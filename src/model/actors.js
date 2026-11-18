// Бойцы: бросок врага ($E4FC), ИИ врагов ($E583 и обработчики $E5B3..$E827), анимация и движение по
// таблицам ($FB71), рамки X и близость ($F4AC), полоски энергии/имена ($EDC2), действия героя ($FC78) с
// выходами из комнаты и дырами ($FD00..$FDDB), ввод героя ($E1F4).
'use strict';
const { u8, u16, ROOM, ACT, rec, INPUT, PHASE } = require('./core');
const { random, print_name, table_word } = require('./sys');
const F = require('./fight');

const cur = (M) => M.rd16(0xE8A2);
const curX = (M) => M.rd(rec(M.rd(0xE8A2)));                      // $E809
const set_input = (M, v) => { M.wr(u16(INPUT + cur(M)), v); M.wr(u16(0xE899 + cur(M)), v); };   // $E7D8
const set_timer = (M, v) => M.wr(u16(0xE893 + cur(M)), v);       // $E7E7
const kind = (M) => M.rd(u16(0xE88D + cur(M))) & 3;              // тип врага (0 бандит, 1 каратист, 2 ниндзя)
const dist_hero = (x, h) => (x >= h ? x - h : h - x);

// $E4FC: враг с вводом $23 (бросок) и своим оружием: фаза <4 — оружие в руке, 4 — летит к краю
function enemy_throw(M) {
  for (let b = 5; b >= 1; b--) {
    M.wr(0xE88B, b); M.wr(0xE8A2, b);
    if (M.rd(INPUT + b) !== 0x23) continue;
    const r = F.proj_of(M);
    if (!r.z) continue;
    const ix = r.hl;
    const a = M.rd(u16(cur(M) + PHASE));
    if (a === 4) {
      M.inc(ix + 3);
      M.wr(ix + 2, M.rd(0xE1F3) ? 0 : 0x1F);
      const e = u8(r.b - 1);
      M.wr(u16(0xE888 + e), 0x32);
      M.wr(ix + 6, 0x32); M.wr(ix + 7, 1);
    } else if (a < 4) {
      M.wr(ix + 7, 0);
      const hl = u16(M.rd16(rec(M.rd(0xE8A2))) + 0x1402);
      M.wr(ix, hl); M.wr(ix + 1, hl >> 8); M.wr(ix + 2, hl); M.wr(ix + 3, hl >> 8);
      M.wr(ix + 6, 0x32); M.wr(ix + 7, 1);
    }
  }
}

// --- ИИ врагов ($E583) ---
// $E75C: случайный выбор: атака $E83F / шаг $E83D или $E83E
function ai_choose(M) {
  const r = random(M);
  if (r >= M.rd(0xE840)) {
    set_input(M, M.rd(0xE83F));
    set_timer(M, (M.rd(0xDEF1) & 3) | 1);
    return;
  }
  if (r < M.rd(0xE841)) { random(M); ai_step(M, !M.rd(0xE1F3)); }          // $E716
  else ai_step(M, !u8(~M.rd(0xE1F3)));                                     // $E73B
}
// $E71F / $E72D: таймер DEF1&7, ввод $E83D (к герою?) или $E83E
function ai_step(M, first) {
  set_timer(M, M.rd(0xDEF1) & 7);
  set_input(M, M.rd(first ? 0xE83D : 0xE83E));
}
// $E7A7: вблизи героя — приём из таблицы $E842 по типу врага
function ai_close(M) {
  random(M);
  set_timer(M, 0);
  const hl = u16(0xE842 + kind(M) * 8 + (M.rd(0xDEF1) & 7));
  const a = M.rd(hl);
  if (a) { set_input(M, a); return; }
  M.wr(0xDEF1, 0);
  ai_step(M, !M.rd(0xE1F3));                                               // $E719
}
// $E77D: у края — разворот или атака
function ai_edge(M) {
  const a = M.rd(u16(0xE899 + cur(M)));
  let c = a === M.rd(0xE83D) ? M.rd(0xE83E) : M.rd(0xE83D);
  if (random(M) < 0x64) c = M.rd(0xE83F);
  set_input(M, c);
  set_timer(M, random(M) & 7);
}
// $E669 / $E689: ниндзя у дыры прыгает ($29 / $28)
function ai_jump(M, v) {
  if (kind(M) !== 2) { ai_close(M); return; }
  if (random(M) >= 0x78) { ai_close(M); return; }
  set_timer(M, 0);
  set_input(M, v);
}
// $E6BC: таймер истёк: ниндзя бросает своё оружие ($23) или подбирает лежащее ($2D); true — ход сделан
function ai_timer(M) {
  if (kind(M) !== 2) { ai_choose(M); return false; }
  M.wr(0xE88B, M.rd(0xE8A2));
  const r = F.proj_of(M);
  if (r.z) {
    if (M.rd(0xDEF1) >= 0xA0) { ai_choose(M); return false; }
    set_input(M, 0x23);
    return true;
  }
  if (random(M) < 0x3C) { ai_choose(M); return false; }
  M.wr(0xE88B, M.rd(0xE8A2));
  F.pick_up(M);
  if (!M.rd(0xE85A)) { ai_choose(M); return false; }
  set_timer(M, 0);
  set_input(M, 0x2D);
  return true;
}
const dec_input_timer = (M) => M.dec(u16(0xE893 + cur(M)));            // $E70D

