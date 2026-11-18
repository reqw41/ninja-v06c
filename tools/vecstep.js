#!/usr/bin/env node
// Боевой образ Вектора по эталонам ZX (docs/PORT_PLAN.md, этап 4): логика и вывод build/vec/ninja_t.bin (шрифт
// ZX — только для этой сверки) идут шаг в шаг с Z80 (tools/zxgold.js): перед проходом память игры ZX
// переносится в память Вектора по раскладке (tools/mkl80.py), экран и состояние вывода Вектора остаются свои.
// Ввод — перехваты zx_in / zx_kemp (очереди эталона), ожидание кадра — пропуск. После прохода экран Вектора
// сравнивается с экраном ZX: клетка = точки ZX, раскрашенные атрибутом ZX (плоскости A000/C000/E000 = биты
// 2/1/0 цвета). Отдельно — поле (строки 0..20) и HUD (21..23).
//   node tools/vecstep.js build/golden/g0_play.jsonl.gz [...] [--max N] [--shots каталог] [--from шаг]
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const { loadGolden, Replay, PortQ, ROOT } = require('./zxgold');

const args = process.argv.slice(2);
let maxShow = 5, shots = null, from = 0;
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--max') maxShow = +args[++i];
  else if (args[i] === '--shots') shots = args[++i];
  else if (args[i] === '--from') from = +args[++i];
  else files.push(args[i]);
}
const IMG = process.env.VECIMG || 'build/vec/ninja_t';
const SYM = {};
for (const l of fs.readFileSync(path.join(ROOT, IMG + '.sym'), 'latin1').split('\n')) {
  const m = l.match(/^([\w.]+):\s+EQU\s+0x([0-9A-F]+)/i); if (m) SYM[m[1]] = parseInt(m[2], 16);
}
const BIN = fs.readFileSync(path.join(ROOT, IMG + '.bin'));
const BANDJ = JSON.parse(fs.readFileSync(path.join(ROOT, 'src/vec/gen/band.json'), 'utf8'));
const PENIDX = JSON.parse(fs.readFileSync(path.join(ROOT, 'src/vec/gen/pen_idx.json'), 'utf8'));
const CPCRAM = fs.existsSync(path.join(ROOT, 'build/cpcrun/dump/ram.bin')) ? fs.readFileSync(path.join(ROOT, 'build/cpcrun/dump/ram.bin')) : null;
const MAP = JSON.parse(fs.readFileSync(path.join(ROOT, 'build/l80/map.json'), 'utf8'));
const z2v = new Int32Array(0x10000).fill(-1);
for (let a = MAP.block[0]; a < MAP.block[1]; a++) z2v[a] = a - MAP.zs;
for (const [lo, hi, v] of MAP.islands) for (let a = lo; a < hi; a++) z2v[a] = v + a - lo;
const PTRS = new Set(); for (const p of MAP.ptrs) { PTRS.add(p); PTRS.add(p + 1); }
const PTRW = [0xE862, 0xE4DD, 0xFE25];

const base = process.env.V06JS || path.join(require('os').homedir(), 'projects/vector06js');
const g = { console: { log() {}, debug() {}, warn() {}, error() {}, info() {} } }; g.window = g;
const ctx = vm.createContext(g);
for (const f of ['i8080-js/i8080_trace.js', 'i8080-js/i8080_disasm.js', 'i8080-js/i8080.js'])
  vm.runInContext(fs.readFileSync(path.join(base, f), 'utf8'), ctx, { filename: f });
const mem = new Uint8Array(0x10000);
const memory = { read: (a) => mem[a & 0xffff], write: (a, v) => { mem[a & 0xffff] = v & 0xff; } };
class Abort extends Error {}
const io = { input: () => 0xff, output: () => {}, commit: () => {}, interrupt: () => {} };
const cpu = new ctx.I8080(memory, io);
let S = null;
const HOOK = new Map([
  [SYM.zx_in, () => { cpu.regs[7] = S.ports.next(cpu.regs[7] << 8 | 0xFE); }],
  [SYM.zx_kemp, () => { cpu.regs[7] = S.ports.next(0x001F); }],
  [SYM.plat_sound, () => {}],
  [SYM.plat_game_over, () => { throw new Abort('GAME OVER'); }],
  [SYM.plat_winner, () => { throw new Abort('WINNER'); }],
  [SYM.plat_menu, () => { throw new Abort('F: в меню'); }],
]);
const DRAW = SYM.plat_draw;
const SENT = 0xFFFE;
let curStep = -1;
let T80 = 0;
const CNTS = {};
const PL = [];
const PROF = !!process.env.PROF, PROFA = new Float64Array(0x10000), PROFB = new Float64Array(0x10000);
const TP = [];
// AZERO: плоскость A000 фона пуста? (клетки комнаты по строкам; клетки под бойцами при выводе)
function stA(cell, pl) { const d = SYM.cdesc + 3 * cell, s = mem[d + pl]; const a = s < SYM.NA ? SYM.pool_a + 8 * s : SYM.POOL_B + 8 * (s - SYM.NA); for (let k = 0; k < 8; k++) if (mem[a + k]) return false; return true; }
function azDump() { const rows = []; for (let r = 0; r < 21; r++) { let z = 0; for (let c = 1; c <= 30; c++) if (stA(mem[SYM.CMAP + (c - 1) * 21 + r], 0)) z++; rows.push(z); } console.log('A0 по строкам карты (из 30):', rows.join(' ')); }
const AZ = { span: 0, zero: 0 };
function azSpan() { const col = mem[SYM.rc_col], lo = mem[SYM.rc_lo], hi = mem[SYM.rc_hi]; let all = true; for (let i = hi; i >= lo; i -= 8) { const rr = 23 - ((i >> 3) & 31); const cell = mem[SYM.CMAP + (col - 1) * 21 + rr]; AZ.span++; (AZ.rr = AZ.rr || Array(21).fill(0))[rr]++; if (stA(cell, 0)) AZ.zero++; else all = false; } AZ.cols = (AZ.cols || 0) + 1; if (all) AZ.call = (AZ.call || 0) + 1; }
process.on('exit', () => { if (process.env.POOLMAX) console.log('pool', JSON.stringify(globalThis.__pm), 'NS_MAX', SYM.NS_MAX, 'NC_MAX', SYM.NC_MAX); if (process.env.TOPS) console.log('tops', JSON.stringify(globalThis.__tops)); if (process.env.HDBG) console.log('h', JSON.stringify(globalThis.__h)); if (process.env.CHARS) console.log('chars', [...(globalThis.__ch||[])].sort((a,b)=>a-b).map(c=>c+':'+String.fromCharCode(c&127)).join(' ')); if (process.env.CELLCNT) console.log('cells', JSON.stringify(CNTS)); if (process.env.BANDDBG) console.log('band', JSON.stringify(CNTS)); if (process.env.AZERO) console.log('клеток под бойцами', AZ.span, 'из них A000 пусто', AZ.zero, (100 * AZ.zero / (AZ.span || 1)).toFixed(0) + '%', 'столбцов', AZ.cols, 'целиком пусто', AZ.call, (100 * AZ.call / (AZ.cols || 1)).toFixed(0) + '%', 'az_cc', AZ.cc, 'пропуск A000', AZ.cc0, '\nстроки клеток под бойцами:', (AZ.rr || []).join(' ')); });
const RM = process.env.RMODEL ? require('./rmodel').make(SYM) : null; let RMP = null, RMBAD = 0; const RMS = [];
process.on('exit', () => { if (!RM) return; const bad = RMS.filter((r) => r[2]).length; console.log('rmodel: вызовов', RMS.length, 'с расхождением', bad);
  if (process.env.RMDUMP) fs.writeFileSync(process.env.RMDUMP, JSON.stringify(RMS.map((r) => [r[0], r[1]]))); });

