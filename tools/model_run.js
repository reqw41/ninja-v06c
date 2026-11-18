#!/usr/bin/env node
// Прогон JS-модели по эталонам (docs/PORT_PLAN.md, этап 2): Z80 (tools/zxgold.js) проигрывает эталон, на
// каждом шаге модель стартует с его памяти, делает проход (game.pass) с теми же портами и LD A,R и
// сравнивается с памятью Z80 после прохода ($7300–$FF7F). Расхождения не копятся: каждый шаг — с Z80.
//   node tools/model_run.js build/golden/g*.jsonl.gz [--max N] [--from шаг] [--neg]
// --neg: негативный контроль — модель с порчей (должна краснеть).
'use strict';
const { loadGolden, Replay, PortQ, LO, HI } = require('./zxgold');
const { Mem } = require('../src/model/core');
const game = require('../src/model/game');

const args = process.argv.slice(2);
let maxShow = 5, from = 0, neg = false;
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--max') maxShow = +args[++i];
  else if (args[i] === '--from') from = +args[++i];
  else if (args[i] === '--neg') neg = true;
  else files.push(args[i]);
}
const hex = (a) => '$' + a.toString(16).toUpperCase().padStart(4, '0');

function runOne(file) {
  const g = loadGolden(file);
  if (!g.init.fixes) { console.log(`${g.name}: оригинал без исправлений — пропуск`); return true; }
  const rp = new Replay(g);
  let bad = 0, run = 0, shown = 0, ng = 0, ngBad = 0;
  let snap = null;                                             // новая игра: снимок на входе в $EC2D
  rp.onStep = (pc) => { if (pc === 0xEC2D) snap = { ram: rp.mem.slice(), a: rp.cpu.get_a() }; return false; };
  const why = {};
  for (const st of g.steps) {
    const ram = rp.mem.slice();
    const M = new Mem(ram);
    M.ports = new PortQ(st.in); M.rq = st.r.slice(); M.writes = new Set();
    let err = null;
    if (st.step >= from) {
      try { game.pass(M); if (neg && st.step % 50 === 7) M.wr(0xE461, M.rd(0xE461) + 1); } catch (e) { err = e; }
    }
    rp.pass(st, 5e7, false);                                  // Z80: тот же проход (без pre)
    const real = rp.mem;
    if (snap) {                                                 // $EC2D..$ED23 против game.new_game
      const M2 = new Mem(snap.ram); M2.writes = new Set(); M2.ports = new PortQ([]);
      let e2 = null;
      try { game.new_game(M2, snap.a); } catch (e) { e2 = e; }
      const d2 = [];
      if (e2) d2.push('исключение: ' + e2.message);
      for (let a = LO; a < HI; a++) if (snap.ram[a] !== real[a]) d2.push(`${hex(a)} ZX ${real[a].toString(16)} модель ${snap.ram[a].toString(16)}`);
      ng++;
      if (d2.length) { ngBad++; if (shown++ < maxShow) console.log(`  новая игра (шаг ${st.step}): ${d2.length} расхождений: ${d2.slice(0, 10).join('; ')}`); }
      snap = null;
    }
    if (st.step < from) { rp.apply(st.pre); continue; }
    if (err && err.notModeled) { why[err.message] = (why[err.message] || 0) + 1; rp.apply(st.pre); continue; }
    run++;
    const diffs = [];
    if (err) diffs.push(`исключение: ${err.stack.split('\n').slice(0, 3).join(' | ')}`);
    else {
      const addrs = new Set([...M.writes, ...st.d.map((x) => x[0])]);
      for (const a of [...addrs].sort((x, y) => x - y)) {
        if (a < LO || a >= HI) continue;
        if (ram[a] !== real[a]) diffs.push(`${hex(a)} ZX ${real[a].toString(16)} модель ${ram[a].toString(16)}`);
      }
      if (M.ports.left()) diffs.push(`портов осталось ${M.ports.left()}`);
      if (M.rq.length) diffs.push(`LD A,R осталось ${M.rq.length}`);
    }
    rp.apply(st.pre);
    if (diffs.length) {
      bad++;
      if (shown++ < maxShow) console.log(`  шаг ${st.step}: ${diffs.length} расхождений: ${diffs.slice(0, 10).join('; ')}`);
    }
  }
  console.log(`${g.name}: шагов ${g.steps.length}, модель ${run}, расхождений ${bad}, без модели ${JSON.stringify(why)}; новых игр ${ng}, расхождений ${ngBad}`);
  return bad === 0 && ngBad === 0;
}

let ok = true;
for (const f of files) ok = runOne(f) && ok;
process.exit(ok ? 0 : 1);