// $E613: общий ход врага
function ai_move(M) {
  if (dist_hero(curX(M), M.rd(ACT)) < 4) { ai_close(M); return; }
  // $E7F0: таймер -1; Z — истёк
  const t = u16(0xE893 + cur(M));
  let z = true;
  if (M.rd(t)) z = M.dec(t) === 0;
  if (z && ai_timer(M)) return;
  const a = M.rd(u16(0xE899 + cur(M)));
  M.wr(0xDFE1, a);
  if (a === M.rd(0xE83D)) {                                                // $E69A
    const x = curX(M);
    if (x < 2) { ai_edge(M); return; }
    if (x >= M.rd(0xE8A0)) { dec_input_timer(M); set_input(M, M.rd(0xDFE1)); return; }
    if (x >= M.rd(0xE89F)) { ai_jump(M, 0x28); return; }
    dec_input_timer(M); set_input(M, M.rd(0xDFE1)); return;
  }
  if (a === M.rd(0xE83F)) { dec_input_timer(M); set_input(M, M.rd(0xE83F)); return; }   // $E704
  if (a !== M.rd(0xE83E)) ai_choose(M);
  const x = curX(M);
  if (x >= 0x18) { ai_edge(M); return; }
  const lo = M.rd(0xE89F);
  if (x === lo) { ai_jump(M, 0x29); return; }
  if (x > lo && x < M.rd(0xE8A0)) { ai_jump(M, 0x29); return; }
  dec_input_timer(M); set_input(M, M.rd(0xDFE1));                          // $E651
}

const AI_TYPES = [[0x1C, 0xE82E], [0x15, 0xE838], [0x21, 0xE833]];          // $E5B8, $E5D7, $E5F6
// $E583: враги 5..1 по типу ($E88D+n: $FF — нокаут, &3 = 3 — нет)
function enemy_ai(M) {
  for (let b = 5; b >= 1; b--) {
    M.wr(0xE8A2, b);
    const a = M.rd(0xE88D + b);
    if (a === 0xFF) set_input(M, 0x2C);                                    // $E5B3
    else if ((a & 3) !== 3) {
      const [stand, src] = AI_TYPES[a & 3];
      if (!M.rd(u16(INPUT + cur(M)))) {
        if (!M.rd(0xE8A4) || M.rd(rec(b) + 8)) set_input(M, stand);
        else {
          for (let k = 0; k < 5; k++) M.wr(0xE83D + k, M.rd(src + k));
          ai_move(M);
        }
      }
    }
    random(M);                                                             // $E5AA
  }
}

