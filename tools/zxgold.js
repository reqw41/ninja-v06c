// Эталоны ZX (tools/golden.py) на JS: чтение и проигрывание на Z80 (tools/vendor/Z80.js).
//
// Эталон — gzip JSON-строки: строка 0 {kind:'init', full (64 КБ hex на первом $ED23), regs, pre},
// дальше шаг на каждый следующий $ED23: {step, in: [[порт, байт, повторов]], r: [LD A,R], d: [[адрес,
// байт]] (изменения $7300–$FF7F за проход), pre: [[адрес, байт]] (внешние записи на границе, после d)}.
// Replay ведёт Z80 от снимка: порты и LD A,R — из очередей шага, так что проход повторяет ZX точно.
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const Z80 = require('./vendor/Z80.js');

const ROOT = path.join(__dirname, '..');
const LO = 0x7300, HI = 0xFF80, LOOP = 0xED23;

function loadGolden(file) {
  const lines = zlib.gunzipSync(fs.readFileSync(file)).toString().split('\n').filter(Boolean);
  const init = JSON.parse(lines[0]);
  const steps = lines.slice(1).map((l) => JSON.parse(l));
  return { name: path.basename(file).replace(/\.jsonl\.gz$/, ''), init, steps };
}

// очередь портов шага: [[порт, байт, n], ...] -> next(порт)
class PortQ {
  constructor(rle) { this.q = rle.map((x) => x.slice()); this.i = 0; }
  next(port) {
    const e = this.q[this.i];
    if (!e) throw new Error(`порт ${port.toString(16)}: в эталоне чтений больше нет`);
    if (e[0] !== port) throw new Error(`порт ${port.toString(16)}, в эталоне ${e[0].toString(16)}`);
    const v = e[1];
    if (--e[2] === 0) this.i++;
    return v;
  }
  left() { let n = 0; for (let k = this.i; k < this.q.length; k++) n += this.q[k][2]; return n; }
}

class Replay {
  constructor(g) {
    this.g = g;
    this.mem = new Uint8Array(Buffer.from(g.init.full, 'hex'));
    this.onWrite = null;       // (адрес, байт) перед записью
    this.onStep = null;        // (pc) перед каждой командой; вернуть true — пропустить шаг CPU
    this.ports = null; this.rq = [];
    const self = this;
    this.cpu = new Z80({
      mem_read: (a) => self.mem[a],
      mem_write: (a, v) => { if (a < 0x4000) return; if (self.onWrite) self.onWrite(a, v & 0xff); self.mem[a] = v & 0xff; },
      io_read: (p) => self.ports.next(p & 0xffff),
      io_write: () => {},
    });
    const r = g.init.regs, s = this.cpu.getState();
    Object.assign(s, { a: r.a, b: r.b, c: r.c, d: r.d, e: r.e, h: r.h, l: r.l, ix: r.ix, iy: r.iy, sp: r.sp,
      pc: r.pc, i: r.i, r: r.r, imode: r.im, iff1: r.iff, iff2: r.iff,
      a_prime: r["'a"], b_prime: r["'b"], c_prime: r["'c"], d_prime: r["'d"], e_prime: r["'e"],
      h_prime: r["'h"], l_prime: r["'l"] });
    s.flags = unpackF(r.f); s.flags_prime = unpackF(r["'f"]);
    this.cpu.setState(s);
    this.apply(g.init.pre);
  }
  apply(pre) { for (const [a, v] of pre || []) this.mem[a] = v; }
  // одна команда; LD A,R берёт A из очереди эталона
  insn() {
    const pc = this.cpu.get_pc();
    const ldar = this.mem[pc] === 0xED && this.mem[(pc + 1) & 0xffff] === 0x5F;
    this.cpu.run_instruction();
    if (ldar) {
      if (!this.rq.length) throw new Error('LD A,R: в эталоне значений нет');
      const v = this.rq.shift(), s = this.cpu.getState();
      s.a = v; s.flags.S = v >> 7; s.flags.Z = v ? 0 : 1; s.flags.H = 0; s.flags.N = 0; s.flags.P = s.iff2 ? 1 : 0;
      s.flags.Y = (v >> 5) & 1; s.flags.X = (v >> 3) & 1;
      this.cpu.setState(s);
    }
  }
  // проход до следующего $ED23; возвращает расхождения с d эталона
  pass(st, maxInsn = 5e7, applyPre = true) {
    this.ports = new PortQ(st.in); this.rq = st.r.slice();
    const before = this.mem.slice(LO, HI);
    let n = 0;
    do {
      if (this.onStep && this.onStep(this.cpu.get_pc())) continue;
      this.insn();
      if (++n > maxInsn) throw new Error('проход не кончился');
    } while (this.cpu.get_pc() !== LOOP);
    const diffs = [];
    const want = new Map(st.d.map(([a, v]) => [a, v]));
    for (let a = LO; a < HI; a++) {
      const was = before[a - LO], now = this.mem[a];
      const w = want.has(a) ? want.get(a) : was;
      if (now !== w) diffs.push([a, w, now]);
    }
    const left = this.ports.left() + this.rq.length;
    if (applyPre) this.apply(st.pre);
    return { diffs, left, insns: n };
  }
}

function unpackF(f) {
  return { S: f >> 7 & 1, Z: f >> 6 & 1, Y: f >> 5 & 1, H: f >> 4 & 1, X: f >> 3 & 1, P: f >> 2 & 1, N: f >> 1 & 1, C: f & 1 };
}

module.exports = { loadGolden, Replay, PortQ, LO, HI, LOOP, ROOT };

if (require.main === module) {
  // самопроверка: Z80.js по эталону даёт те же изменения памяти, что SkoolKit
  let ok = true;
  for (const f of process.argv.slice(2)) {
    const g = loadGolden(f), rp = new Replay(g);
    let bad = 0, insns = 0;
    for (const st of g.steps) {
      const r = rp.pass(st);
      insns += r.insns;
      if (r.diffs.length || r.left) {
        if (bad++ < 3) console.log(`  шаг ${st.step}: ${r.diffs.length} расхождений, осталось чтений ${r.left}: ` +
          r.diffs.slice(0, 6).map(([a, w, n]) => `${a.toString(16)} ZX ${w} JS ${n}`).join('; '));
        rp.mem.set(rp.mem.slice(LO, HI), LO);
      }
    }
    console.log(`${g.name}: шагов ${g.steps.length}, команд ${insns}, расхождений ${bad}`);
    if (bad) ok = false;
  }
  process.exit(ok ? 0 : 1);
}
