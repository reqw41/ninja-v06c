// Комнаты: переход ($F699, $FB2A), расстановка врагов по всем комнатам ($E336), постройка комнаты
// ($EABC: поток тайлов $F62F/$F64C, пол, дыры $FDDC, идол $FAB3, стены $F107), разворот спрайтов при
// смене направления ($F925), бойцы и оружие новой комнаты ($F97E, $FA3D), вывод — только след в памяти
// игры ($E8AB: кадры и адреса бойцов, флаги поля, состояния оружия).
'use strict';
const { u8, u16, ROOM, ACT, rec, INPUT, PHASE, proj } = require('./core');
const S = require('./sys');
const F = require('./fight');
const A = require('./actors');

// --- постройка комнаты ---
// $EBAB: тайл $E4CB в карту ($E4DD) и на экран; указатели печати +1; счётчик клеток $E4C8 -1
function put_tile(M) {
  const d = M.rd16(0xE4DD);
  M.wr(d, M.rd(0xE4CB));
  M.wr16(0xE4DD, d + 1);
  const p = u16(M.rd16(0xDEF8) + 1);
  M.wr16(0xDEF8, p);
  M.wr16(0xDEF6, ((((p >> 8) & 3) << 3 | 0x40) << 8) | (p & 0xff));
  M.wr16(0xE4C8, u16(M.rd16(0xE4C8) - 1));
}
// $EB95: столбец 0..39, видны 4..35
function next_col(M) {
  const c = u8(M.rd(0xE4CA) + 1);
  M.wr(0xE4CA, c);
  if (c >= 0x28) { M.wr(0xE4CA, 0); return; }
  if (c < 4 || c >= 0x24) return;
  put_tile(M);
}
// $F64C: поток тайлов ($FF тайл n — n+1 повторов) до конца счётчика $E4C8
function stream(M) {
  for (;;) {
    let p = M.rd16(0xE4C4);
    const a = M.rd(p);
    p = u16(p + 1);
    M.wr16(0xE4C4, p);
    if (a === 0xFF) {
      const t = M.rd(p);
      let b = M.rd(u16(p + 1));
      M.wr16(0xE4C4, u16(p + 2));
      M.wr(0xE4CB, t);
      for (;;) {
        next_col(M);
        if (!M.rd16(0xE4C8)) return;
        if (b === 0) break;
        b--;
      }
    } else {
      M.wr(0xE4CB, a);
      next_col(M);
      if (!M.rd16(0xE4C8)) return;
    }
  }
}
// $F131: блок стены 15 строк по 4 тайла из источника шириной 40
function wall(M, hl, de, bc) {
  M.wr16(0xE4C4, hl); M.wr16(0xE4DD, de); M.wr16(0xDEF6, bc); M.wr16(0xDEF8, u16(bc + 0x1800));
  for (let r = 0; r < 15; r++) {
    for (let k = 0; k < 4; k++) {
      const p = M.rd16(0xE4C4);
      M.wr(0xE4CB, M.rd(p));
      M.wr16(0xE4C4, u16(p + 1));
      put_tile(M);
    }
    M.wr16(0xE4DD, u16(M.rd16(0xE4DD) + 0x1C));
    const p = u16(M.rd16(0xDEF8) + 0x1C);
    M.wr16(0xDEF8, p);
    M.wr16(0xDEF6, ((((p >> 8) & 3) << 3 | 0x40) << 8) | (p & 0xff));
    M.wr16(0xE4C4, u16(M.rd16(0xE4C4) + 0x24));
  }
}
// $F107: нет выхода влево/вправо — стена
function walls(M) {
  const p = u16(0xD897 + u8(4 * M.rd(ROOM)));
  if (!M.rd(p)) wall(M, 0x8134, 0x8AF7, 0x4040);
  if (!M.rd(u16(p + 1))) wall(M, 0x8158, 0x8B13, 0x405C);
}
// $FDDC: дыры комнаты из таблицы $DBB5 (X дыры в потолке, X дыры в полу); рисунок края — $FE25
function holes(M) {
  M.wr16(0xE4D9, S.table_word(M, 0xDBB5, M.rd(ROOM)));
  if (M.rd(0xE4D9)) M.wr16(0xFE25, 0xDBFF);
  if (M.rd(0xE4DA)) M.wr16(0xFE25, 0xDBDF);
}
// $FAF3: идол в этой комнате (ROOM+1 в $E4BC..$E4C1): { c, hl }
function idol_room(M) {
  const a = u8(M.rd(ROOM) + 1);
  let hl = 0xE4BC;
  for (let k = 0; k < 6; k++, hl++) if (M.rd(hl) === a) return { c: true, hl };
  return { c: false, hl };
}
// $FAB3: идол на экране у края по направлению ($E4DB — адрес на экране)
function idol_draw(M) { M.wr16(0xE4DB, S.table_word(M, 0xFB06, M.rd(0xE1F3))); }

