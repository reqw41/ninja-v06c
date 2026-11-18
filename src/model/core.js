// Ядро JS-модели логики Ninja (docs/PORT_PLAN.md, этап 2; образец — brucelee-v06c/src/model/core.js).
//
// Память — 64 КБ в раскладке ZX (адреса как в игре, с исправлениями порта: комната в $E4BB). Модель не
// рисует: записи в экран и задний буфер (< $7300) не делаются; всё, что вывод оставляет в памяти игры
// (адреса бойцов на экране, указатели печати, флаги), модель повторяет. Порты и LD A,R — очереди
// эталона. Звук — список событий [имя, ...] (точки запуска для озвучки Atari, docs/MUSIC.md).
'use strict';

class NotModeled extends Error { constructor(m) { super(m); this.notModeled = true; } }

class Mem {
  constructor(ram) {
    this.ram = ram;                   // Uint8Array(0x10000), владеет вызывающий
    this.ports = null;                // .next(порт) -> байт
    this.rq = [];                     // LD A,R
    this.snd = [];                    // звуковые события
    this.writes = null;               // Set записанных адресов (для сверки)
  }
  rd(a) { return this.ram[a & 0xffff]; }
  wr(a, v) {
    a &= 0xffff;
    if (a < 0x7300) return;           // экран, атрибуты, задний буфер — вывод
    this.ram[a] = v & 0xff;
    if (this.writes) this.writes.add(a);
  }
  rd16(a) { return this.rd(a) | this.rd(a + 1) << 8; }
  wr16(a, v) { this.wr(a, v); this.wr(a + 1, v >> 8); }
  inc(a) { const v = (this.rd(a) + 1) & 0xff; this.wr(a, v); return v; }
  dec(a) { const v = (this.rd(a) - 1) & 0xff; this.wr(a, v); return v; }
  in(port) { if (!this.ports) throw new Error('модель: нет очереди портов'); return this.ports.next(port & 0xffff); }
  ldar() { if (!this.rq.length) throw new Error('модель: нет значения LD A,R'); return this.rq.shift(); }
  sound(name, ...a) { this.snd.push([name, ...a]); }
}

const u8 = (v) => v & 0xff, u16 = (v) => v & 0xffff;
const ROOM = 0xE4BB;                  // номер комнаты (багфикс 2; в оригинале $E4BA)
const ACT = 0xE461, REC = 15;         // записи бойцов: 0 — герой, 1..5 — враги
const rec = (n) => u16(ACT + REC * n);
const INPUT = 0xE1ED;                 // «нажатия» бойцов: герой, 1..5
const PHASE = 0xE4CD;                 // фаза анимации бойцов 0..5
const PROJ = 0xE866, PREC = 11;       // 3 метательных оружия по 11 байт; владельцы/флаги — $E888
const proj = (j) => u16(PROJ + PREC * j);

module.exports = { Mem, NotModeled, u8, u16, ROOM, ACT, REC, rec, INPUT, PHASE, PROJ, PREC, proj };
