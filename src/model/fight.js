// Бой: попадания ($EF3F), удар ($EE4B), нокаут ($EE91, $EEE6, $EF24), гибель героя ($EE29), метательное
// оружие ($F3C3 полёт, $F40D подбор, $F476 чьё, $F277 попадания). Перевод с ZX по смыслу, адреса — игры.
'use strict';
const { NotModeled, u8, u16, ROOM, ACT, rec, INPUT, PHASE, proj } = require('./core');
const { random, print_name } = require('./sys');

// $F063: пересечение отрезков [L, L+H] и [E, E+D]; true = нет пересечения (перенос)
const apart = (h, l, d, e) => u8(h + l) < e || u8(d + e) < l;
const cur = (M) => M.rd16(0xE8A2);              // текущий боец (слово: $E8A3 читается вместе с ним)
const xof = (M, n) => M.rd(rec(n));             // $E809 по номеру

// звуковые события порта (озвучка Atari, docs/MUSIC.md): sw0/sw1 замах героя/врага, hit0/hit1 удар (канал — кто
// ударил; оружие — 0), ko — очки за нокаут, idol, room
function hit_sound(M) { }                       // $F06C — бипер ZX, у порта — событие hit в $EE4B

// $EF3F: удары врагов по герою (5..1), потом героя по врагам (1..5)
function check_hits(M) {
  if (M.rd(0xE8A8)) return;
  M.wr(0xE8A9, 0); M.wr(0xE8AA, 0);
  for (let b = 5; b >= 1; b--) {
    M.wr(0xE8A2, b);
    if (M.rd(rec(b) + 8)) continue;                      // исправление порта: поле +8 (у ZX — +7)
    const atk = M.rd(u16(0xFECA + M.rd(INPUT + b)));
    if (!atk || atk !== M.rd(u16(cur(M) + PHASE))) continue;
    const p = u16(0xFEF6 + 2 * M.rd(u16(cur(M) + INPUT)));
    let c = M.rd(p);
    if (!M.rd(0xE1F3)) c = u8(0x28 - c);
    let e = u8(8 * xof(M, M.rd(0xE8A2)) + c);
    if (apart(0x28, u8(8 * M.rd(ACT)), 2, e)) continue;
    e = u8(M.rd(rec(M.rd(0xE8A2)) + 1) + M.rd(p + 1));
    if (apart(0x30, M.rd(ACT + 1), 2, e)) continue;
    M.wr(0xE8AA, 0); M.wr(0xE8A9, 1);
  }
  for (let b = 1; b <= 5; b++) {
    M.wr(0xE8A2, b);
    if (M.rd(rec(b) + 8)) continue;
    const inp = M.rd(INPUT);
    const atk = M.rd(u16(0xFECA + inp));
    if (!atk || M.rd(PHASE) !== atk) continue;
    let c = M.rd(u16(0xFEF6 + 2 * inp));
    if (M.rd(0xE1F3)) c = u8(0x28 - c);
    const l = u8(8 * M.rd(ACT) + c);
    if (apart(2, l, 0x28, u8(8 * xof(M, M.rd(0xE8A2))))) continue;
    const e = u8(M.rd(ACT + 1) + M.rd(u16(0xFEF7 + 2 * inp)));
    if (apart(0x30, M.rd(rec(M.rd(0xE8A2)) + 1), 2, e)) continue;
    M.wr(0xE8AA, b); M.wr(0xE8A9, b);
    return;
  }
}

// $EE4B: боец $E8AA получил удар: энергия -= 3..7 (случайно); 0 — нокаут ($EE8C)
function hit(M, weapon) {
  if (M.rd(0xE8A8) || M.rd(0xEE8F)) return;
  M.sound(weapon || M.rd(0xE8AA) ? 'hit0' : 'hit1');
  const iy = rec(M.rd(0xE8AA));
  const r = (random(M) & 7) | 3;
  let a = M.rd(iy + 0x0C) - r;
  if (a <= 0) { M.wr(0xEE8C, 0xFF); M.wr(0xE8A8, 4); M.wr(0xEE8D, 4); a = 0; }
  M.wr(iy + 0x0C, a);
}

// $EE91: нокаут бойца $E8AA: очки, отметка; герой — $EF24
function ko(M, ctx) {
  if (M.rd(0xEE8F)) return;
  const e = M.rd(0xE8AA);
  const t = u16(0xE88D + e);
  const a = M.rd(t) & 3;
  M.wr(t, 0xFF);
  if (a < 3) M.wr16(0xE4C2, u16(M.rd16(0xE4C2) + u8(20 * (a + 1))));
  M.wr(0xEE8C, 0);
  M.wr(u16(PHASE + M.rd(0xE8AA)), 0);
  M.wr(rec(e) + 8, 0xFF);
  if (!M.rd(0xE8AA)) { hero_ko(M, ctx); return; }
  M.sound('ko');
  enemy_ko(M);
  M.wr(0xE8AA, 0);
}

// $EEE6: стереть имя нокаутированного; следующий враг в очереди (состояние 2) выходит на его место
function enemy_ko(M) {
  if (M.rd(0xEE8F)) return;
  const a = M.rd(0xEE90);
  if (a >= 3) return;
  print_name(M, a, 4);
  for (let k = 1; k <= 5; k++) {
    const iy = rec(k);
    if (M.rd(iy + 8) !== 2) continue;
    // $EF02 (эталоны не проходили)
    M.wr(iy + 0x0E, M.rd(0xEE90));
    M.wr(0xEE90, 0xFF);
    M.wr(iy + 8, 0);
    print_name(M, M.rd(iy + 0x0E), M.rd(iy + 0x0D));
    return;                                              // JR $EF22 -> RET
  }
}