// $FB71: бойцы 5..0: шаг анимации по вводу (таблица $DC63), кадр, сдвиг X и Y по таблице $DDA8
function animate_all(M) {
  for (let b = 5; b >= 0; b--) {
    const iy = rec(b);
    M.wr(0xE88B, b);
    const inp = M.rd(INPUT + b);
    M.wr(0xE85A, inp);
    const tbl = M.rd16(u16(0xDC63 + 2 * inp));
    const ph = M.rd(PHASE + b);
    if (!ph && inp && (M.rd(u16(0xFECA + inp)) || inp === 0x23)) M.sound(b ? 'sw1' : 'sw0');   // начало приёма/броска
    M.wr(PHASE + b, ph + 1);
    M.wr(0xE85C, ph);
    let a = M.rd(u16(tbl + ph));
    if (!a) { M.wr(INPUT + b, 0); M.wr(PHASE + b, 0); continue; }
    a = u8(a - 1);
    if (a < 0x34) { if (a >= 0x23) a -= 2; M.wr(iy + 9, a); }
    const mv = u16(M.rd16(u16(0xDDA8 + 2 * M.rd16(0xE85A))) + u8(2 * M.rd(0xE85C)));
    const bb = M.rd(mv), c = M.rd(mv + 1);
    const step = (bb & 0x7F) >> 2;
    const hero = !M.rd(0xE88B);
    if (!(bb & 0x80)) { if (!(hero && M.rd(0xE8A7))) M.wr(iy, M.rd(iy) + step); }
    else if (!(hero && M.rd(0xE8A6))) M.wr(iy, M.rd(iy) - step);
    M.wr(iy + 1, c);
    M.wr(iy + 1, M.rd(0xE4D3 + b) + c);
  }
}

// $F4AC: X врагов в пределах 4..$18; близость врагов к герою ($E8A5 рядом, $E8A6/$E8A7 вплотную)
function enemy_state(M) {
  for (let b = 5; b >= 1; b--) {
    const hl = rec(b), x = M.rd(hl);
    if (x < 4) M.wr(hl, 4);
    if (x >= 0x18) M.wr(hl, 0x18);
  }
  M.wr(0xE8A5, 0); M.wr(0xE8A7, 0); M.wr(0xE8A6, 0);
  const right = M.rd(0xE1F3);
  for (let b = 5; b >= 1; b--) {
    M.wr(0xE8A2, b);
    const iy = rec(b);
    if (M.rd(iy + 8)) continue;
    const h = right ? M.rd(ACT) : u8(M.rd(ACT) + 2);
    const d = dist_hero(M.rd(iy), h);
    if (right) { if (d < 2) M.wr(0xE8A7, 1); if (d < 0x0A) M.wr(0xE8A5, 1); }
    else { if (d < 4) M.wr(0xE8A6, 1); if (d < 0x0C) M.wr(0xE8A5, 1); }
  }
}

// $EDC2: бойцы 0..4 в строках полосок: полоска энергии (экран); нокаутированный — имя стирается
function bars(M) {
  for (let k = 0; k < 5; k++) {
    const iy = rec(k), s = M.rd(iy + 8);
    if (s && s !== 0xFF) continue;
    if (M.rd(iy + 0x0E) >= 3) continue;
    if (!M.rd(iy + 0x0C)) { M.wr(0xEE90, M.rd(iy + 0x0E)); print_name(M, M.rd(iy + 0x0E), 4); }
    if (!M.rd(iy + 0x0C)) M.wr(iy + 0x0E, 0xFF);
  }
}

// $FC64: сброс вводов бойцов 1..5 (и героя, если не $14), фаза героя 0
function reset_inputs(M) {
  if (M.rd(INPUT) !== 0x14) M.wr(INPUT, 0);
  for (let k = 1; k <= 5; k++) M.wr(INPUT + k, 0);
  M.wr(PHASE, 0);
}

// $FC41: враг рядом: шаг героя превращается в блок/приём
function hero_near(M) {
  const a = M.rd(INPUT);
  if (a === 3 || a === 7) M.wr(INPUT, 0x2E);
  else if (a === 4 || a === 8) M.wr(INPUT, 0x2F);
  else if (!a) M.wr(INPUT, 0x11);
}