// SPANEST: оценка — рисовать в столбце только строки силуэтов (старых disp и новых cur) изменившихся бойцов
const SE = { full: 0, dirty: 0, rowsFull: 0, rowsDirty: 0, calls: 0 };
function colRows(e, col) {   // строки i (множество отрезков) силуэта записи e в столбце экрана col
  const out = []; if (!mem[e]) return out;
  const col0 = mem[e + 1], top0 = mem[e + 3], w = mem[e + 4], hdr = mem[e + 5] | mem[e + 6] << 8, s = mem[e + 7] & 7;
  const d = (col - col0) & 0xFF; if (d >= w) return out;
  const wv = mem[hdr + 1];
  const dc = [d]; if (s && d >= 1) dc.push(d - 1);
  for (const c of dc) { if (c >= wv) continue; const h = hdr + 6 + 4 * c; const r0 = mem[h + 2], n = mem[h + 3]; if (!n) continue;
    const top = (top0 - r0) & 0xFF, bot = (top - n + 1) & 0xFF; out.push([bot, top]); }
  return out;
}
function spanEst() {
  if (mem[SYM.spr_m] !== ((mem[SYM.zv_F924] & 1))) return;
  let lo = mem[SYM.rb_lo]; if (lo < 24) lo = 24; lo &= 0xF8; let hi = mem[SYM.rb_hi]; if (hi >= 200) hi = 199; hi |= 7; if (hi < lo) return;
  let c1 = mem[SYM.rb_c1]; if (c1 >= 32) c1 = 31;
  const ch = []; for (let k = 0; k < 6; k++) { let diff = false; for (let q = 0; q < 8; q++) if (mem[SYM.cur + 8 * k + q] !== mem[SYM.disp + 8 * k + q]) diff = true; if (diff) ch.push(k); }
  if (!ch.length) return;
  SE.calls++;
  for (let col = mem[SYM.rb_c0]; col < c1; col++) {
    const dirty = new Uint8Array(256);
    for (const k of ch) for (const base of [SYM.cur, SYM.disp]) for (const [b, t] of colRows(base + 8 * k, col)) for (let i = b; i <= t; i++) dirty[i & 0xFF] = 1;
    const cells = new Set(); for (let i = lo; i <= hi; i++) if (dirty[i]) cells.add(i >> 3);
    SE.full += (hi - lo + 1) >> 3; SE.dirty += cells.size;
    const inD = (i) => cells.has(i >> 3);
    for (let k = 0; k < 6; k++) for (const [b, t] of colRows(SYM.cur + 8 * k, col)) for (let i = Math.max(b, lo); i <= Math.min(t, hi); i++) { SE.rowsFull++; if (inD(i)) SE.rowsDirty++; }
  }
}
process.on('exit', () => { if (process.env.SPANEST) console.log('SPANEST: rect', SE.calls, 'клеток', SE.full, '->', SE.dirty, (100 * SE.dirty / SE.full).toFixed(0) + '%', '| строк наложения', SE.rowsFull, '->', SE.rowsDirty, (100 * SE.rowsDirty / SE.rowsFull).toFixed(0) + '%'); });
function call80(addr, regs) {
  const sp = SYM.STACK || 0xA000;
  mem[sp - 1] = SENT >> 8; mem[sp - 2] = SENT & 0xff;
  cpu.sp = sp - 2; cpu.pc = addr;
  const idx = { b: 0, c: 1, d: 2, e: 3, h: 4, l: 5, a: 7 };
  for (const k of Object.keys(regs || {})) cpu.regs[idx[k]] = regs[k] & 0xff;
  let n = 0;
  while (cpu.pc !== SENT) {
    const pc0 = cpu.pc;
    const h = HOOK.get(cpu.pc);
    if (h) { h(); cpu.pc = mem[cpu.sp] | mem[cpu.sp + 1] << 8; cpu.sp = (cpu.sp + 2) & 0xffff; continue; }
    if (process.env.NAMES && cpu.pc === SYM.plat_name) console.log('name', curStep, cpu.regs[0], cpu.regs[1], 'color', mem[SYM.pr_color]);
    if (process.env.CNT && (cpu.pc === SYM.cpc_decode || cpu.pc === SYM.rect_draw || cpu.pc === SYM.col_draw)) CNTS[cpu.pc] = (CNTS[cpu.pc] || 0) + 1;
    if (process.env.SPAN && cpu.pc === SYM.col_draw) { const col = mem[SYM.rc_col], lo = mem[SYM.rc_lo], hi = mem[SYM.rc_hi]; let a = 255, b = 0; for (let k = 0; k < 6; k++) { const e = SYM.cur + 8 * k; if (!mem[e]) continue; const d = (col - mem[e + 1]) & 255; if (d < mem[e + 4]) { a = Math.min(a, mem[e + 2]); b = Math.max(b, mem[e + 3]); } } const tot = hi - lo + 1; let inr = 0; if (b >= a) { const x0 = Math.max(lo, a & ~7), x1 = Math.min(hi, b | 7); if (x1 >= x0) inr = x1 - x0 + 1; } CNTS.tot = (CNTS.tot || 0) + tot; CNTS.rp = (CNTS.rp || 0) + tot; CNTS.inr = (CNTS.inr || 0) + inr; CNTS.ip = (CNTS.ip || 0) + inr; }
    if (process.env.CHARS && cpu.pc === SYM.pr_char) { const ch = cpu.regs[7] & 0xFF; (globalThis.__ch = globalThis.__ch || new Set()).add(ch); }
    if (process.env.HDBG && cpu.pc === SYM.cd_chk) { const B = cpu.regs[0], lo = mem[SYM.er_lo], hi = mem[SYM.er_hi]; const k = (B >= lo && B <= hi) ? 'inEr' : 'outEr'; (globalThis.__h = globalThis.__h || {})[k] = (globalThis.__h[k] || 0) + 1; if (!globalThis.__e && k==='inEr' && Math.random() < 0.001) { globalThis.__e = 1; console.log('dbg B', B, 'er', lo, hi, 'sp', mem[SYM.sp_lo], mem[SYM.sp_hi], 'rc', mem[SYM.rc_lo], mem[SYM.rc_hi]); } }
    if (process.env.HDBG && cpu.pc === SYM.col_draw) { const h = mem[SYM.rc_hi] - mem[SYM.rc_lo]; const b = h < 24 ? '<24' : h > 160 ? '>160' : 'mid'; (globalThis.__h = globalThis.__h || {})[b] = (globalThis.__h[b] || 0) + 1; }
    if (process.env.CELLCNT) { if (cpu.pc === SYM.cd_cell) CNTS.cells = (CNTS.cells || 0) + 1; if (cpu.pc === SYM['cd_cell.scr']) { CNTS.scr = (CNTS.scr || 0) + 1;
        const col = mem[SYM.rc_col], i = mem[SYM.cd_i]; let old = false; for (let k = 0; k < 6; k++) { const e = SYM.disp + 8 * k; if (!mem[e]) continue; const d = (col - mem[e + 1]) & 255; if (d < mem[e + 4] && i >= (mem[e + 2] & ~7) && i - 7 <= mem[e + 3]) old = true; } for (let j = 0; j < 3; j++) { const v = SYM.pdisp + 5 * j; if (mem[v] && ((mem[v + 1] >> 3) === col || (mem[v + 1] >> 3) + 1 === col)) old = true; } if (old) CNTS.scrOld = (CNTS.scrOld || 0) + 1; }
      if (cpu.pc === SYM.col_draw) CNTS.cols = (CNTS.cols || 0) + 1; }
    if (process.env.BANDDBG) { if (cpu.pc === SYM.cd_band) { CNTS.cdb = (CNTS.cdb || 0) + 1; if (mem[SYM.band_ok]) CNTS.cdbok = (CNTS.cdbok || 0) + 1; } if (cpu.pc === SYM.cs_go) CNTS.cs = (CNTS.cs || 0) + 1; if (cpu.pc === SYM.bo_calc) CNTS.bo = (CNTS.bo || 0) + 1; }
    if (process.env.AZERO && cpu.pc === SYM.cb_idol) azDump();
    if (process.env.AZDBG && cpu.pc === SYM.az_cc && mem[SYM.a_nz] && (AZ.dbg = (AZ.dbg || 0) + 1) < 6) { const col = mem[SYM.rc_col], lo = mem[SYM.rc_lo], hi = mem[SYM.rc_hi]; const ids = []; for (let i = hi; i >= lo; i -= 8) { const rr = 23 - ((i >> 3) & 31); const cell = mem[SYM.CMAP + (col - 1) * 21 + rr]; ids.push(rr + ':' + mem[SYM.cdesc + 3 * cell] + (stA(cell, 0) ? 'z' : '')); } console.log('a_nz', mem[SYM.a_nz], 'col', col, lo, hi, ids.join(' ')); }
    if (process.env.AZERO && cpu.pc === SYM.az_cc) { AZ.cc = (AZ.cc || 0) + 1; if (!mem[SYM.a_nz]) AZ.cc0 = (AZ.cc0 || 0) + 1; }
    if (process.env.AZERO && cpu.pc === SYM.ov_proj) azSpan();
    if (process.env.RECTLOG && cpu.pc === SYM.rect_draw) (globalThis.__rl = globalThis.__rl || []).push([mem[SYM.rb_c0], mem[SYM.rb_c1], mem[SYM.rb_lo], mem[SYM.rb_hi], T80]);
    if (process.env.ROWCNT) { const R = (globalThis.__rc = globalThis.__rc || { p: {} }); const pp = R.cur = R.cur || {};
      if (cpu.pc === SYM.contrib) { pp.calls = (pp.calls || 0) + 1; pp['s' + mem[SYM.a_s]] = (pp['s' + mem[SYM.a_s]] || 0) + 1; }
      if (cpu.pc === SYM.cb_r) { pp.rows = (pp.rows || 0) + 1; pp['r' + mem[SYM.a_s]] = (pp['r' + mem[SYM.a_s]] || 0) + 1; }
      if (cpu.pc === SYM.ct_pc) pp.op = (pp.op || 0) + 1;
      if (cpu.pc === SYM.cd_cell) pp.cells = (pp.cells || 0) + 1; if (cpu.pc === SYM.c0_r) pp.c0 = (pp.c0 || 0) + 1; if (cpu.pc === SYM.cs_r) pp.cs = (pp.cs || 0) + 1; if (cpu.pc === SYM.cs_r && mem[SYM['cs_m1'] + 1] === 0xFF) pp.cs0 = (pp.cs0 || 0) + 1; if (cpu.pc === SYM.st_find) pp.stf = (pp.stf || 0) + 1; if (cpu.pc === SYM.cb_build) pp.cbb = (pp.cbb || 0) + 1; if (cpu.pc === SYM.cell_draw) pp.celld = (pp.celld || 0) + 1; }
    if (process.env.SPANEST && cpu.pc === SYM.rect_draw) spanEst();
    if (process.env.CDLOG && cpu.pc === SYM.cell_draw && globalThis.__st === +process.env.CDLOG) console.log('cell_draw', mem[SYM.pr_cell] | mem[SYM.pr_cell + 1] << 8, 'room', mem[SYM.zv_E4BB]);
    if (cpu.pc === DRAW) mem[SYM.frames] = (mem[SYM.last_draw] + 8) & 0xff;      // ожидание кадра — пропуск
    if (process.env.POOLMAX && cpu.pc === SYM.bo_calc) { const r = mem[SYM.zv_E4BB]; const v = [mem[SYM.cb_ns], mem[SYM.cb_nc]]; const P = (globalThis.__pm = globalThis.__pm || {}); if (!P[r] || P[r][0] < v[0] || P[r][1] < v[1]) P[r] = [Math.max(v[0], (P[r] || [0])[0]), Math.max(v[1], (P[r] || [0, 0])[1])]; }
    if (RM && cpu.pc === SYM.rect_draw && !RMP) { const cl = mem.slice(); const cnt = RM.rectDraw(cl); RMP = { ret: mem[cpu.sp] | mem[cpu.sp + 1] << 8, sp: cpu.sp, cl, cnt, t0: T80 }; }
    const anz0 = process.env.AZW ? mem[SYM.a_nz] : 0;
    const W = process.env.WATCH && globalThis.__st === +process.env.WSTEP ? process.env.WATCH.split(',').map((x) => parseInt(x, 16)) : null; const wv = W ? W.map((x) => mem[x]) : null;
    cpu.instruction();
    if (W) W.forEach((x, k) => { if (mem[x] !== wv[k]) console.log('watch', x.toString(16), wv[k].toString(16), '->', mem[x].toString(16), 'pc', pc0.toString(16), 'rc_col', mem[SYM.rc_col], 'sp', mem[SYM.sp_lo], mem[SYM.sp_hi]); });
    if (process.env.AZW && mem[SYM.a_nz] !== anz0 && (AZ.w = (AZ.w || 0) + 1) < 15) console.log('a_nz', anz0, '->', mem[SYM.a_nz], 'pc', pc0.toString(16));
    T80 += cpu.vcycles;
    if (RMP && cpu.pc === RMP.ret && cpu.sp === RMP.sp + 2) { let bad = 0; for (let x = 0xA000; x < 0x10000; x++) if (mem[x] !== RMP.cl[x]) bad++; RMS.push([RMP.cnt, T80 - RMP.t0, bad]); if (bad && RMBAD++ < 3) console.log('rmodel: расхождение', bad, 'байт, rect', [0, 1, 2, 3].map((q) => mem[SYM.rb_c0 + q]).join(',')); RMP = null; }
    if (PROF) PROFB[pc0] += cpu.vcycles;
    if (++n > 5e7) throw new Error('не вернулся, pc ' + cpu.pc.toString(16));
  }
}
// вид CPC: на месте спрайтов ZX ($8D8C–$D00B) у Вектора кадры CPC, на месте тайлов — тайлы 6 точек, карта —
// своя (без стен ZX, со своими тайлами дыр и идола): не переносить; экран комнаты строит room_build Вектора
const CPC = SYM.cpc_frp !== undefined;
function load(z) {
  for (let a = 0; a < 0x10000; a++) { const v = z2v[a]; if (v >= 0 && !PTRS.has(a) && !(CPC && ((a >= 0x8AB7 && a < 0x8D57) || (a >= 0x8D8C && a < 0xD714)))) mem[v] = z[a]; }
  for (const a of PTRW) { const w = z[a] | z[a + 1] << 8, v = z2v[w]; if (v >= 0) { mem[z2v[a]] = v & 0xff; mem[z2v[a] + 1] = v >> 8; } }
}
// экран ZX -> ожидаемые плоскости; сравнение по клеткам
const zaddr = (L, c) => 0x4000 | ((L & 0xC0) << 5) | ((L & 7) << 8) | ((L & 0x38) << 2) | c;
// эталон поля ×1.5 по памяти ZX (как tools/geom15.py): карта 40 x 21 из потоков, тайлы — точки ZX 0,1,3,4,6,7,
// дыры и идол поверх тайлов, атрибуты $E37E | $40 с перекрасками ZX и таблицами цветов CPC; -> 3 плоскости 32 x 168
function field40(z) {
  const w = (a) => z[a] | z[a + 1] << 8, room = z[0xE4BB];
  const m = Array.from({ length: 21 }, () => new Array(40).fill(0));
  const stream = (p, cells, col, row) => {
    let vis = 0;
    for (;;) {
      let a = z[p++], reps = 1;
      if (a === 0xFF) { a = z[p]; reps = z[p + 1] + 1; p += 2; }
      for (let k = 0; k < reps; k++) {
        if (++col >= 40) { col = 0; row++; }
        if (row >= 0 && row < 21) m[row][col] = a;
        if (col >= 4 && col < 36 && ++vis === cells) return;
      }
    }
  };
  stream(w(0xD9DE + 2 * room), 480, 0x27, -1);
  stream(0x7808, 200, 0x1B, 14);
  for (const [side, base, c0] of [[0, 0x8134, 0], [1, 0x8158, 36]])
    if (!z[0xD897 + 4 * room + side]) for (let y = 0; y < 15; y++) for (let k = 0; k < 4; k++) m[2 + y][c0 + k] = z[base + 40 * y + k];
  // нижняя линия пола на 8 строк ниже (fl_patch, 16.11): ряд 19 — тайл 0, концы диагоналей 7 / 8; ряд 20 — тайл 9, диагонали 12 / 13
  m[19].fill(0); m[20].fill(9); m[19][7] = 7; m[19][32] = 8; m[20][6] = 12; m[20][33] = 13;
  const at = m.map((r) => r.map((t) => z[0xE37E + t] | 0x40));
  let rl = [0, 1, 2, 3, 4, 5].find((k) => z[0xEB56 + k] === room);   // $EB68 берёт строки/адрес с конца списка: 5 - k
  if (rl !== undefined) rl = 5 - rl;
  if (rl !== undefined) { const r0 = (w(0xEB5C + 2 * rl) - 0x5800) >> 5; for (let r = r0; r < r0 + z[0xEB50 + rl]; r++) for (let c = 0; c < 40; c++) { const a = at[r][c]; if (a >= 0x68 && a < 0x70) at[r][c] = (a & 0xC7) | 8; } }
  if (room === 0) for (let r = 4; r <= 10; r++) for (let c = 0; c < 40; c++) at[r][c] = (at[r][c] & 0xC7) + 8 * (r - 3);
  if (room === 19 || room === 20) for (let r = 5; r < 13; r++) for (let c = 16; c < 24; c++) at[r][c] = room === 20 ? 0x60 : 0x50;
  const keep6 = (b) => [0, 1, 3, 4, 6, 7].reduce((v, k, j) => v | ((b >> (7 - k)) & 1) << (7 - j), 0);
  const gfx = (t, y) => keep6(z[0xD00C + 8 * t + y]);
  const ov = new Map();                          // (строка, столбец 40) -> узор 8 строк (8 бит ZX)
  const hole = (X, base, R0) => { for (let rr = 0; rr < 2; rr++) for (let d = 0; d < 5; d++) { const pat = []; for (let c = 8 * rr; c < 8 * rr + 8; c++) pat.push(d === 0 ? z[base + (c < 8 ? c : c + 8)] : d === 4 ? z[base + (c + 8 < 16 ? c + 8 : c + 16)] : 0xFF); ov.set((R0 + rr) * 40 + X + 4 + d, { pat, idol: false }); } };
  if (z[0xE4D9]) hole(z[0xE4D9], 0xDBFF, 0);
  if (z[0xE4DA]) hole(z[0xE4DA], 0xDBDF, 19);
  // идол — как на момент вывода (логика берёт его после вывода, $F554)
  // идол CPC (владелец 15.11): строка 19, силуэт ct_idol (перо 3 -> жёлтый номер комнаты), узор ct_idolb (перо 1)
  if (mem[SYM.idol_on]) { const X = mem[SYM.idol_col] & 31; for (let k = 0; k < 3; k++) { const py = [], pb = []; for (let y = 0; y < 8; y++) { py.push(mem[SYM.ct_idol + 3 + 11 * k + 3 + y]); pb.push(mem[SYM.ct_idolb + 3 + 11 * k + 3 + y]); } ov.set(19 * 40 + X + 4 + k, { py, pb, idol: true }); } }
  if (process.env.DUMPA && !globalThis.__d) { globalThis.__d = 1; const MA = SYM.MARG_A, MT = SYM.MARG_T, AM = SYM.AMAP, MV = SYM.MAP_V;
    for (let r = 0; r < 21; r++) console.log(r, 'ref', at[r].map((x) => x.toString(16)).join(' '), '\n   vec', [...Array(40)].map((_, c) => (c < 4 ? mem[MA + 8 * r + c] : c < 36 ? mem[AM + 32 * r + c - 4] : mem[MA + 8 * r + c - 32]).toString(16)).join(' ')); }
  // комнаты CPC (владелец 15.11): тайлы $4721 и перекраска строк $7A31 из снимка памяти CPC (build/cpcrun/dump/ram.bin),
  // точка n из 6 = точка CPC 2n / 3; дыра — перо 1, идол — перо | 3; перо -> номер палитры — pen_idx генератора
  const R8 = CPCRAM, w8 = (a) => R8[a] | R8[a + 1] << 8;
  const lp = (v) => (v >> 7 & 1) | (v >> 2 & 2) | (v >> 3 & 4) | (v << 2 & 8);
  // диагонали пола — свои тайлы (tools/cpcroom.py DIAG, 17.11): точка x строки y, 12/13 — с линией внизу
  const D7 = [5, 4, 3, 3, 2, 1, 0, 0], DIAG = { 7: D7, 8: D7.map((x) => 5 - x), 12: D7, 13: D7.map((x) => 5 - x) };
  const pen6 = (tl, y, x) => (x === DIAG[tl][y] || (y === 7 && (tl === 12 || tl === 13))) ? 2 : 0;
  const pen4 = (tl, y, cx) => { if (tl === 0xA0) { if (room === 1) return 2; tl = 0x9C; } const v = R8[0x4721 + 16 * tl + 2 * y + (cx >> 1)]; return lp(cx & 1 ? (v << 1) & 0xFF : v) & 3; };
  const maps = []; for (let y = 0; y < 168; y++) maps.push([0, 1, 2, 3]);
  for (let q = w8(0x7A31 + 2 * room); R8[q]; q += 4) { const c = R8[q], nb = R8[q + 1], f = lp(R8[q + 2]), tt = lp(R8[q + 3]);
    for (let i = 0; i < nb; i++) { const y = 199 - c + i; if (y >= 0 && y < 168) maps[y] = maps[y].map((v) => v === f ? tt : v); } }
  const pidx = (p) => PENIDX[room][p];
  const ex = [new Uint8Array(32 * 176), new Uint8Array(32 * 176), new Uint8Array(32 * 176)];
  // строка клеток 21 (строки 168..175) — серый пол под комнатой (номер 1: E000), владелец 16.11
  for (let L = 168; L < 176; L++) for (let c = 1; c < 31; c++) ex[2][L * 32 + c] = 0xFF;
  for (let L = 0; L < 168; L++) {
    const R = L >> 3, y = L & 7;
    for (let n = 0; n < 240; n++) {
      const t = (n / 6) | 0, x = n % 6, o = ov.get(R * 40 + t);
      let pen = DIAG[m[R][t]] ? pen6(m[R][t], y, x) : pen4(m[R][t], y, (2 * x / 3) | 0);
      let yel = false;
      if (o && !o.idol && (keep6(o.pat[y]) >> (7 - x) & 1)) pen = 1;
      if (o && o.idol) { if (o.pb[y] >> (7 - x) & 1) pen = 1; else if (o.py[y] >> (7 - x) & 1) yel = true; }   // узор — чёрное перо 1
      // полоса пола (строки 112..167): перо тайла 2 (линии пола) и силуэт идола — номер 5 в A000 (владелец 16.11,
      // вариант Б); где цвет линии = оранжевый бойцов — номер 2 в C000 (владелец 17.11, src/vec/gen/band.json)
      const n5 = BANDJ[room] ? 2 : 5;
      const ys = yel ? n5 : undefined;
      const col = ys !== undefined ? ys : L >= 112 && pen === 2 && !yel ? n5 : pidx(maps[L][yel ? 3 : pen]);
      const X = n + 8, c = X >> 3, b = 0x80 >> (X & 7);
      for (let pl = 0; pl < 3; pl++) if (col >> (2 - pl) & 1) ex[pl][L * 32 + c] |= b;
    }
  }
  return ex;
}
function compare(z) {
  const bad = { field: [], hud: [], proj: 0, rect: 0 };
  // прямоугольники копирования бойцов ZX ($E9B1: 7 байт x 60/66 строк от +A/+B; лежащий $EA43: 8 x 64 от $4880+X-2):
  // ZX режет ими спрайты и затирает HUD (в заднем буфере там пусто), Вектор рисует бойцов целиком
  const rc = new Set();
  const line = (a) => ((a >> 8) & 7) | ((a >> 2) & 0x38) | ((a >> 5) & 0xC0);
  const addr = (a0, w, n) => { const c0 = a0 & 31, L0 = line(a0); for (let L = L0; L < L0 + n && L < 192; L++) for (let c = c0; c < c0 + w && c < 32; c++) rc.add((L >> 3) * 32 + c); };
  for (let k = 0; k < 6; k++) {
    const r = 0xE461 + 15 * k, st = z[r + 8];
    if (st === 0) addr(z[r + 10] | z[r + 11] << 8, 7, z[r + 1] >= 0x24 ? 66 : 60);
    else if (st === 0xFF) addr(0x4880 + ((z[r] - 2) & 0xFF), 8, 64);
  }
  // вид CPC: бойцы — кадры CPC (свой рисунок): клетки старых и новых прямоугольников бойцов Вектора не сверяются
  const act = new Set();
  if (CPC) for (const base of [SYM.cur, SYM.disp]) for (let k = 0; k < 6; k++) {
    const e = base + 8 * k; if (!mem[e]) continue;
    let x0 = mem[e + 1]; const bot = mem[e + 2], top = mem[e + 3], w = mem[e + 4];
    for (let i = bot; i <= top; i++) { const L = 191 - i; if (L < 0 || L >= 192) continue;
      for (let d = 0; d < w; d++) { const c = (x0 + d) & 0xFF; if (c < 32) act.add((L >> 3) * 32 + c); } }
  }
  bad.act = 0;
  const room = z[0xE4BB];
  // клетки под оружием: у ZX оружие рисуется прямо на экран и прячется под прямоугольниками бойцов, у Вектора —
  // всегда поверх (решение порта) — их расхождения считаются отдельно
  const pj = new Set();
  const addp = (x, y) => { if (x >= 32) return; for (const i of [y, y - 7]) { const L = 191 - i; if (L >= 0 && L < 192) pj.add((L >> 3) * 32 + x); } };
  for (let j = 0; j < 3; j++) { const r = 0xE866 + 11 * j; addp(z[r], z[r + 1]); const v = SYM.pcur + 5 * j; if (mem[v]) addp(mem[v + 1], mem[v + 2]); const d = SYM.pdisp + 5 * j; if (mem[d]) addp(mem[d + 1], mem[d + 2]); }
  if (CPC) {                                    // поле ×1.5: эталон — своя отрисовка 40 тайлов по 6 точек (field40)
    const ex = field40(z);
    const sk = new Set();                        // клетки (строка ZX, столбец экрана) под бойцами и оружием
    for (const base of [SYM.cur, SYM.disp]) for (let k = 0; k < 6; k++) {
      const e = base + 8 * k; if (!mem[e]) continue;
      const c0 = (mem[e + 1] << 24) >> 24, bot = mem[e + 2], top = mem[e + 3], w = mem[e + 4];
      for (let i = bot; i <= top; i++) { const L = 199 - i; if (L < 0 || L >= 176) continue; for (let d = 0; d < w; d++) sk.add((L >> 3) * 32 + c0 + d); }
    }
    const pjs = new Set();
    const addq = (px, y) => { if (!px) return; const c = px >> 3; for (const i of [y, y - 7]) { const L = 199 - i; if (L >= 0 && L < 176) { pjs.add((L >> 3) * 32 + c); pjs.add((L >> 3) * 32 + c + 1); } } };
    for (let j = 0; j < 3; j++) { const r = 0xE866 + 11 * j; if (z[r] < 32) addq(32 + 6 * z[r], z[r + 1]); for (const b of [SYM.pcur, SYM.pdisp]) { const v = b + 5 * j; if (mem[v]) addq(mem[v + 1], mem[v + 2]); } }
    if (process.env.NSLOG) { const N = globalThis.__ns = globalThis.__ns || {}; const r = z[0xE4BB], n = mem[SYM.cb_ns]; if (!(r in N) || n > N[r]) N[r] = n; }
    if (process.env.JERK) {                      // лежащее оружие (Y $1E, не летит, на месте): клетки без бойцов не меняются
      const J = globalThis.__jk = globalThis.__jk || { prev: new Map(), n: 0, log: [] };
      const cur = new Map();
      for (let j = 0; j < 3; j++) { const r = 0xE866 + 11 * j; if (z[r + 1] !== 0x1E || z[r + 7] || z[r] >= 36) continue;
        const key = z[r] + ',' + z[0xE4BB]; const px = 32 + 6 * z[r], c0 = px >> 3, L = 199 - 0x1E;
        const cells = []; for (let c = c0; c <= c0 + 1; c++) for (const R of [L >> 3, (L - 7) >> 3]) if (!sk.has(R * 32 + c)) cells.push(R * 32 + c);
        const snap = [...new Set(cells)].sort().map((rc) => { const R = rc >> 5, c = rc & 31; let t = rc + ':'; for (let k = 0; k < 8; k++) for (let pl = 0; pl < 3; pl++) t += mem[(0xA0 + 0x20 * pl + c) << 8 | (231 - R * 8 - k)].toString(16) + '.'; return t; });
        const pe = J.prev.get(key), age = pe ? pe.age + 1 : 0;
        cur.set(key, { snap, age });
        const pv = age >= 2 ? pe.snap : null;     // лежит на месте 2 прохода (смена комнаты — вывод на проход позже)
        if (pv) { const a = new Map(pv.map((t) => [t.split(':')[0], t])); for (const t of snap) { const q = a.get(t.split(':')[0]); if (q && q !== t) { J.n++; if (J.log.length < 40) J.log.push(`шаг ${globalThis.__st} комната ${z[0xE4BB]} оружие X ${z[r]} ${q} -> ${t}`); } } }
      }
      J.prev = cur;
    }
    for (let R = 0; R < 22; R++) for (let c = 0; c < 32; c++) {
      let ok = true;
      for (let k = 0; k < 8 && ok; k++) { const L = R * 8 + k, low = 231 - L;   // фон поднят на 8 строк (16.11)
        for (let pl = 0; pl < 3; pl++) if (mem[(0xA0 + 0x20 * pl + c) << 8 | low] !== ex[pl][L * 32 + c]) { ok = false; break; } }
      if (!ok && process.env.CELL && (!process.env.CELLSTEP || globalThis.__st === +process.env.CELLSTEP) && (globalThis.__c = (globalThis.__c || 0) + 1) <= +process.env.CELL) { const L0 = R * 8; console.log('cell', R, c, 'room', z[0xE4BB], [0, 1, 2].map((pl) => [...Array(8)].map((_, k) => mem[(0xA0 + 0x20 * pl + c) << 8 | (231 - L0 - k)].toString(16) + '/' + ex[pl][(L0 + k) * 32 + c].toString(16)).join(' ')).join(' | ')); }
      if (!ok) { if (sk.has(R * 32 + c)) bad.act++; else if (pjs.has(R * 32 + c)) bad.proj++; else bad.field.push(R * 32 + c); }
    }
  }
  for (let R = CPC ? 21 : 0; R < 24; R++) for (let c = 0; c < 32; c++) {
    let at = z[0x5800 + R * 32 + c], ink = at & 7, paper = (at >> 3) & 7;
    if (CPC) {                                  // цвета CPC: перекраска комнаты (строки 0..13 / 14..20), HUD — 3 на 0
      if (R >= 21) { ink = R === 22 ? 1 : 3; paper = 0; }   // строка 22 — полоски энергии серые (владелец 15.11)
      else { const t = (R < 14 ? SYM.remap_up : SYM.remap_fl) + 8 * room; ink = mem[t + ink]; paper = mem[t + paper]; }
    }
    let ok = true;
    for (let k = 0; k < 8 && ok; k++) {
      const L = R * 8 + k, p = z[zaddr(L, c)], low = 223 - L - (R >= 21 ? 8 : 0);   // HUD на символьную строку ниже (17.11)
      for (let pl = 0; pl < 3; pl++) {
        const bit = 2 - pl, I = ((ink ^ paper) >> bit & 1) ? 0xFF : 0, P = (paper >> bit & 1) ? 0xFF : 0;
        if (mem[(0xA0 + 0x20 * pl + c) << 8 | low] !== ((p & I) ^ P)) { ok = false; break; }
      }
    }
    if (!ok) { if (act.has(R * 32 + c)) bad.act++; else if (pj.has(R * 32 + c)) bad.proj++; else if (rc.has(R * 32 + c)) bad.rect++; else (R < 21 ? bad.field : bad.hud).push(R * 32 + c); }
  }
  return bad;
}
function png(file, z) {
  const { execSync } = require('child_process');
  const W = 512, H = 192, img = Buffer.alloc(W * H * 3);
  const PAL = [[0, 0, 0], [0, 0, 255], [255, 0, 0], [255, 0, 255], [0, 255, 0], [0, 255, 255], [255, 255, 0], [255, 255, 255]];
  for (let y = 0; y < 192; y++) for (let x = 0; x < 256; x++) {
    const at = z[0x5800 + (y >> 3) * 32 + (x >> 3)], p = (z[zaddr(y, x >> 3)] >> (7 - (x & 7))) & 1;
    img.set(PAL[p ? at & 7 : (at >> 3) & 7], (y * W + x) * 3);
    const a = ((x >> 3) << 8) | (223 - y - (y >= 168 ? 8 : 0)), b = 7 - (x & 7);
    const idx = ((mem[0xA000 + a] >> b) & 1) << 2 | ((mem[0xC000 + a] >> b) & 1) << 1 | ((mem[0xE000 + a] >> b) & 1);
    img.set(PAL[idx], (y * W + 256 + x) * 3);
  }
  fs.writeFileSync(file + '.ppm', Buffer.concat([Buffer.from(`P6 ${W} ${H} 255\n`), img]));
  execSync(`sips -s format png "${file}.ppm" --out "${file}" >/dev/null && rm "${file}.ppm"`);
}