// $EABC: постройка комнаты ROOM
function room_build(M) {
  const room = M.rd(ROOM);
  if (room === 1) { M.wr(0xE41E, 0x30); for (let k = 0; k < 8; k++) M.wr(0xD50C + k, 0); }
  else { M.wr(0xE41E, 0x28); for (let k = 0; k < 8; k++) M.wr(0xD50C + k, M.rd(0xD4EC + k)); }
  M.wr16(0xE4C4, S.table_word(M, 0xD9DE, room));
  M.wr16(0xE4DB, 0);
  M.wr(0xE4CA, 0x27); M.wr16(0xDEF6, 0x4000); M.wr16(0xDEF8, 0x5800); M.wr16(0xE4C8, 0x01E0); M.wr16(0xE4DD, 0x8AB7);
  stream(M);
  // $EB68: перекраска атрибутов в комнатах списка $EB56 — только экран
  M.wr16(0xE4C4, 0x7808); M.wr16(0xE4C8, 0x00C8); M.wr16(0xDEF6, 0x48D8); M.wr16(0xDEF8, 0x59D8);
  M.wr16(0xE4DD, 0x8C8F); M.wr(0xE4CA, 0x1B);
  stream(M);
  holes(M);
  if (idol_room(M).c) idol_draw(M);
  if (M.rd(ROOM) === 10) idol_draw(M);
  walls(M);
}

// --- переход ---
// $F925: развернуть 50 кадров (+смещение $E864): каждая строка задом наперёд с обращением битов,
// через карту тайлов $8AB7 как буфер
function flip_frames(M) {
  const off = M.rd16(0xE864);
  for (let f = 0x31; f >= 0; f--) {
    let p = u16(S.table_word(M, 0xDA0C, f) + off);
    let rows = M.rd(p) || 256;
    const w = M.rd(u16(p + 1));
    p = u16(p + 2);
    for (; rows > 0; rows--) {
      let hl = u16(0x8AB6 + w);
      for (let k = 0; k < (w || 256); k++) {
        let a = M.rd(p); p = u16(p + 1);
        if (a !== 0xFF && a !== 0) { let r = 0; for (let i = 0; i < 8; i++) { r = r << 1 | (a & 1); a >>= 1; } a = r; }
        M.wr(hl, a); hl = u16(hl - 1);
      }
      p = u16(p - (w || 256));
      for (let k = 0; k < (w || 256); k++) { M.wr(p, M.rd(u16(0x8AB7 + k))); p = u16(p + 1); }
    }
  }
}

// $E336: враги во всех комнатах: в каждом слоте, кроме последнего, с вероятностью 191/256, тип 1..3
function place_enemies(M) {
  for (let a = 0xDA85; a <= 0xDAED; a++) M.wr(a, 0);
  let hl = 0xDA70, de = 0xDA85;
  for (let r = 0; r < 21; r++) {
    const n = M.rd(hl); hl++;
    let d = de;
    for (let k = n; k >= 1; k--) {
      if (k !== 1 && random_ge(M, 0xBF)) continue;
      let t;
      do t = (S.random(M) & 0x18) >> 3; while (!t);
      M.wr(d, 0xF0 + t); d++;
    }
    de += 5;
  }
}
const random_ge = (M, v) => S.random(M) >= v;

