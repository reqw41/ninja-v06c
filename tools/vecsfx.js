#!/usr/bin/env node
// Звук события на Векторе — запись с выхода ВИ53 эмулятора (vector06js Soundnik: счётчики + фильтр, с шумом),
// для сравнения с Atari (tools/atari/sfx_iso.py). Без окна и без звука.
//   node tools/vecsfx.js build/vec/ninja.bin <событие> out.wav
// События: swing_hero swing_enemy hit ko_t0..ko_t3 idol whistle_room whistle_rand ambient
'use strict';
const fs = require('fs');
const E = require('./vec_emu');
const [ROM, EV, OUT] = process.argv.slice(2);
const S = {};
for (const l of fs.readFileSync(ROM.replace(/\.bin$/, '.sym'), 'latin1').split('\n')) {
  const q = l.match(/^([\w.]+):\s+EQU\s+0x([0-9A-F]+)/i); if (q) S[q[1]] = parseInt(q[2], 16);
}
const m = E.mk(ROM);
const SR = 44100;
const sn = m.v06c.soundnik;
let rec = null;
sn.soundRatio = SR / 1497600;
sn.sample = (v) => { if (rec) rec.push(v); };
const W = (sym, off, v) => m.wr(S[sym] + off, v);
const R = (sym, off) => m.rd(S[sym] + off);
for (let f = 0; f < 400; f++) m.frame();
// чистое состояние: драйвер идёт, песни нет, эффекты и подыгрывание погашены, случайный свист не скоро
W('snd_pause', 0, 0); W('snd_cc', 0, 0xFF); W('snd_rt', 0, 1); W('snd_9f5a', 0, 0);
for (const a of [0x2416, 0x2417, 0x240D, 0x240E, 0x240F]) W('SV', a, 0);
W('SW', 0x24E8, 1); W('SW', 0x24E6, 0); W('SW', 0x24E5, 0);
for (let i = 0; i < 8; i++) W('pk', i, 0);
for (let f = 0; f < 10; f++) m.frame();
const fx = (x, step, vol, f0) => {           // $249F (шаг 1, громкость 1) / $24B6 (шаг -2, громкость 16)
  W('SV', 0x2410 + x, step); W('SV', 0x240D + x, vol); W('pk', 2 * x + 1, 2 * x); W('pk', 2 * x, f0);
  W('SW', 0x24E8, 1); W('SW', 0x24E6, 0);
};
const KO = [40, 80, 60, 140];
let n = 50;
rec = [];
if (EV === 'swing_hero') fx(0, 1, 1, R('SV', 0x2413));
else if (EV === 'swing_enemy') fx(1, 1, 1, R('SV', 0x2414));
else if (EV === 'hit') fx(0, 0xFE, 0x10, 0x40);
else if (EV.startsWith('ko_t')) { fx(0, 0xFE, 0x10, 0x40); W('snd_9f5a', 0, KO[+EV[4]]); n = KO[+EV[4]] + 40; }
else if (EV === 'idol') { W('SV', 0x2416, 0x0F); W('snd_9f5a', 0, 200); n = 210; }
else if (EV === 'whistle_room') { W('SV', 0x2417, 0x3F); for (let i = 0; i < 8; i++) W('pk', i, 0); n = 80; }
else if (EV === 'whistle_rand') { W('SV', 0x2417, 0x40); W('SW', 0x24E8, 1); W('SW', 0x24E6, 0); n = 80; }
else if (EV === 'ambient') { W('SW', 0x24E8, 0xFF); n = 600; }
else if (EV === 'music') { W('snd_cc', 0, 0); W('MB', 0xBDBC, 0x40); n = 750; }
else throw new Error('событие? ' + EV);
for (let f = 0; f < n; f++) {
  if (EV !== 'ambient' && EV !== 'whistle_rand') W('snd_rt', 0, 1);
  if (EV === 'music') W('snd_cc', 0, 0);   // без случайного свиста
  m.frame();
}
const buf = Buffer.alloc(44 + rec.length * 2);
buf.write('RIFF', 0); buf.writeUInt32LE(36 + rec.length * 2, 4); buf.write('WAVEfmt ', 8);
buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22); buf.writeUInt32LE(SR, 24);
buf.writeUInt32LE(SR * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36);
buf.writeUInt32LE(rec.length * 2, 40);
let mean = 0; for (const v of rec) mean += v; mean /= rec.length || 1;
rec.forEach((v, i) => buf.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round((v - mean) * 30000))), 44 + i * 2));
fs.writeFileSync(OUT, buf);
console.log(`${EV}: ${(rec.length / SR).toFixed(2)} с -> ${OUT}`);