function runOne(file) {
  const gd = loadGolden(file);
  if (!gd.init.fixes) { console.log(`${gd.name}: оригинал — пропуск`); return true; }
  const rp = new Replay(gd);
  mem.fill(0); mem.set(BIN.subarray(0, Math.min(BIN.length, 0xA000)));
  // экран к началу эталона: APPROACHING-очистка, имена, комната, HUD (как next_room ZX и конец новой игры)
  const screenInit = () => {
    load(rp.mem); S = { ports: new PortQ([]) };
    call80(SYM.plat_approach);
    call80(SYM.plat_name, { b: rp.mem[0xE46F], c: 3 });
    for (let k = 1; k <= 5; k++) { const r = 0xE461 + 15 * k; if (rp.mem[r + 8] === 0) call80(SYM.plat_name, { b: rp.mem[r + 14], c: rp.mem[r + 13] }); }
    { const t0 = T80; call80(CPC ? SYM.room_build : SYM.plat_room); if (process.env.TROOM) console.log('room_build', T80 - t0, 'strips', mem[SYM.cb_ns], 'cells', mem[SYM.cb_nc], 'NS_MAX', SYM.NS_MAX, 'NA', SYM.NA); }
    call80(SYM.plat_hudinit); call80(SYM.plat_hud); call80(SYM.plat_hudinit);
  };
  screenInit();
  if (process.env.PROFINIT) { PROFA.set(PROFB); profDump(); process.exit(0); }
  PROFB.fill(0);
  let nF = 0, nH = 0, run = 0, shown = 0, skip = 0, cellsF = 0, nP = 0, nR = 0;
  for (const st of gd.steps) {
    if (process.env.ROOMSHOT) { const d = process.env.ROOMSHOT, R = (globalThis.__rs = globalThis.__rs || { n: {} });
      if (R.pend !== undefined) { const room = R.pend; R.pend = undefined; fs.mkdirSync(d, { recursive: true });   // после прохода: ZX и Вектор — одно состояние
        fs.writeFileSync(`${d}/zx${room}.bin`, Buffer.from(rp.mem.subarray(0x4000, 0x5B00)));
        fs.writeFileSync(`${d}/vec${room}.bin`, Buffer.from(mem.subarray(0xA000, 0x10000)));
        fs.writeFileSync(`${d}/pal${room}.bin`, Buffer.from(mem.subarray(SYM.pal_rooms + 8 * mem[SYM.zv_E4BB], SYM.pal_rooms + 8 * mem[SYM.zv_E4BB] + 8)));
        fs.writeFileSync(`${d}/room${room}.txt`, `шаг ${st.step}, комната ZX ${rp.mem[0xE4BB]}, Вектора ${mem[SYM.zv_E4BB]}`); }
      const room = rp.mem[0xE4BB]; R.n[room] = (R.n[room] || 0) + 1;
      if (R.n[room] === +(process.env.RSTEP || 20)) { screenInit(); R.pend = room; } }   // тур — телепортом: комнату Вектора построить заново
    load(rp.mem);
    curStep = st.step; globalThis.__st = st.step;
    S = { ports: new PortQ(st.in) };
    let err = null;
    T80 = 0;
    const pc0 = [CNTS[SYM.cpc_decode] || 0, CNTS[SYM.col_draw] || 0];
    try { call80(SYM.pass); } catch (e) { err = e; }
    if (!err && process.env.SPAN && T80 < 1e6) { CNTS.rows2 = (CNTS.rows2 || 0) + (CNTS.rp || 0); CNTS.in2 = (CNTS.in2 || 0) + (CNTS.ip || 0); CNTS.np = (CNTS.np || 0) + 1; CNTS.cyc = (CNTS.cyc || 0) + T80; }
    CNTS.rp = 0; CNTS.ip = 0;
    if (!err) TP.push(T80);
    if (process.env.FIELDDUMP && !err) { const room = rp.mem[0xE4BB]; const F = (globalThis.__fd = globalThis.__fd || {}); if (!F[room]) { const ex = field40(rp.mem); F[room] = ex.map((p) => Buffer.from(p).toString('base64')); } }
    if (process.env.PJT && !err) { const z = rp.mem; const row = [0, 1, 2].map((j) => { const r = 0xE866 + 11 * j, v = SYM.pcur + 5 * j; return `${z[r]},${z[r + 1]}>${z[r + 2]},${z[r + 3]} f${z[r + 5]} t${z[r + 6]} m${z[r + 7]} o${z[0xE888 + j]} d${mem[SYM.pj_dr + j]}e${mem[SYM.pj_er + j]} v${mem[v]}:${mem[v + 1]},${mem[v + 2]}`; }); (globalThis.__pjt = globalThis.__pjt || []).push(st.step + ' ' + row.join(' | ')); }
    if (process.env.SHIFTS && !err) { const H = (globalThis.__sh = globalThis.__sh || {}); for (let k = 0; k < 6; k++) { const e = SYM.cur + 8 * k; if (!mem[e]) continue; const hdr = mem[e + 5] | mem[e + 6] << 8, sh = mem[e + 7] & 7; const wv = mem[hdr + 1]; let sz = 0; for (let c = 0; c < wv; c++) sz += 2 * mem[hdr + 6 + 4 * c + 3]; const key = hdr.toString(16) + ' s' + sh + ' k' + (k ? 'e' : 'h'); H[key] = H[key] || [0, sz, wv]; H[key][0]++; } }
    if (process.env.ROWCNT) { const R = globalThis.__rc; if (R && !err && T80 < 2e6) (R.all = R.all || []).push([T80, R.cur || {}]); if (R) R.cur = {}; }
    if (process.env.RECTLOG && !err) { (globalThis.__rp = globalThis.__rp || []).push({ st: st.step, t: T80, r: globalThis.__rl || [], act: [0,1,2,3,4,5].map((k) => mem[SYM.cur + 8 * k] ? [mem[SYM.cur + 8 * k + 1], mem[SYM.cur + 8 * k + 2], mem[SYM.cur + 8 * k + 3], mem[SYM.cur + 8 * k + 4]] : null) }); globalThis.__rl = []; }
    if (PROF) { if (!err && T80 < 1e6 && T80 >= (+process.env.PROFMIN || 0)) for (let a = 0; a < 0x10000; a++) PROFA[a] += PROFB[a]; PROFB.fill(0); }
    if (process.env.PASSLOG && !err) PL.push([T80, (CNTS[SYM.cpc_decode] || 0) - pc0[0], (CNTS[SYM.col_draw] || 0) - pc0[1]]);
    rp.pass(st, 5e7, false);
    if (process.env.SCRDUMP && st.step < +process.env.SCRDUMP) { const b = Buffer.alloc(3 * 32 * 256); for (let pl = 0; pl < 3; pl++) for (let a = 0; a < 0x2000; a++) b[pl * 0x2000 + a] = mem[0xA000 + 0x2000 * pl + a]; fs.appendFileSync(process.env.SCRFILE, b); fs.appendFileSync(process.env.SCRFILE + ".room", Buffer.from([mem[SYM.zv_E4BB]])); }
    if (process.env.DBG && st.step >= +process.env.DBG && st.step < +process.env.DBG + 4) console.log('dbg', st.step, 'cur', [...mem.subarray(SYM.cur, SYM.cur + 7)].join(','), 'disp', [...mem.subarray(SYM.disp, SYM.disp + 7)].join(','), 'rb', [...mem.subarray(SYM.rb_c0, SYM.rb_c0 + 4)].join(','), 'pc', [...mem.subarray(SYM.pcur, SYM.pcur + 15)].join(','), 'pd', [...mem.subarray(SYM.pdisp, SYM.pdisp + 15)].join(','), 'er/dr', [...mem.subarray(SYM.pj_er, SYM.pj_er + 6)].join(','), 'zx', [0, 1, 2].map((j) => [...rp.mem.subarray(0xE866 + 11 * j, 0xE866 + 11 * j + 11)].join(' ')).join(' | '), 'own', [...rp.mem.subarray(0xE888, 0xE88B)].join(','));
    if (process.env.PJF && st.step < +process.env.PJF) console.log('pjf', st.step, [0, 1, 2].map((j) => { const r = 0xE866 + 11 * j; return [...rp.mem.subarray(r, r + 11)].map((v) => v.toString(16)).join('.') + ' own ' + rp.mem[0xE888 + j].toString(16); }).join(' | '), '| vecptr', [0, 1, 2].map((j) => (mem[SYM.pcur + 5 * j + 3] | mem[SYM.pcur + 5 * j + 4] << 8).toString(16)).join(','));
    if (process.env.PJLOG && st.step >= +process.env.PJLOG && st.step < +process.env.PJLOG + 400) { const zp = [0, 1, 2].map((j) => { const r = 0xE866 + 11 * j; return rp.mem[r + 10] ? `${rp.mem[r]},${rp.mem[r + 1]}` : '-'; }).join(' '); const vp = [0, 1, 2].map((j) => { const v = SYM.pcur + 5 * j; return mem[v] ? `${mem[v + 1]},${mem[v + 2]}` : '-'; }).join(' '); if (zp !== '- - -' || vp !== '- - -') console.log('pj', st.step, 'zx', zp, '| vec', vp); }
    if (process.env.IDOL && Math.abs(st.step - +process.env.IDOL) < 4) console.log('idol', st.step, 'zx', rp.mem[0xE4DB], rp.mem[0xE4DC], 'room', rp.mem[0xE4BB], 'vec', mem[SYM.idol_on], mem[SYM.idol_col], 'mapv', [0, 1].map((k) => mem[SYM.MAP_V + 18 * 32 + (mem[SYM.idol_col] & 31) + k]).join(','));
    if (err) {
      if (!(err instanceof Abort)) console.log(`  шаг ${st.step}: ${err.message}`);
      skip++;
      // после меню и новой игры — экран заново, как в начале
      rp.apply(st.pre); screenInit();
      continue;
    }
    run++;
    if (process.env.SHOTSTEPS && process.env.SHOTSTEPS.split(',').includes(String(st.step))) { fs.mkdirSync('build/vecstep', { recursive: true }); png(`build/vecstep/s_${gd.name}_${st.step}.png`, rp.mem); }
    if (st.step >= from) {
      globalThis.__st = st.step; if (process.env.TOPS) { for (let k = 0; k < 6; k++) { const e = SYM.cur + 8 * k; if (mem[e]) { const t = mem[e + 3]; (globalThis.__tops = globalThis.__tops || {})[t] = (globalThis.__tops[t] || 0) + 1; } } } const b = compare(rp.mem); if (process.env.IDBG && st.step >= 60 && st.step <= 66) console.log("idol", st.step, mem[SYM.idol_on], mem[SYM.idol_col], rp.mem[0xE4DC], rp.mem[0xE4DB], rp.mem[0xE4BB]);
      if (b.field.length) { nF++; cellsF += b.field.length; }
      if (b.hud.length) nH++;
      if (b.proj) nP++;
      if (b.rect) nR++;
      if ((b.field.length || b.hud.length) && shown++ < maxShow) {
        console.log(`  шаг ${st.step}: поле ${b.field.length} клеток, HUD ${b.hud.length}: ` +
          b.field.slice(0, 8).map((x) => `${x >> 5},${x & 31}`).join(' ') + ' | HUD ' + b.hud.slice(0, 8).map((x) => `${x >> 5},${x & 31}`).join(' '));
        if (shots) { fs.mkdirSync(shots, { recursive: true }); png(path.join(shots, `${gd.name}_${st.step}.png`), rp.mem); }
      }
    }
    rp.apply(st.pre);
  }
  console.log(`${gd.name}: шагов ${run} (+${skip} через меню): экран поля расходится на ${nF} (${cellsF} клеток), HUD — на ${nH}; под оружием — на ${nP}, в прямоугольниках бойцов ZX — на ${nR}`);
  return nF === 0 && nH === 0;
}
let ok = true;
for (const f of files) ok = runOne(f) && ok;
if (TP.length) { TP.sort((a, b) => a - b); const q = (p) => TP[Math.floor(p * (TP.length - 1))]; const mean = Math.round(TP.filter((t) => t < 2e6).reduce((a, b) => a + b, 0) / TP.filter((t) => t < 2e6).length); console.log(`такты на проход с выводом: среднее ${mean}, p50 ${q(0.5)}, p90 ${q(0.9)}, p99 ${q(0.99)}, max ${TP[TP.length - 1]} (кадр 59904, 4 кадра — ${4 * 59904})`); }
if (process.env.PASSLOG) { PL.sort((a, b) => b[0] - a[0]); const q = PL.slice(Math.floor(PL.length * 0.05), Math.floor(PL.length * 0.15)); const avg = (k) => (q.reduce((s, x) => s + x[k], 0) / q.length).toFixed(1); const all = (k) => (PL.reduce((s, x) => s + x[k], 0) / PL.length).toFixed(1); console.log('p85..p95: декодов', avg(1), 'столбцов', avg(2), '| все: декодов', all(1), 'столбцов', all(2)); }
if (process.env.SPAN) console.log('rows', CNTS.tot, 'in actor span', CNTS.inr, '| normal passes', CNTS.np, 'rows/pass', (CNTS.rows2 / CNTS.np).toFixed(0), 'cycles/pass', (CNTS.cyc / CNTS.np).toFixed(0), 'in span/pass', (CNTS.in2 / CNTS.np).toFixed(0));
if (process.env.CNT) console.log('decode', CNTS[SYM.cpc_decode], 'rect', CNTS[SYM.rect_draw], 'columns', CNTS[SYM.col_draw]);
function profDump() {
  const labs = Object.entries(SYM).filter(([k, v]) => v < 0xA000 && v >= 0x100 && !k.startsWith('zv_') && !k.includes('.') && !/^[A-Z_]+$/.test(k)).sort((a, b) => a[1] - b[1]);
  const per = new Map();
  for (let a = 0; a < 0x10000; a++) if (PROFA[a]) { let lo = 0, hi = labs.length - 1, n = '?'; while (lo <= hi) { const m = (lo + hi) >> 1; if (labs[m][1] <= a) { n = labs[m][0]; lo = m + 1; } else hi = m - 1; } per.set(n, (per.get(n) || 0) + PROFA[a]); }
  const tot = [...per.values()].reduce((x, y) => x + y, 0);
  for (const [n, t] of [...per].sort((a, b) => b[1] - a[1]).slice(0, +(process.env.PROFN || 20))) console.log(`  ${n.padEnd(16)} ${(100 * t / tot).toFixed(1)} %`);
}
if (PROF) profDump();
if (process.env.FIELDDUMP) fs.writeFileSync(process.env.FIELDDUMP, JSON.stringify(globalThis.__fd));
if (process.env.NSLOG) { const N = globalThis.__ns || {}; fs.writeFileSync(process.env.NSLOG, Object.entries(N).map(([r, n]) => r + ':' + n).join(' ') + ' | max ' + Math.max(...Object.values(N)) + '\n'); }
if (process.env.JERK) { const J = globalThis.__jk || { n: 0, log: [] }; fs.writeFileSync(process.env.JERK, `дёрганий лежащего оружия: ${J.n}\n` + J.log.join('\n') + '\n'); }
if (process.env.PJT) fs.writeFileSync(process.env.PJT, globalThis.__pjt.join('\n'));
if (process.env.SHIFTS) console.log(JSON.stringify(globalThis.__sh));
if (process.env.ROWCNT) fs.writeFileSync(process.env.ROWCNT, JSON.stringify(globalThis.__rc.all));
if (process.env.RECTLOG) fs.writeFileSync(process.env.RECTLOG, JSON.stringify(globalThis.__rp));
process.exit(ok ? 0 : 1);