// $FA3D: оружие j лежит в случайном месте (в комнате с врагом-метателем или в комнате 4)
function proj_place(M, j, hl) {
  const ix = proj(j);
  M.wr(hl, 0);
  for (;;) {
    if (M.rd(ROOM) !== 4) {
      // $FA8F: есть ли у первого врага комнаты тип (у ZX цикл проверяет только первый слот)
      const c = (M.rd(M.rd16(0xE862)) & 0xF0) ? 1 : 0;
      for (let f = 0xE888; f <= 0xE88A; f++) if (M.rd(f) >= 7) M.wr(f, 0xFF);
      M.wr(ix + 7, c);
      if (!c) { M.wr(0xE88B, 0xFF); M.wr(ix + 7, 0); M.wr(ix + 0x0A, 0); return; }
    }
    const r = S.random(M) & 0x1F;
    if (r < 3 || r >= 0x1B) continue;
    M.wr(ix, r); M.wr(ix + 2, r); M.wr(ix + 7, 1);
    M.wr(ix + 1, 0x1E); M.wr(ix + 3, 0x1E); M.wr(ix + 0x0A, 0x1E);
    M.wr(ix + 4, S.random(M) & 1); M.wr(ix + 5, 0);
    return;
  }
}

// $F97E: бойцы новой комнаты: герой у края по направлению, враги в ряд, кадр по типу
function place_actors(M) {
  M.wr(0xE8A1, 0xFF); M.wr(0xE462, 0x22); M.wr(0xE46A, 8);
  if (M.rd(0xE85C) >= 2) throw new (require('./core').NotModeled)('$FA27');
  M.wr(ACT, M.rd(u16(0xF97C + M.rd(0xE1F3))));
  let h = 0xE88E;
  for (let k = 1; k <= 5; k++) {
    const iy = rec(k);
    if (M.rd(iy + 8) === 3) continue;
    const a = M.rd(iy + 0x0D);
    M.wr(h, a); h++;
    M.wr(iy + 9, M.rd(u16(0xF96F + a)));
    if (!M.rd(iy + 0x0C)) { M.wr(iy + 9, 7); M.wr(iy + 8, 0xFF); }
    const t = M.rd(0xE1F3) ? 0xF977 : 0xF972;
    const n = M.inc(0xE8A1);
    M.wr(iy, M.rd(u16(t + n)));
    M.wr(iy + 1, 0x22);
    if (M.rd(iy + 0x0C)) M.wr(iy + 8, 0);
  }
  for (let k = 1; k <= 5; k++) {
    const iy = rec(k);
    if (M.rd(iy + 8) === 3) continue;
    if (!M.rd(iy + 0x0C)) { M.wr(iy + 8, 0xFF); continue; }
    if (M.rd(iy + 0x0E) === 0xFF) M.wr(iy + 8, 2);
  }
}

