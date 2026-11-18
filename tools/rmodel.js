// rmodel.js — модель вывода Вектора на JS (владелец 15.11: «оптимизировать вывод через JS, потом снова i8080»).
// Повторяет rect_draw (src/vec/render.asm) -> col_draw / span_calc / ov_proj / ov_actors / contrib / ct_split /
// cs_go / cd_band / cc_band / col_copy (src/vec/field.asm, stk.asm, page0.asm) на копии памяти и считает операции.
// Сверка: tools/vecstep.js RMODEL=1 — экран модели против экрана i8080 после каждого rect_draw.
'use strict';

function make(SYM) {
  const S = (n) => { if (SYM[n] === undefined) throw new Error('нет символа ' + n); return SYM[n]; };
  const CP_H = 0x32, BAND = 88, HDR = 6;   // фон поднят на 8 строк, строка клеток 21 — пол (16.11)
  const A = {
    rb_c0: S('rb_c0'), rb_c1: S('rb_c0') + 1, rb_lo: S('rb_c0') + 2, rb_hi: S('rb_c0') + 3,
    cur: S('cur'), pcur: S('pcur'), CMAP: S('CMAP'), cdesc: S('cdesc'), NA: S('NA'), pool_a: S('pool_a'),
    POOL_B: S('POOL_B'), band_ok: S('band_ok'),
  };
  const msk = (s) => (0xFF >> s) & 0xFF;
  const rotr = (b, s) => ((b >> s) | (b << (8 - s))) & 0xFF;

  // m — Uint8Array 64K (меняется на месте); возвращает счётчики операций
  function rectDraw(m) {
    const n = { cols: 0, cells: 0, cellScr: 0, cellStr: 0, cellBand: 0, planes: 0, spanEnt: 0, projChk: 0,
      projRows: 0, actChk: 0, contrib: 0, rowsT: 0, rowsO3: 0, rowsO2: 0, copyB: 0, copyPl: 0, scrSame: 0, uni: 0, zero: 0, cU: 0, cUs: 0 };
    let lo = m[A.rb_lo]; if (lo < 24) lo = 24; lo &= 0xF8;
    let hi = m[A.rb_hi]; if (hi >= 200) hi = 199; hi |= 7;
    if (hi < lo) return n;
    let c1 = m[A.rb_c1]; if (c1 >= 32) c1 = 31;
    const band = m[A.band_ok];
    for (let col = m[A.rb_c0]; col < c1; col++) colDraw(m, col & 0xFF, lo, hi, band, n);
    return n;
  }

  function stAddr(m, id) { return id < A.NA ? A.pool_a + 8 * id : A.POOL_B + 8 * (id - A.NA); }

  function span(m, col, lo, hi, n) {
    let sl = 0xFF, sh = 0;
    const add = (d, e) => { if (d < sl) sl = d; if (e > sh) sh = e; };
    for (let k = 5; k >= 0; k--) {
      const e = A.cur + 8 * k; n.spanEnt++;
      if (!m[e]) continue;
      const d = (col - m[e + 1]) & 0xFF;
      if (d < m[e + 4]) add(m[e + 2], m[e + 3]);
    }
    for (let j = 0; j < 3; j++) {
      const r = A.pcur + 5 * j;
      if (!m[r] || !m[r + 1]) continue;
      const px = m[r + 1], c = px >> 3;
      if (col === c || (((col - c) & 0xFF) === 1 && (px & 7) >= 3)) add((m[r + 2] - 7) & 0xFF, m[r + 2]);
    }
    if (!sh) return [0, 0];
    sh = Math.min(sh, hi) | 7; sl = Math.max(sl, lo) & 0xF8;
    if (sh < sl) return [0, 0];
    return [sl, sh];
  }

  function colDraw(m, col, lo, hi, band, n) {
    n.cols++;
    const [sl, sh] = span(m, col, lo, hi, n);
    for (let i = hi; i >= lo; i -= 8) {
      n.cells++;
      const rr = 24 - ((i >> 3) & 31);
      const cell = m[A.CMAP + (col - 1) * 22 + rr];
      let cd = A.cdesc + 3 * cell;
      const uni = cell >= 0xF8 ? [cell & 1, (cell >> 1) & 1, (cell >> 2) & 1] : null;   // cl_uni / cu_fill
      const inSpan = sh && i >= sl && i <= sh;
      let page, L, step, planes;
      if (inSpan && band && i < BAND) { n.cellBand++; cd++; page = CP_H + 1; L = i; step = 1; planes = 2; }
      else if (inSpan) { n.cellStr++; page = CP_H; L = i; step = 1; planes = 3; }
      else { n.cellScr++; page = 0xA0 + col; L = i + 32; step = 0x20; planes = 3; }
      let chg = 0;
      { const ids = uni ? uni : [0, 1, 2].slice(0, planes).map((q) => m[cd + q]); if (ids.every((x) => x < 2)) { n.cU++; if (!inSpan) n.cUs++; } }
      for (let p = 0; p < planes; p++) {
        n.planes++;
        const id = uni ? uni[cd - (A.cdesc + 3 * cell) + p] : m[cd + p];
        const src = stAddr(m, id);
        { let u = 1; for (let j = 1; j < 8; j++) if (m[src + j] !== m[src]) u = 0; if (u) { n.uni++; if (!m[src]) n.zero++; n["v" + m[src].toString(16)] = (n["v" + m[src].toString(16)] || 0) + 1; } }
        for (let j = 0; j < 8; j++) { const ad = ((page + p * step) << 8) | ((L - j) & 0xFF); if (!inSpan && m[ad] !== m[src + j]) chg = 1; m[ad] = m[src + j]; }
      }
      if (!inSpan && !chg) n.scrSame++;
    }
    if (!sh) return;
    ovProj(m, col, sl, sh, n);
    ovActors(m, col, sl, sh, band, n);
  }

  function ovProj(m, col, lo, hi, n) {
    for (let j = 0; j < 3; j++) {
      const r = A.pcur + 5 * j; n.projChk++;
      if (!m[r] || !m[r + 1]) continue;
      const px = m[r + 1], s = px & 7, c = px >> 3;
      let mk = msk(s);
      if (col !== c) { if (((col - c) & 0xFF) !== 1 || s < 3) continue; mk = ~mk & 0xFF; }
      let C = m[r + 2], de = m[r + 3] | m[r + 4] << 8;
      for (let k = 0; k < 8; k++, de++, C = (C - 1) & 0xFF) {
        if (C > hi || C < lo) continue;
        n.projRows++;
        const v = rotr(m[de], s) & mk;
        const a = (CP_H << 8) | C, cc = ((CP_H + 1) << 8) | C, ee = ((CP_H + 2) << 8) | C;
        m[a] &= ~v; m[cc] |= v; m[ee] |= v;
      }
    }
  }

  function ovActors(m, col, lo, hi, band, n) {
    for (let k = 5; k >= 0; k--) {
      const e = A.cur + 8 * k; n.actChk++;
      if (!m[e]) continue;
      const d = (col - m[e + 1]) & 0xFF, top0 = m[e + 3];
      if (d >= m[e + 4]) continue;
      const hdr = m[e + 5] | m[e + 6] << 8, s = m[e + 7] & 7, wv = m[hdr + 1], am = msk(s);
      if (d < wv) contrib(m, hdr, d, am, s, top0, lo, hi, band, n);
      if (s && d) contrib(m, hdr, d - 1, ~am & 0xFF, s, top0, lo, hi, band, n);
    }
    // копия полос на экран (cc_band / col_copy)
    const copy = (pl, l0, l1) => {
      n.copyPl++;
      const cnt = ((l1 - l0 + 1) >> 3) * 8;
      for (let q = 0; q < cnt; q++) { m[((0xA0 + 0x20 * pl + col) << 8) | ((l0 + 32 + q) & 0xFF)] = m[((CP_H + pl) << 8) | ((l0 + q) & 0xFF)]; n.copyB++; }
    };
    if (band && lo < BAND) { copy(1, lo, hi); copy(2, lo, hi); if (hi >= BAND) copy(0, BAND, hi); }
    else { copy(0, lo, hi); copy(1, lo, hi); copy(2, lo, hi); }
  }

  function contrib(m, hdr, C, mask, s, top0, lo, hi, band, n) {
    n.contrib++;
    const ent = hdr + HDR + 4 * C;
    let de = m[ent] | m[ent + 1] << 8;
    const r0 = m[ent + 2], cnt = m[ent + 3];
    if (!cnt) return;
    const top = (top0 - r0) & 0xFF, bot = (top - cnt + 1) & 0xFF;
    const is = Math.min(top, hi), ie = Math.max(bot, lo);
    if (is < ie) return;
    let rows = is - ie + 1;
    de += 2 * (top - is);
    let L = is;
    let n3 = rows;                                      // строки в 3 плоскости (выше полосы пола)
    if (band) { const a = is - (BAND - 1); n3 = a <= 0 ? 0 : Math.min(a, rows); }
    for (let r = 0; r < rows; r++, L = (L - 1) & 0xFF, de += 2) {
      const p0 = rotr(m[de], s) & mask, p1 = rotr(m[de + 1], s) & mask, M = p0 | p1;
      if (!M) { n.rowsT++; continue; }
      const nm = ~M & 0xFF, three = r < n3;
      if (three) { m[(CP_H << 8) | L] &= nm; n.rowsO3++; } else n.rowsO2++;
      const cc = ((CP_H + 1) << 8) | L, ee = ((CP_H + 2) << 8) | L;
      m[cc] = (m[cc] & nm) | p1;
      m[ee] = (m[ee] & nm) | (p0 & p1);
    }
  }

  return { rectDraw };
}

module.exports = { make };
