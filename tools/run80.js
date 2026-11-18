#!/usr/bin/env node
// Сверка логики i8080 (build/l80/logic.bin) с эталонами ZX по шагам (docs/PORT_PLAN.md, этап 3; образец —
// brucelee-v06c/tools/run80.js). Z80 (tools/zxgold.js) проигрывает эталон; на каждом шаге память ZX
// переносится в память i8080 по раскладке Вектора (build/l80/map.json: блок $7300–$D713 со сдвигом ZS и
// острова), i8080 выполняет `pass`, результат сравнивается с Z80 по всем адресам ZX, которые записал Z80
// или i8080. Ввод — IN E0 (перед ним OUT E5 = старший байт порта ZX, OUT E7 — Kempston), LD A,R — IN E1,
// звук — OUT E2 (сверяется с событиями JS-модели), OUT E4 — «не моделируется» (шаг пропускается).
// Новая игра ($EC2D) сверяется отдельно: i8080 `new_game` с A = тип управления.
//   node tools/run80.js build/golden/g*.jsonl.gz [--max N] [--prof]
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const { loadGolden, Replay, PortQ, LO, HI, ROOT } = require('./zxgold');
const { Mem } = require('../src/model/core');
const game = require('../src/model/game');

const args = process.argv.slice(2);
let maxShow = 5;
const PROF = args.includes('--prof');
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--max') maxShow = +args[++i];
  else if (!args[i].startsWith('--')) files.push(args[i]);
}
const SYM = {};
for (const l of fs.readFileSync(path.join(ROOT, 'build/l80/logic.sym'), 'latin1').split('\n')) {
  const m = l.match(/^([\w.]+):\s+EQU\s+0x([0-9A-F]+)/i); if (m) SYM[m[1]] = parseInt(m[2], 16);
}
const BIN = fs.readFileSync(path.join(ROOT, 'build/l80/logic.bin'));
if (process.env.BREAK80) {                       // негативный контроль: BREAK80=метка+смещение:байт
  const m = process.env.BREAK80.match(/^([\w.]+)\+(\d+):(\d+)$/);
  BIN[SYM[m[1]] + +m[2]] = +m[3];
}
const MAP = JSON.parse(fs.readFileSync(path.join(ROOT, 'build/l80/map.json'), 'utf8'));
const z2v = new Int32Array(0x10000).fill(-1);
for (let a = MAP.block[0]; a < MAP.block[1]; a++) z2v[a] = a - MAP.zs;
for (const [lo, hi, v] of MAP.islands) for (let a = lo; a < hi; a++) z2v[a] = v + a - lo;
const v2z = new Int32Array(0x10000).fill(-1);
for (let a = 0; a < 0x10000; a++) if (z2v[a] >= 0) v2z[z2v[a]] = a;
// не сверяются: след вывода ZX, которого у Вектора нет (адреса экрана/буфера, размеры и указатели кадров —
// их выводу Вектора даёт номер кадра +9), состояние печати, сохранённый SP, звук бипера, цвет дверей
const NOCMP = new Set();
for (let k = 0; k < 6; k++) for (const o of [2, 3, 4, 5, 6, 7, 10, 11]) NOCMP.add(0xE461 + 15 * k + o);
for (const a of [0xE2D2, 0xE2D3, 0xE2D4, 0xDFE1, 0xDFE2, 0xF91B, 0xF91C, 0xFF51, 0xE4C4, 0xE4C5]) NOCMP.add(a);   // $E4C4 — курсор потока (у Вектора — в распакованном буфере)
for (let a = 0xDEF5; a <= 0xDEFA; a++) NOCMP.add(a);
// слова-указатели в память ZX: сравниваются после перевода в адреса Вектора
const PTRW = [0xE862, 0xE4DD, 0xFE25];
const PTR = new Map(); for (const a of PTRW) { PTR.set(a, a); PTR.set(a + 1, a); }

// --- i8080 (ядро vector06js)
const base = process.env.V06JS || path.join(require('os').homedir(), 'projects/vector06js');
const g = { console: { log() {}, debug() {}, warn() {}, error() {}, info() {} } }; g.window = g;
const ctx = vm.createContext(g);
for (const f of ['i8080-js/i8080_trace.js', 'i8080-js/i8080_disasm.js', 'i8080-js/i8080.js'])
  vm.runInContext(fs.readFileSync(path.join(base, f), 'utf8'), ctx, { filename: f });