// $F699: в соседнюю комнату по направлению dir (0 влево, 1 вправо, 2 вверх, 3 вниз); 0 — выхода нет.
// sp — SP на входе в $F699 (у ZX его след остаётся в $DFE1 от очистки экрана)
function next_room(M, dir, sp) {
  // $FB2A
  const a = M.rd(u16(0xD897 + u8(4 * M.rd(ROOM) + dir)));
  if (!a) return 0;
  M.wr(ROOM, a - 1);
  S.clear_screen(M, u16(sp - 6));
  M.wr(0xDB8E, M.rd(u16(0xD8EB + M.rd(ROOM))));
  S.print_big(M, 0xDB8C);                                     // APPROACHING
  let hl = 0xD900;
  for (let k = M.rd(ROOM); k > 0; k--) { while (M.rd(hl)) hl++; hl++; }
  S.print_big(M, hl);                                         // имя комнаты
  M.sound('room');
  if (dir >= 2) place_enemies(M);
  M.wr(0xE85C, dir);
  if (dir < 2) {
    if (dir !== M.rd(0xE1F3)) {
      M.wr(0xF924, M.rd(0xF924) ^ 1);
      M.wr16(0xE864, 0x2140); flip_frames(M);
      M.wr16(0xE864, 0); flip_frames(M);
      const [x, y] = M.rd(0xE1F3) ? [0xFA87, 0xFA8B] : [0xFA8B, 0xFA87];
      for (let k = 0; k < 4; k++) M.wr(0xDCE3 + k, M.rd(x + k));
      for (let k = 0; k < 4; k++) M.wr(0xDCDE + k, M.rd(y + k));
    }
    M.wr(0xE1F3, dir);
  }
  // $F70A: энергия врагов старой комнаты — в её таблицу
  let t = M.rd16(0xE862);
  for (let k = 1; k <= 5; k++, t = u16(t + 1)) {
    const iy = rec(k);
    if (M.rd(iy + 8) === 3) continue;
    M.wr(iy + 3, 3);
    const e = M.rd(iy + 0x0C);
    M.wr(iy + 0x0C, 0);
    M.wr(t, u8(e * 16 + (M.rd(t) & 3)));
  }
  M.wr16(0xF91B, 0x2AF8);                                    // $F8F5: звук перехода (10 нот бипера)
  for (let k = 1; k <= 5; k++) M.wr(rec(k) + 8, 3);
  for (let k = 0xE88E; k <= 0xE892; k++) M.wr(k, 0);
  M.wr(0xE8A4, 0);
  const hn = M.rd(u16(0xFA85 + M.rd(0xE1F3)));
  M.wr(0xE46F, hn);
  S.print_name(M, hn, 3);
  if (M.rd(ROOM) !== 4) {
    let p = u16(0xDA85 + 5 * M.rd(ROOM));
    M.wr16(0xE862, p);
    for (let k = 1; k <= 5; k++, p = u16(p + 1)) {
      const iy = rec(k), v = M.rd(p);
      if (!v) { M.wr(iy + 8, 3); continue; }
      M.wr(iy + 0x0D, u8((v & 3) - 1));
      M.wr(iy + 8, 2);
      M.wr(iy + 0x0C, v >> 4);
      if (!(v >> 4)) { M.wr(iy + 0x0D, 0xFF); M.wr(iy + 8, 0xFF); }
    }
    const c = M.rd(0xE46F);
    let l = 0;
    for (let k = 1; k <= 5; k++) {
      const iy = rec(k);
      if (M.rd(iy + 8) === 3) continue;
      if (!M.rd(iy + 0x0C)) { M.wr(iy + 0x0E, 0xFF); continue; }
      let n = l;
      if (n === c) n++;
      if (n >= 3) { M.wr(iy + 0x0E, 0xFF); continue; }
      M.wr(iy + 0x0E, n); l = n;
      M.wr(iy + 8, 0);
      S.print_name(M, M.rd(iy + 0x0E), M.rd(iy + 0x0D));
      l++;
    }
  }
  // $F800
  M.wr(0xE3A3, 0x2A);
  for (let k = 0; k < 5; k++) if (M.rd(0xF694 + k) === M.rd(ROOM)) { M.wr(0xE3A3, 0x2C); break; }
  room_build(M);
  const room = M.rd(ROOM);
  if (room === 0x14) M.wr(0xFF51, 0x60);                     // $FF48: двери (атрибуты)
  if (room === 0x13) { M.wr(0xFF51, 0x50); M.wr(0xFF51, 0x60); }
  for (let j = 0; j < 3; j++) {
    const ix = proj(j), f = 0xE888 + j;
    const v = M.rd(f);
    if (v >= 7) { M.wr(ix + 6, 0); M.wr(f, 0); }
    M.wr(ix + 7, 0);
    if (v === 0xFF) proj_place(M, j, f);
    if (v === 0) proj_place(M, j, f);
  }
  S.print_string(M, 0xDB63);                                 // $F5CB
  score_hud(M);
  for (let b = 5; b >= 1; b--) {
    const e = M.rd(0xE88D + b);
    let v = null;
    if (!(e & 0xF0)) v = 0x2C;
    else v = [0x1C, 0x15, 0x21, null][e & 3];
    if (v !== null) M.wr(INPUT + b, v);
  }
  for (let k = 0; k < 6; k++) M.wr(PHASE + k, 0);
  A.animate_all(M);
  place_actors(M);
  M.wr(0xE893, 0);
  const hf = M.rd(0xE4DA);
  if (hf) { M.wr(0xE89F, u8(hf - 5)); M.wr(0xE8A0, u8(hf + 5)); }
  else { M.wr(0xE8A0, 0); M.wr(0xE89F, 0xFF); }
  return 5;
}

