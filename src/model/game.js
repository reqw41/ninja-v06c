// Ход игры: проход главного цикла ($ED23), новая игра ($EC2D), идол ($F554), очки ($EA76).
// Меню, GAME OVER, WINNER и выход в меню (F) не моделируются (на Векторе — свой фронт).
'use strict';
const { NotModeled, u8, u16, ROOM, ACT, INPUT } = require('./core');
const S = require('./sys');
const F = require('./fight');
const A = require('./actors');
const R = require('./room');

const ctx = { animate_all: A.animate_all, draw: R.draw, next_room: R.next_room };

// $EA76: 2 очка из $E4C2 в счёт (5 цифр ASCII $DB86); false — нечего начислять (HUD не печатается)
function score_tick(M) {
  const hl = M.rd16(0xE4C2);
  if (!hl) return false;
  M.wr16(0xE4C2, u16(hl - 2));
  let p = 0xDB8A, a = u8(2 + M.rd(p));
  for (;;) {
    if (a < 0x3A) { M.wr(p, a); return true; }
    M.wr(p, a - 0x3A + 0x30);
    p--;
    a = M.rd(p);
    if (!a) return true;
    a = u8(a + 1);
  }
}

// $F554: идол у края комнаты по направлению: +1 идол, +200 очков, полная энергия; 6-й открывает комнату 10
function idol_take(M) {
  if (!M.rd(0xE88C)) return;
  const x = M.rd(ACT);
  if (M.rd(0xE1F3) ? x < 0x19 : x >= 3) return;
  M.sound('idol');
  M.wr(0xE4DB, 0); M.wr(0xE4DC, 0);
  M.inc(0xE4CC);
  M.wr16(0xE4C2, u16(M.rd16(0xE4C2) + 0xC8));
  if (M.rd(ROOM) !== 10) M.wr(R.idol_room(M).hl, 0);
  M.wr(0xE46D, 0x0F);
  if (M.rd(0xE4CC) === 6) { M.wr(0xDBD7, 7); M.wr(0xDBCA, 7); M.wr(0xD8DD, 0x0B); }   // $F5B2
}

// $ED23: один проход
function pass(M) {
  S.random(M);
  F.check_hits(M);
  if (M.rd(0xE8A9)) F.hit(M);
  if (M.rd(0xEE8C)) F.ko(M, ctx);
  if (M.rd(0xEE8E)) F.hero_death(M);
  A.enemy_throw(M);
  A.hero_action(M, ctx);
  A.enemy_state(M);
  A.enemy_ai(M);
  A.animate_all(M);
  R.draw(M);
  A.bars(M);
  if (M.rd(0xE8A8)) M.dec(0xE8A8);
  if (M.rd(0xE4CC) === 7) {
    M.wr(0xE88C, 0);
    if (M.rd(ROOM) === 4) throw new NotModeled('WINNER');
  }
  if (M.rd(ROOM) === 10 || R.idol_room(M).c) idol_take(M);
  if (score_tick(M)) R.score_hud(M);
  if (!M.rd(INPUT)) { A.read_controls(M); if (M.rd(INPUT)) M.wr(0xE8A4, 1); }
  if (!(M.in(0xFDFE) & 0x10)) {                               // G — пауза до любой клавиши управления
    do { M.wr(INPUT, 0); A.read_controls(M); } while (!M.rd(INPUT));
    return;
  }
  if (!(M.in(0xFDFE) & 0x08)) throw new NotModeled('F: в меню');
}

// $EC2D: новая игра с управлением ctl (0..4): идолы в 6 случайных комнатах, обнуления, комната 6 -> 4
function new_game(M, ctl) {
  M.wr(0xE1EC, ctl);
  for (let k = 0; k < 6; k++) M.wr(0xE4BC + k, 0);
  for (let k = 0; k < 6;) {
    const r = S.random(M) & 0x1F;
    if (r >= 0x14) continue;
    const a = r + 1;
    let dup = false;
    for (let i = 0; i < 6; i++) if (M.rd(0xE4BC + i) === a) dup = true;
    if (dup || a === 0x0B) continue;
    M.wr(0xE4BC + k, a); k++;
  }
  M.wr(0xEE8E, 0);
  for (let a = 0xE866; a <= 0xE887; a++) M.wr(a, 0);
  M.wr(0xE888, 0); M.wr(0xE889, 0); M.wr(0xE88A, 0);
  for (const a of [0xE4CC, 0xDBD7, 0xDBCA, 0xE4C2, 0xE4C3, 0xD8DD]) M.wr(a, 0);
  for (let a = 0xE461; a <= 0xE4BA; a++) M.wr(a, 0);
  for (const a of [0xE86D, 0xE878, 0xE883, 0xE88C]) M.wr(a, 1);
  M.wr(0xE1F3, 1); M.wr(0xE88D, 4); M.wr(0xE46D, 0x0F); M.wr(0xEE90, 0xFF);
  for (let k = 0; k < 5; k++) M.wr(0xDB86 + k, 0x30);
  A.reset_inputs(M);
  for (let k = 0; k < 4; k++) M.wr(0xDCE3 + k, M.rd(0xFA8B + k));
  for (let k = 0; k < 4; k++) M.wr(0xDCDE + k, M.rd(0xFA87 + k));
  if (M.rd(0xF924)) { M.wr16(0xE864, 0x2140); R.flip_frames(M); M.wr16(0xE864, 0); R.flip_frames(M); }
  M.wr16(0xE4C2, 0);
  R.place_enemies(M);
  M.wr(0xF924, 0);
  M.wr(ROOM, 6);
  for (const a of [0xE478, 0xE487, 0xE496, 0xE4A5, 0xE4B3]) M.wr(a, 3);   // $E4B3 = боец 5 +7 (у ZX так)
  R.next_room(M, 1, 0xFFFE);
  S.print_string(M, 0xDB63);                                   // $F5CB
}

module.exports = { pass, new_game, score_tick, idol_take, ctx };