// $FC78: действие героя: бросок ($0D), подбор (2), выходы влево/вправо, дыры вверх/вниз
function hero_action(M, ctx) {
  if (M.rd(0xE8A5)) hero_near(M);
  if (M.rd(INPUT) === 0x0D) {
    M.wr(0xE88B, 0);
    const r = F.proj_of(M);
    if (!r.z) { if (!M.rd(PHASE)) M.wr(INPUT, 0x11); }
    else {
      const ix = r.hl, a = M.rd(PHASE);
      if (a === 4) {
        M.wr(ix + 3, M.rd(ix + 3) + 2);
        M.wr(ix + 2, M.rd(0xE1F3) ? 0x20 : 0);
        const e = u8((r.b === null ? 0 : r.b) - 1);                       // B после $E4FC = 0
        M.wr(u16(0xE888 + e), 0x64);
        M.wr(ix + 6, 0x64); M.wr(ix + 7, 0x64);
      } else if (a < 4) {
        M.wr(ix + 7, 0);
        const hl = u16(M.rd16(ACT) + 0x1402);
        M.wr(ix, hl); M.wr(ix + 1, hl >> 8); M.wr(ix + 2, hl); M.wr(ix + 3, hl >> 8);
        M.wr(ix + 6, 0x64); M.wr(ix + 7, 0xFF);
      }
    }
  }
  if (M.rd(INPUT) === 2) { M.wr(0xE88B, 0); F.pick_up(M); }
  const x = M.rd(ACT);
  if (x < 2) {
    if (ctx.next_room(M, 0, 0xFFFC)) { M.wr(ACT, 0x18); reset_inputs(M); }
    else M.wr(ACT, 2);                                                    // $FD0F
    return;
  }
  if (x >= 0x19) {
    if (ctx.next_room(M, 1, 0xFFFC)) { M.wr(ACT, 3); reset_inputs(M); }
    else M.wr(ACT, 0x19);                                                 // $FD2C
    return;
  }
  // $FD3D: вверх под дырой в потолке (X..X+2)
  if (M.rd(INPUT) === 1) {
    const hc = M.rd(0xE4D9);
    if (hc && (hc === x || u8(hc + 1) === x || u8(hc + 2) === x)) {
      for (;;) {
        const a = u8(M.rd(ACT + 1) + 8);
        if (a >= 0x7C) break;
        M.wr(ACT + 1, a);
        M.wr(0xE46A, 0x11);
        ctx.draw(M);
      }
      ctx.next_room(M, 2, 0xFFFC);
      M.wr(ACT + 1, 0x14);
      M.wr(ACT, M.rd(u16(0xDBB5 + 2 * M.rd(ROOM))) + 2);
      reset_inputs(M);
      M.wr(INPUT, 0); M.wr(PHASE, 0);
      return;
    }
  }
  // $FD93: вниз в приседе (фаза 2) над дырой в полу
  const a = M.rd(INPUT);
  if (a !== 2 || M.rd(PHASE) !== 2) return;
  const hf = M.rd(0xE4DA);
  if (!hf) return;
  // $FDAE: X = hf или hf+1 (у ZX третья проверка без CP: INC A / RET NZ)
  if (hf !== x && u8(hf + 1) !== x && u8(hf + 2) !== 0) return;
  ctx.next_room(M, 3, 0xFFFC);
  M.wr(INPUT, 0x14); M.wr(PHASE, 0);
  M.wr(ACT + 1, 0x50);
  reset_inputs(M);
  M.wr(ACT, M.rd(u16(0xDBB5 + 2 * M.rd(ROOM))));
}

// $E1F4: клавиши по таблице типа управления $E1EC и Kempston -> ввод героя (таблицы $E244/$E254)
function read_controls(M) {
  let hl = table_word(M, 0xE021, M.rd(0xE1EC));
  let c = 1, carry = 0;
  do {
    const v = M.in(M.rd(hl) << 8 | 0xFE);
    const m = M.rd(u16(hl + 1));
    hl = u16(hl + 3);
    const bit = (v & m) ? 0 : 1;
    carry = c >> 7;
    c = u8(c << 1 | bit);
  } while (!carry);
  let k = M.in(0x001F);
  if (k >= 0x1B) k = 0;
  let a = (k | c) & 0x1F;
  M.wr(INPUT, a);
  const tbl = (a & 0x10) && M.rd(0xE1F3) ? 0xE254 : 0xE244;
  a &= ~0x10;
  let v = M.rd(tbl + a);
  if (M.rd(INPUT) & 0x10) v = u8(v + 9);
  M.wr(INPUT, v);
}

module.exports = { enemy_throw, enemy_ai, animate_all, enemy_state, bars, reset_inputs, hero_action, read_controls };
