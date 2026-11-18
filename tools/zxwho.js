#!/usr/bin/env node
// Кто что пишет: по эталонам на Z80 каждая запись в $7300–$FF7F относится к подпрограмме, вызванной из
// главного цикла ($ED23–$EDC1) — «верхнему» вызову; печать по вызовам — диапазоны записанных адресов.
//   node tools/zxwho.js build/golden/g2_rand.jsonl.gz [...]
'use strict';
const { loadGolden, Replay, LO, HI } = require('./zxgold');

const who = new Map();   // верх -> Map(адрес -> число записей)
for (const f of process.argv.slice(2)) {
  const g = loadGolden(f), rp = new Replay(g);
  let top = 'main', sp0 = 0;
  rp.onStep = (pc) => {
    const sp = rp.cpu.get_sp();
    if (pc >= 0xED23 && pc < 0xEDC2) {
      top = 'main';
      const op = rp.mem[pc];
      if (op === 0xCD || (op & 0xC7) === 0xC4) { top = 'c' + (rp.mem[pc + 1] | rp.mem[pc + 2] << 8).toString(16).toUpperCase(); sp0 = sp; }
      else if (op === 0xC3) top = 'j' + (rp.mem[pc + 1] | rp.mem[pc + 2] << 8).toString(16).toUpperCase();
    }
    return false;
  };
  rp.onWrite = (a) => {
    if (a < LO || a >= HI) return;
    if (a >= rp.cpu.get_sp() - 2 && a < 0x10000 && rp.cpu.get_sp() > 0xFF00) return;   // стек
    let m = who.get(top); if (!m) who.set(top, m = new Map());
    m.set(a, (m.get(a) || 0) + 1);
  };
  for (const st of g.steps) rp.pass(st);
}
const ranges = (addrs) => {
  const s = [...addrs].sort((x, y) => x - y), out = [];
  for (const a of s) { const l = out[out.length - 1]; if (l && a === l[1] + 1) l[1] = a; else out.push([a, a]); }
  return out.map(([a, b]) => a === b ? a.toString(16) : a.toString(16) + '-' + b.toString(16)).join(' ');
};
for (const [t, m] of [...who].sort()) console.log(`${t}: ${ranges(m.keys())}`);