const mem = new Uint8Array(0x10000);
const written = new Set();
const memory = { read: (a) => mem[a & 0xffff], write: (a, v) => { a &= 0xffff; written.add(a); mem[a] = v & 0xff; } };
class Abort extends Error {}
let S = null;
const SNDN = { 0x10: 'sw0', 0x11: 'sw1', 0x20: 'hit0', 0x21: 'hit1', 0x30: 'ko', 0x40: 'idol', 0x50: 'room' };
const io = {
  input: (p) => {
    p &= 0xff;
    if (p === 0xE0) {
      const want = S.kemp ? 0x001F : (S.hi << 8 | 0xFE);
      S.kemp = false;
      return S.ports.next(want);
    }
    if (p === 0xE1) { if (!S.rq.length) throw new Error('нет LD A,R'); return S.rq.shift(); }
    return 0xff;
  },
  output: (p, v) => {
    p &= 0xff;
    if (p === 0xE5) S.hi = v;
    else if (p === 0xE7) S.kemp = true;
    else if (p === 0xE2) S.snd.push(SNDN[v] || ('?' + v));
    else if (p === 0xE4) throw new Abort(['', 'GAME OVER', 'WINNER', 'F: в меню'][v] || ('E4:' + v));
  },
  commit: () => {}, interrupt: () => {},
};
const cpu = new ctx.I8080(memory, io);
const prof = new Float64Array(0x10000);
let tPass = 0, nPass = 0, tMax = 0;
const tAll = [];
const SENT = 0xFFFE, STACK = SYM.stack_top;

function call80(addr, a) {
  mem[STACK - 1] = SENT >> 8; mem[STACK - 2] = SENT & 0xff;
  cpu.sp = STACK - 2; cpu.pc = addr;
  if (a !== undefined) cpu.regs[7] = a & 0xff;
  let t = 0;
  while (cpu.pc !== SENT) {
    const pc = cpu.pc;
    cpu.instruction();
    t += cpu.vcycles;
    if (PROF) prof[pc] += cpu.vcycles;
    if (t > 2e8) throw new Error('i8080 не вернулся, pc ' + cpu.pc.toString(16));
  }
  return t;
}
function load(zmem) {
  mem.set(BIN.subarray(0, 0x10000 > BIN.length ? BIN.length : 0x10000));
  for (let a = 0; a < 0x10000; a++) { const v = z2v[a]; if (v >= 0) mem[v] = zmem[a]; }
  for (const p of MAP.ptrs) { /* таблицы указателей — из образа (уже в адресах Вектора) */ mem[z2v[p]] = BIN[z2v[p]]; mem[z2v[p] + 1] = BIN[z2v[p] + 1]; }
  for (const a of PTRW) {                        // указатели-переменные: в адреса Вектора
    const w = zmem[a] | zmem[a + 1] << 8, v = z2v[w];
    if (v >= 0) { mem[z2v[a]] = v & 0xff; mem[z2v[a] + 1] = v >> 8; }
  }
  written.clear();
}
const hex = (a) => '$' + a.toString(16).toUpperCase().padStart(4, '0');
function compare(zreal, zaddrs) {
  const diffs = [], seen = new Set();
  const addrs = new Set(zaddrs);
  for (const v of written) { const z = v2z[v]; if (z >= 0) addrs.add(z); else if ((v < STACK - 0x100 || v >= STACK) && (v < SYM.scratch || v >= SYM.scratch_end) && (v < SYM.roombuf || v >= SYM.roombuf_end)) diffs.push(`запись вне карты ${hex(v)}`); }
  for (const a of [...addrs].sort((x, y) => x - y)) {
    if (a < LO || a >= HI || NOCMP.has(a)) continue;
    if (PTR.has(a)) {
      const b = PTR.get(a); if (seen.has(b)) continue; seen.add(b);
      const zw = zreal[b] | zreal[b + 1] << 8, vw = mem[z2v[b]] | mem[z2v[b] + 1] << 8;
      if (z2v[zw] !== vw) diffs.push(`${hex(b)} ZX ${hex(zw)} i8080 ${hex(vw)}(${v2z[vw] >= 0 ? hex(v2z[vw]) : '?'})`);
      continue;
    }
    if (z2v[a] < 0) { diffs.push(`${hex(a)} нет на Векторе (ZX ${zreal[a].toString(16)})`); continue; }
    if (mem[z2v[a]] !== zreal[a]) diffs.push(`${hex(a)} ZX ${zreal[a].toString(16)} i8080 ${mem[z2v[a]].toString(16)}`);
  }
  return diffs;
}

