// Служебное: ГСЧ ($DECA), печать ($DEFB..$DFC9) — только её след в памяти игры (указатели $DEF6/$DEF8,
// флаг двойной высоты $DEF5, цвет $DEFA), очистка экрана ($DFE3), полоски энергии и имена ($F5F2).
'use strict';
const { u8, u16 } = require('./core');

// $DECA: сдвиговый регистр 32 бита $DEF1..$DEF4; A = новый $DEF1
function random(M) {
  const t = u8((M.rd(0xDEF1) & 0x48) + 0x38);
  let c = (t >> 6) & 1;                       // перенос после двух SLA = бит 6
  for (const a of [0xDEF4, 0xDEF3, 0xDEF2, 0xDEF1]) {
    const v = M.rd(a);
    M.wr(a, (v << 1) | c);
    c = v >> 7;
  }
  return M.rd(0xDEF1);
}

// экранный адрес клетки из адреса атрибута ($DF38)
const scr_of_attr = (hl) => ((((hl >> 8) & 3) << 3 | 0x40) << 8) | (hl & 0xff);

// $DFAB: AT B,C
function at(M, b, c) {
  const cc = u8((((b >> 3) | (b << 5)) & 0xE0) | c);
  const bb = (b & 0x18) | 0x40;
  M.wr16(0xDEF6, bb << 8 | cc);
  M.wr16(0xDEF8, ((((bb >> 3) & 3) | 0x58) << 8) | cc);
}

// $DF04: один знак/код строки по адресу hl; возвращает адрес последнего прочитанного байта
function print_char(M, hl) {
  const a = M.rd(hl);
  if (a === 0x16) { at(M, M.rd(hl + 1), M.rd(hl + 2)); return u16(hl + 2); }
  if (a === 0x11) { M.wr(0xDEFA, M.rd(hl + 1)); return u16(hl + 1); }
  // знак: пиксели и атрибут (двойная высота — два атрибута) — экран; указатель атрибута +1
  const p = u16(M.rd16(0xDEF8) + 1);
  M.wr16(0xDEF8, p);
  M.wr16(0xDEF6, scr_of_attr(p));
  return hl;
}

// $DEFB: строка до 0
function print_string(M, hl) {
  while (M.rd(hl)) hl = u16(print_char(M, hl) + 1);
}
// $DF47: строка двойной высоты
function print_big(M, hl) { M.wr(0xDEF5, 1); print_string(M, hl); M.wr(0xDEF5, 0); }

// $DFE3: очистка экрана (PUSH-заливка: SP сохраняется в $DFE1), цвет печати 7, рамка/атрибуты ($DFCA)
function clear_screen(M, sp) {
  M.wr16(0xDFE1, sp);
  M.wr(0xDEFA, 7);
}

// $F5F2: имя бойца C (0 THUG, 1 KARATEKA, 2 NINJA, 3 HERO, 4 — пустое) в строке B полосок энергии
function print_name(M, b, c) {
  M.wr16(0xDEF6, table_word(M, 0xF610, b));
  M.wr16(0xDEF8, table_word(M, 0xF616, b));
  print_string(M, table_word(M, 0xF61C, c));
}

// $E2B4: слово по адресу hl + (2*a mod 256) (перенос ADD A,A теряется)
const table_word = (M, hl, a) => M.rd16(u16(hl + u8(2 * a)));

module.exports = { random, at, print_char, print_string, print_big, clear_screen, print_name, table_word };