// $EF24: герой в нокауте: два кадра анимации и вывод, начало гибели ($EE8E/$EE8F)
function hero_ko(M, ctx) {
  M.wr(INPUT, 0x30);
  ctx.animate_all(M); ctx.animate_all(M);
  const a = ctx.draw(M);
  M.wr(0xEE8E, a);
  M.wr(0xEE8F, 5);
  M.wr(PHASE, 0);
}

// $EE29: герой лежит 5 проходов, потом ждёт, пока начислятся очки, и GAME OVER
function hero_death(M) {
  const n = M.rd(0xEE8F);
  if (n) M.wr(0xEE8F, n - 1);
  else if (!M.rd16(0xE4C2)) throw new NotModeled('GAME OVER');
  M.wr(INPUT, 0x30);
  M.wr(0xE469, 0);
}

// $F476: оружие бойца $E88B: { z: есть, hl: запись оружия, b: регистр B на выходе (null — не менялся) }.
// Если боец ниже Y=$28 — Z с HL = адрес его Y ($F4AA: XOR A; RET), как у ZX.
function proj_of(M) {
  const n = M.rd(0xE88B);
  const hl = u16(0xE462 + 15 * n);
  if (M.rd(hl) >= 0x28) return { z: true, hl, b: n ? 0 : null };
  for (let j = 2; j >= 0; j--) if (u8(M.rd(0xE888 + j) - 1) === n) return { z: true, hl: proj(j), b: j + 1 };
  return { z: false, hl: 0, b: 0 };
}

// $F40D: боец $E88B подбирает лежащее рядом оружие (X-1 <= x < X+5): цель — над ним
function pick_up(M) {
  M.wr(0xE85A, 0);
  for (let j = 0; j < 3; j++) {
    const ix = proj(j), f = 0xE888 + j;
    if (M.rd(f)) continue;
    const n = M.rd(0xE88B), X = M.rd(rec(n));
    const c = u8(X - 1), b = u8(c + 6), x = M.rd(ix);
    if (x < c || x >= b) continue;
    M.wr(ix + 2, u8(X + 2)); M.wr(ix + 3, 0x39); M.wr(ix + 7, 1);
    M.wr(f, u8(n + 1)); M.wr(ix + 6, u8(n + 1)); M.wr(0xE85A, u8(n + 1));
  }
}

// $F3A7: мерцание/кадр летящего оружия
function proj_spin(M, iy, f) {
  if (M.rd(f) < 7) return;
  const v = M.dec(iy + 5);
  if (!(v & 0x80)) return;
  M.wr(iy + 5, M.rd(iy + 4) ? 3 : 1);
}

// $F3C3: шаг оружия к цели (+2,+3): X по 1, Y по 3; на месте — если владелец $E888 = +6, полёт кончен
function proj_move(M, j) {
  const iy = proj(j), f = 0xE888 + j;
  let c = 0;
  if (M.rd(iy + 7)) {
    if (M.rd(iy + 3) >= 0x39) M.wr(iy + 3, 0x39);
    proj_spin(M, iy, f);
    const x = M.rd(iy), tx = M.rd(iy + 2);
    if (x !== tx) { M.wr(iy, x < tx ? x + 1 : x - 1); c++; }
    const y = M.rd(iy + 1), ty = M.rd(iy + 3);
    if (y !== ty) { M.wr(iy + 1, y < ty ? y + 3 : y - 3); c++; }
  }
  if (!c && M.rd(iy + 6) === M.rd(f)) M.wr(iy + 7, 0);
}

// попадание оружием: оружие падает, удар
function proj_hit(M, iy, j, who, setFrame) {
  M.wr(0xE8AA, who); M.wr(0xE8A9, 1);
  M.wr(iy + 2, M.rd(iy)); M.wr(iy + 3, 0x1E); M.wr(iy + 6, 0x28);
  if (setFrame) M.wr(iy + 5, 0);
  M.wr(0xE888 + j, 0);
  hit(M, true);
}

// $F277: полёт оружия и попадания: $32 — брошено врагом (в героя), $64 — героем (во врагов)
function projectiles(M) {
  if (M.rd(0xE887)) return;
  for (let j = 0; j < 3; j++) proj_move(M, j);
  if (M.rd(0xE8A8)) return;
  for (let j = 2; j >= 0; j--) {
    const iy = proj(j);
    M.wr(0xF3A2, j);
    const own = M.rd(0xE888 + j);
    if (own === 0x32) {
      if (apart(8, u8(8 * M.rd(iy)), 8, u8(8 * M.rd(ACT) + 6))) continue;
      if (apart(8, M.rd(iy + 1), 0x30, M.rd(ACT + 1))) continue;
      if (M.rd(0xE8A9)) continue;
      proj_hit(M, iy, M.rd(0xF3A2), 0, false);
    } else if (own === 0x64) {
      for (let t = 5; t >= 1; t--) {
        M.wr(0xF3A4, t);
        const ix = rec(t);
        const l = u8(8 * M.rd(ix) + 6);
        M.wr(0xF3A6, M.rd(ix + 1));
        if (M.rd(ix + 8)) continue;
        if (apart(8, l, 8, u8(8 * M.rd(iy)))) continue;
        if (apart(0x30, M.rd(0xF3A6), 8, M.rd(iy + 1))) continue;
        if (M.rd(0xE8A9)) continue;
        proj_hit(M, iy, M.rd(0xF3A2), M.rd(0xF3A4), true);
      }
    }
  }
}

module.exports = { apart, check_hits, hit, ko, enemy_ko, hero_ko, hero_death, proj_of, pick_up, proj_move, projectiles, hit_sound, cur };
