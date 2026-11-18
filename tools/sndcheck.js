#!/usr/bin/env node
// Звуковой драйвер Вектора (src/vec/sound.asm, образ build/vec/ninja.bin) по сценарию: N вызовов snd_vbi,
// события plat_sound и режим $CC по плану; после каждого вызова — регистры pk (виртуальный POKEY) и случайные
// байты, которые драйвер взял. -> JSON для tools/atari/sndcheck.py (сверка с моделью Atari tools/atari/sound.py).
//   node tools/sndcheck.js N "вызов:событие ..." > out.json   (событие: sw0 sw1 hit0 hit1 ko idol room cc0 ccff)
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const ROOT = path.join(__dirname, '..');
const SYM = {};
for (const l of fs.readFileSync(path.join(ROOT, 'build/vec/ninja.sym'), 'latin1').split('\n')) {
  const m = l.match(/^([\w.]+):\s+EQU\s+0x([0-9A-F]+)/i); if (m) SYM[m[1]] = parseInt(m[2], 16);
}
const base = process.env.V06JS || path.join(require('os').homedir(), 'projects/vector06js');
const g = { console: { log() {}, debug() {}, warn() {}, error() {}, info() {} } }; g.window = g;
const ctx = vm.createContext(g);
for (const f of ['i8080-js/i8080_trace.js', 'i8080-js/i8080_disasm.js', 'i8080-js/i8080.js'])
  vm.runInContext(fs.readFileSync(path.join(base, f), 'utf8'), ctx, { filename: f });
const mem = new Uint8Array(0x10000);
mem.set(fs.readFileSync(path.join(ROOT, 'build/vec/ninja.bin')));
const cpu = new ctx.I8080({ read: (a) => mem[a & 0xffff], write: (a, v) => { mem[a & 0xffff] = v & 0xff; } },
  { input: () => 0xff, output: () => {}, commit: () => {}, interrupt: () => {} });
let rnds = [];
const RET_RND = new Set();
function call(addr, a) {
  const SENT = 0xFFFE; mem[0x9FFF] = SENT >> 8; mem[0x9FFE] = SENT & 0xff; cpu.sp = 0x9FFE; cpu.pc = addr;
  if (a !== undefined) cpu.regs[7] = a;
  let inRnd = 0;
  while (cpu.pc !== SENT) {
    if (cpu.pc === SYM.snd_random) inRnd = cpu.sp;
    cpu.instruction();
    if (inRnd && cpu.sp > inRnd) { rnds.push(cpu.regs[7]); inRnd = 0; }
  }
}
const N = +process.argv[2] || 1000;
const plan = {};
for (const it of (process.argv[3] || '').split(/\s+/).filter(Boolean)) { const [k, e] = it.split(':'); (plan[+k] = plan[+k] || []).push(e); }
const EV = { sw0: 0x10, sw1: 0x11, hit0: 0x20, hit1: 0x21, ko: 0x30, idol: 0x40, room: 0x50 };
call(SYM.snd_newgame);
const out = [];
for (let n = 0; n < N; n++) {
  const evs = plan[n] || [];
  for (const e of evs) {
    if (e === 'cc0') mem[SYM.snd_cc] = 0; else if (e === 'ccff') mem[SYM.snd_cc] = 0xFF;
    else call(SYM.plat_sound, EV[e]);
  }
  rnds = [];
  call(SYM.snd_vbi);
  out.push({ n, ev: evs, pk: [...mem.subarray(SYM.pk, SYM.pk + 9)], rnd: rnds });
}
process.stdout.write(JSON.stringify(out));