function runOne(file) {
  const gd = loadGolden(file);
  if (!gd.init.fixes) { console.log(`${gd.name}: оригинал — пропуск`); return true; }
  const rp = new Replay(gd);
  let bad = 0, run = 0, shown = 0, ng = 0, ngBad = 0;
  const why = {};
  let snap = null;
  rp.onStep = (pc) => { if (pc === 0xEC2D) snap = { ram: rp.mem.slice(), a: rp.cpu.get_a() }; return false; };
  for (const st of gd.steps) {
    const z0 = rp.mem.slice();
    // JS-модель: события звука и «не моделируется»
    const M = new Mem(z0.slice()); M.ports = new PortQ(st.in); M.rq = st.r.slice();
    let merr = null; try { game.pass(M); } catch (e) { merr = e; }
    // i8080
    load(z0);
    S = { ports: new PortQ(st.in), rq: st.r.slice(), snd: [], hi: 0, kemp: false };
    let err = null, t = 0;
    try { t = call80(SYM.pass); } catch (e) { err = e; }
    rp.pass(st, 5e7, false);
    const real = rp.mem;
    if (snap) {
      const zs = snap.ram, sa = snap.a; snap = null;
      load(zs);
      S = { ports: new PortQ([]), rq: [], snd: [], hi: 0, kemp: false };
      let e2 = null; try { call80(SYM.new_game, sa); } catch (e) { e2 = e; }
      ng++;
      const all = []; for (let a = LO; a < HI; a++) if (zs[a] !== real[a] || written.has(z2v[a])) all.push(a);
      const d2 = e2 ? ['исключение: ' + e2.message] : compare(real, all);
      if (d2.length) { ngBad++; if (shown++ < maxShow) console.log(`  новая игра (шаг ${st.step}): ${d2.length} расхождений: ${d2.slice(0, 10).join('; ')}`); }
    }
    if (merr && merr.notModeled) {
      if (!(err instanceof Abort) && shown++ < maxShow) console.log(`  шаг ${st.step}: модель — «${merr.message}», i8080 — ${err ? err.message : 'прошёл'}`);
      if (!(err instanceof Abort)) bad++;
      why[merr.message] = (why[merr.message] || 0) + 1; rp.apply(st.pre); continue;
    }
    run++;
    let diffs;
    if (err) diffs = [`исключение: ${err instanceof Abort ? 'не моделируется ' + err.message : err.stack.split('\n').slice(0, 2).join(' | ')}`];
    else {
      diffs = compare(real, st.d.map((x) => x[0]));
      if (S.ports.left()) diffs.push(`портов осталось ${S.ports.left()}`);
      if (S.rq.length) diffs.push(`LD A,R осталось ${S.rq.length}`);
      const ms = M.snd.map((s) => s[0]).join(','), is = S.snd.join(',');
      if (ms !== is) diffs.push(`звук: модель ${ms} i8080 ${is}`);
      tPass += t; nPass++; tAll.push(t); if (t > tMax) tMax = t;
    }
    rp.apply(st.pre);
    if (diffs.length) {
      bad++;
      if (shown++ < maxShow) console.log(`  шаг ${st.step}: ${diffs.length} расхождений: ${diffs.slice(0, 10).join('; ')}`);
    }
  }
  console.log(`${gd.name}: шагов ${gd.steps.length}, сверено ${run}, расхождений ${bad}, без модели ${JSON.stringify(why)}; новых игр ${ng}, расхождений ${ngBad}`);
  return bad === 0 && ngBad === 0;
}
let ok = true;
for (const f of files) ok = runOne(f) && ok;
if (nPass) { tAll.sort((a, b) => a - b); const q = (p) => tAll[Math.floor(p * (tAll.length - 1))];
  console.log(`такты i8080 на проход: p50 ${q(0.5)}, p90 ${q(0.9)}, p99 ${q(0.99)}, наибольшее ${tMax} (кадр Вектора 59904)`); }
if (PROF) {
  const labs = Object.entries(SYM).filter(([k, v]) => v < 0x8414 && !k.startsWith('zv_') && !k.includes('.')).sort((a, b) => a[1] - b[1]);
  const per = new Map();
  for (let a = 0; a < 0x10000; a++) if (prof[a]) {
    let lo = 0, hi = labs.length - 1, n = '?';
    while (lo <= hi) { const m = (lo + hi) >> 1; if (labs[m][1] <= a) { n = labs[m][0]; lo = m + 1; } else hi = m - 1; }
    per.set(n, (per.get(n) || 0) + prof[a]);
  }
  const tot = [...per.values()].reduce((x, y) => x + y, 0);
  for (const [n, t] of [...per].sort((a, b) => b[1] - a[1]).slice(0, 25)) console.log(`  ${n.padEnd(20)} ${(100 * t / tot).toFixed(1)} %`);
}
process.exit(ok ? 0 : 1);