// $EAA7: строка HUD: число идолов и строки
function score_hud(M) {
  S.print_string(M, 0xDB81);
  M.wr(0xDB7F, u8(M.rd(0xE4CC) + 0x30));
  S.print_string(M, 0xDB7A);
}

// --- вывод: след в памяти игры ---
// $E8DB: кадр бойца k из таблицы $DA0C: высота/ширина (+2/+3), указатель данных (+6/+7), адрес в
// заднем буфере (+4/+5), адрес на экране (+A/+B; X у краёв сдвинут)
function actor_frame(M, k) {
  const ix = rec(k);
  const hl = S.table_word(M, 0xDA0C, M.rd(ix + 9));
  const h = M.rd(hl), w = M.rd(u16(hl + 1));
  M.wr(ix + 2, h); M.wr(ix + 3, w);
  M.wr16(ix + 6, u16(hl + 2));
  const s = M.rd16(u16(0xD717 + 2 * u8(M.rd(ix + 1) + h + 0x0C)));
  let a = M.rd(ix);
  if (a >= 2) { a = a - 1; if (u8(a + w) >= 0x1D) a = u8(a - 2); }
  M.wr16(ix + 0x0A, u16(s + a));
  const b = M.rd16(u16(0xD717 + 2 * u8(M.rd(ix + 1) + h)));
  M.wr16(ix + 4, u16(b + M.rd(ix) + 0x1B00));
}
// $E8AB: проход вывода; возвращает A на выходе (= состояние бойца 5, его читает $EF24)
function draw(M) {
  for (let k = 0; k < 6; k++) if (M.rd(rec(k) + 1) > 0x28) M.wr(0xE2D4, 1);
  M.wr16(0xE2D2, M.rd(0xE2D4) ? 0x5AA0 : 0x5A80);           // $E2D5: поле 320 или 672 клетки
  M.wr(0xE2D4, 0);
  for (let k = 0; k < 6; k++) actor_frame(M, k);
  // $F21B: стереть оружие; вне поля X — больше не рисовать
  for (let j = 0; j < 3; j++) {
    const iy = proj(j);
    if (!M.rd(iy + 0x0A)) continue;
    if (M.rd(iy + 1) < 0x20 && !M.rd(0xE888 + j)) continue;
    const x = M.rd(iy);
    if (!x || x >= 0x20) M.wr(iy + 0x0A, 0);
  }
  F.projectiles(M);
  // $F1B4: нарисовать оружие (лежит на полу Y=$1E или летит)
  for (let j = 0; j < 3; j++) {
    const iy = proj(j);
    if (!M.rd(iy + 0x0A)) continue;
    if (M.rd(iy + 1) !== 0x1E && !M.rd(iy + 7)) continue;
    const x = M.rd(iy);
    M.wr(iy + 0x0A, x >= 0x20 ? x : 1);
  }
  return M.rd(0xE4B4);
}

module.exports = { room_build, stream, walls, holes, idol_room, idol_draw, flip_frames, place_enemies, proj_place,
  place_actors, next_room, score_hud, actor_frame, draw };
