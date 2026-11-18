#!/usr/bin/env node
// Звук Ninja на Векторе без окна: боевой образ в vector06js (tools/vec_emu.js) N кадров с планом клавиш; записи
// в ВИ53 (порты 08..0B) за кадр -> делители трёх счётчиков на конец кадра -> WAV (сумма трёх меандров, режим 3;
// режим 0 без счёта — тишина). Грубо (без точного времени записей внутри кадра), но тембр и ноты — как на Векторе.
//   node tools/vecwav.js build/vec/ninja.rom.bin? -> node tools/vecwav.js build/vec/ninja.bin <кадров> "<план>" out.wav
'use strict';
const fs = require('fs');
const E = require('./vec_emu');
const [ROM, NS, PLAN, OUT] = process.argv.slice(2);
// VPOKES="кадр:символ[+смещение]=значение,..." (символы — из .sym образа): запись в память перед кадром
const POKES = {};
if (process.env.VPOKES) {
  const S = {}; for (const l of require('fs').readFileSync(ROM.replace(/\.bin$/, '.sym'), 'latin1').split('\n')) { const q = l.match(/^([\w.]+):\s+EQU\s+0x([0-9A-F]+)/i); if (q) S[q[1]] = parseInt(q[2], 16); }
  for (const it of process.env.VPOKES.split(',')) { const q = it.match(/^(\d+):(\w+)(?:\+(\w+))?=(\w+)$/); (POKES[+q[1]] = POKES[+q[1]] || []).push([(S[q[2]] + (q[3] ? parseInt(q[3], 16) : 0)) & 0xFFFF, parseInt(q[4], 16)]); }
}
const m = E.mk(ROM);
const VK = { space: [7, 0x80], left: [0, 0x10], up: [0, 0x20], right: [0, 0x40], down: [0, 0x80], vk: [0, 0x04] };
const plan = {};
for (const it of (PLAN || '').split(/\s+/).filter(Boolean)) {
  const mm = it.match(/^(\d+):(\w+)([+-])$/); (plan[+mm[1]] = plan[+mm[1]] || []).push([mm[2], mm[3] === '+']);
}
const N = +NS || 1500;
const st = [0, 1, 2].map(() => ({ mode: 0, div: 0, lsb: null, rw: 3 }));
const frames = [];
for (let f = 0; f < N; f++) {
  if (POKES[f]) for (const [a, v] of POKES[f]) m.wr(a, v);
  for (const [k, d] of plan[f] || []) { const e = VK[k]; if (d) m.keyboard.matrix[e[0]] |= e[1]; else m.keyboard.matrix[e[0]] &= ~e[1]; }
  m.taps = [];
  m.frame();
  for (let i = 0; i < m.taps.length; i += 2) {
    const p = m.taps[i], v = m.taps[i + 1];
    if (p === 0x08) { const c = v >> 6; if (c === 3) continue; st[c].mode = (v >> 1) & 7; st[c].rw = (v >> 4) & 3; st[c].lsb = null; if (st[c].mode !== 3) st[c].div = 0; }
    else { const c = 0x0B - p; if (c < 0 || c > 2) continue; const s = st[c];
      if (s.rw === 3) { if (s.lsb === null) s.lsb = v; else { s.div = s.lsb | v << 8; s.lsb = null; } } else s.div = v; }
  }
  frames.push(st.map((s) => (s.mode === 3 || s.mode === 7) && s.div ? s.div : 0));
  if (process.env.VDUMP && f >= +process.env.VDUMP) console.error(f, frames[frames.length - 1].join(" "), m.taps.filter((_, i) => i % 2 === 0).filter((p) => p !== 0x08).length);
}
const RATE = 44100, spf = RATE / 50;
const out = Buffer.alloc(Math.ceil(N * spf) * 2 + 4);
const ph = [0, 0, 0];
let acc = 0, o = 0;
for (const fr of frames) {
  acc += spf; const n = Math.floor(acc); acc -= n;
  for (let i = 0; i < n; i++) {
    let s = 0;
    for (let c = 0; c < 3; c++) { if (!fr[c]) continue; ph[c] += 1500000 / fr[c] / RATE; ph[c] -= Math.floor(ph[c]); s += ph[c] < 0.5 ? 1 : -1; }
    out.writeInt16LE(Math.round(s * 6000), o); o += 2;
  }
}
const data = out.subarray(0, o);
const hdr = Buffer.alloc(44);
hdr.write('RIFF', 0); hdr.writeUInt32LE(36 + data.length, 4); hdr.write('WAVEfmt ', 8); hdr.writeUInt32LE(16, 16);
hdr.writeUInt16LE(1, 20); hdr.writeUInt16LE(1, 22); hdr.writeUInt32LE(RATE, 24); hdr.writeUInt32LE(RATE * 2, 28);
hdr.writeUInt16LE(2, 32); hdr.writeUInt16LE(16, 34); hdr.write('data', 36); hdr.writeUInt32LE(data.length, 40);
fs.writeFileSync(OUT || 'build/vec/ninja_vec.wav', Buffer.concat([hdr, data]));
const act = frames.filter((f) => f.some((x) => x)).length;
console.log(`кадров ${N}, со звуком ${act} -> ${OUT || 'build/vec/ninja_vec.wav'}`);
