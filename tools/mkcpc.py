#!/usr/bin/env python3
"""CPC look for the Vector (owner 14.11.2026): fighters = CPC frames, room colours = CPC (scheme of Bruce Lee).

  python3 tools/mkcpc.py      (needs Pillow for the palette votes; CPC disk image in orig/, tour shots in build/)

Writes src/vec/gen/cpc.asm:
- fighters unpacked by columns (owner: «store them ready»): cpc_frp — 50 pointers (ZX frame order) to headers
  x0 (signed bytes from the ZX frame box left), wv, top (rows below the box top), h, hzx, wzx, then wv column
  entries: ptr (2), r0 (first row), n (rows); column data = n rows x (P0, P1) — pens 1 black 01, 2 orange 10,
  3 salmon 11, 0 transparent; transparent rows at the top and bottom of a column are not stored. Orientation:
  as the CPC (ZX $F924 = 0); the Vector flips all frames in place when the direction changes (cpc_data..cpc_data_end).
  CPC: NINJA3.BIN frame table $79D1 (48), composites $7DC1; alignment to the ZX box by silhouette, step 4 px.
  The hero (black) frames lose single coloured pixels inside the silhouette below the head (owner 14.11).
- room palettes: pal_rooms (21 x 16), remap_up / remap_fl (21 x 8: ZX colour -> palette index, rows 0..13 / 14..20),
  pal_appr.
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpcspr import load_cpc, cpc_frame, zx_frame, align, walk_dx   # noqa: E402
import cpcpal                                              # noqa: E402
import geom15                                              # noqa: E402
import cpcroom                                             # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


WALK_HERO = (9, 10, 11, 12, 13, 14)


PINK = 0xA7                                         # телесное CPC (255,128,128) на Векторе: R7 G4 B2


def frame_cols(pix, y0, y1, dy, h, w, q, org):
    """кадр из точек pix ((n, y) -> перо) с началом данных org (точка = бит 7 столбца 0): заголовок и столбцы"""
    nmax = max(n for n, _ in pix)
    wv, hh = (nmax - org + 8) // 8, y1 - y0 + 1
    p0 = [[0] * hh for _ in range(wv)]
    p1 = [[0] * hh for _ in range(wv)]
    for (n, y), p in pix.items():
        px = n - org
        j, bit = px // 8, 0x80 >> (px % 8)
        if p & 1: p0[j][y - y0] |= bit
        if p & 2: p1[j][y - y0] |= bit
    cols = []
    for j in range(wv):
        nz = [i for i in range(hh) if p0[j][i] | p1[j][i]]
        if not nz:
            cols.append((0, 0, b''))
            continue
        r0, r1 = nz[0], nz[-1]
        cols.append((r0, r1 - r0 + 1, bytes(b for i in range(r0, r1 + 1) for b in (p0[j][i], p1[j][i]))))
    return (org, wv, y0 + dy, hh, h, w, cols, q)


def main():
    c = load_cpc()
    hdrs, cols_data, src = [], [], {}
    total = 0
    wdx = walk_dx(c)
    for f in range(50):
        dx, dy, q = align(f, c)
        if f in wdx:
            dx = wdx[f]
        rows, _ = cpc_frame(c, f)
        rows = [list(r) for r in rows]
        ys = [y for y, r in enumerate(rows) if any(r)]   # сетка 4 точки ZX (2 точки CPC = 3 Вектора) — по левому краю
        hl = 2 * min(x for y in ys[:2] for x, p in enumerate(rows[y]) if p)   # головы: одна фаза x0.75, голова одна
        dx = int(round((dx + hl) / 4.0)) * 4 - hl
        h, w, _, _ = zx_frame(f)
        blk = sum(1 for r in rows for p in r if p == 1)
        col = sum(1 for r in rows for p in r if p > 1)
        if blk > 3 * col:                               # герой: без одиночных цветных точек ниже головы
            ys0 = min(y for y, r in enumerate(rows) if any(r))
            for y in range(ys0 + 8, len(rows)):         # и без розовых (перо 3) пятен на теле (прыжок, владелец 15.11)
                rows[y] = [1 if p == 3 else p for p in rows[y]]
            for y in range(10, len(rows)):
                r = rows[y]
                for i in range(1, len(r) - 1):
                    if r[i] > 1 and r[i - 1] == 1 and r[i + 1] == 1:
                        r[i] = 1
        ys = [y for y, r in enumerate(rows) if any(r)]
        y0, y1 = ys[0], ys[-1]
        pix = {}                                        # x1.5: новая точка n (от левого края рамки ZX) — точка CPC
        for y in range(y0, y1 + 1):                     # cx = floor(((n + 0.5) * 4/3 - dx) / 2)
            r = rows[y]
            for n in range(-48, 96):
                cx = math.floor(((n + 0.5) * 4 / 3 - dx) / 2)
                if 0 <= cx < len(r) and r[cx]:
                    pix[n, y] = r[cx]
        src[f] = (pix, y0, y1, dy, h, w, q)
        if f in WALK_HERO:
            hdrs.append(None)                           # кадры ходьбы героя — готовые со сдвигом (50..57)
            continue
        hdrs.append(frame_cols(pix, y0, y1, dy, h, w, q, min(n for n, _ in pix)))
    # ходьба героя (владелец 15.11, как Bruce Lee): кадр по X mod 4, сдвиг внутри байта зашит в кадр — вывод без
    # вращений, шаг ровно 6 точек как у CPC. 50..53 — лицом вправо (12, 13, 14, 13), 54..57 — влево (9, 10, 11, 10
    # в обратном порядке: X убывает); X ≡ k: позиция 32 + 6X + ox кратна 8
    for k in range(8):
        fs = [12, 13, 14, 13][k] if k < 4 else [9, 10, 11, 10][(4 - (k - 4)) % 4]
        kk = k % 4
        pix, y0, y1, dy, h, w, q = src[fs]
        nmin = min(n for n, _ in pix)
        r = (32 + 6 * kk + nmin) % 8
        hdrs.append(frame_cols(pix, y0, y1, dy, h, w, q, nmin - r))
    for hd in hdrs:
        if hd:
            total += sum(len(cdat) for _r0, _n, cdat in hd[6])
    out = ['; generated by tools/mkcpc.py: CPC fighters unpacked by columns, CPC room palettes',
           '; header: x0, wv, top, h, hzx, wzx; then wv x (ptr, r0, n); column: n rows x (P0, P1)',
           'CPC_HDR\tEQU\t6', 'cpc_frp:']
    out += [f'\t\t\tDW\tcpc_f{f if hdrs[f] else "z"}' for f in range(58)]
    out.append('cpc_fz:\t\tDB\t0,0,0,0,0,0\t\t; кадры 9..14 не выводятся (ходьба героя — 50..57)')
    for f, hd in enumerate(hdrs):
        if not hd:
            continue
        x0, wv, top, hh, hz, wz, cols, q = hd
        out.append(f'cpc_f{f}:\t\t\t\t; ZX {f}: совпадение с силуэтом {q:.2f}')
        out.append(f'\t\t\tDB\t{x0 & 0xFF},{wv},{top & 0xFF},{hh},{hz},{wz}')
        for j, (r0, n, data) in enumerate(cols):
            out.append(f'\t\t\tDW\t{"cpc_c%d_%d" % (f, j) if n else "0"}\n\t\t\tDB\t{r0},{n}')
    def emit(rng):
        for f in rng:
            if not hdrs[f]:
                continue
            for j, (r0, n, data) in enumerate(hdrs[f][6]):
                if n:
                    out.append(f'cpc_c{f}_{j}:')
                    out.extend('\t\t\tDB\t' + ','.join(f'0x{b:02X}' for b in data[i:i + 24]) for i in range(0, len(data), 24))
    out.append('cpc_data:')
    emit(range(50))
    out.append('cpc_data_end:')                         # разворот на месте — только 0..49 (готовые 50..57 — нет)
    emit(range(50, 58))
    # комнаты целиком как CPC (владелец 15.11): палитра из чернил CPC ($7C54), полосы строк — перо тайла (0..3) ->
    # номер палитры по таблице перекраски комнаты ($7A31); номер плоскости k = функция f (таблица истинности по перу)
    d = cpcroom.ram()
    img = geom15.zx_img()
    out.append('pal_rooms:')
    rr = []
    for t in range(21):
        rgb, pen_idx, runs = cpcroom.room_colours(d, t, img)
        rr.append((pen_idx, runs))
        b = [cpcpal.vec_byte(x) for x in rgb]
        for c, v in VEC_OVR.get(t, {}).items():      # ручные цвета владельца: RGB CPC -> байт Вектора
            b = [v if rgb[i] == c else b[i] for i in range(8)]
        b[3] = PINK                                 # телесное бойцов (владелец 15.11: «A7» — 0x5F сливался с оранжевым)
        out.append('\t\t\tDB\t' + ','.join(f'0x{x:02X}' for x in b) + f'\t; комната {t}')
    # владелец 17.11: линия пола в плоскостях бойцов — 1, если A000 полосы пола пуста (сборка полосы в 2 плоскостях)
    out.append('room_band:\tDB\t' + ','.join('0' if cpcroom.BAND_A[t] else '1' for t in range(21)))
    out.append('; полосы: число; (строка ZX начала, f2, f1, f0): f — таблица истинности бита плоскости по перу 0..3')
    out.append('room_runs:')
    out += [f'\t\t\tDW\trr_{t}' for t in range(21)]
    lo = ['; generated by tools/mkcpc.py: полосы строк части комнат и pal_appr — в нижней области (место, 16.11)']
    stk = ['; generated by tools/mkcpc.py: полосы строк части комнат — в странице стека после кода (место, 18.11)']
    for t, (pen_idx, runs) in enumerate(rr):
        dst = lo if t in LO_RUNS else stk if t in STK_RUNS else out
        ent = []
        for y, idx in runs:
            f = [sum(((idx[p] >> k) & 1) << p for p in range(4)) for k in (2, 1, 0)]
            ent.append(f'{y},{f[0]},{f[1]},{f[2]}')
        dst.append(f'rr_{t}:\t\tDB\t{len(runs)}')
        dst += ['\t\t\tDB\t' + e for e in ent]
    import json                                     # перо CPC -> номер палитры: только для сверки (tools/vecstep.js)
    json.dump([pi for pi, _ in rr], open(os.path.join(ROOT, 'src/vec/gen/pen_idx.json'), 'w'))
    json.dump([0 if cpcroom.BAND_A[t] else 1 for t in range(21)], open(os.path.join(ROOT, 'src/vec/gen/band.json'), 'w'))
    ap = [0x00, 0x5B, 0x1F, PINK, 0x00, 0x00, 0x00, 0x3F]   # 1 — серый: поля и HUD (владелец 18.11, всё вне комнаты серое)
    lo.append('pal_appr:\tDB\t' + ','.join(f'0x{x:02X}' for x in ap))
    open(os.path.join(ROOT, 'src/vec/gen/cpc_lo.asm'), 'w').write('\n'.join(lo) + '\n')
    open(os.path.join(ROOT, 'src/vec/gen/cpc_stk.asm'), 'w').write('\n'.join(stk) + '\n')
    out += geom15_tables()
    open(os.path.join(ROOT, 'src/vec/gen/cpc.asm'), 'w').write('\n'.join(out) + '\n')
    ncols = sum(len(h[6]) for h in hdrs if h)
    print(f'frames: data {total} bytes, headers {50 * 2 + 50 * 6 + ncols * 4}; palettes {21 * 32} bytes')


LO_RUNS = (0,)                                    # комнаты, чьи полосы строк — в нижней области
# владелец 18.11: «столбы ворот (красный) и оранжевый выглядят одинаково, можно столбы ворот сделать малиновыми»
VEC_OVR = {3: {(255, 0, 0): 0x46}}
STK_RUNS = (8,)                                   # ... в странице стека (src/vec/stk.asm, до 9FB0)


def cpc_weapon(tab, n):
    d = cpcroom.ram()
    w = lambda a: d[a] | d[a + 1] << 8
    out = []
    for k in range(n):
        a = w(tab + 2 * k)
        rows = [[0] * 6 for _ in range(5)]
        for r in range(5):
            for j in range(3):
                b = d[a + 3 * r + j]
                rows[r][2 * j] = (b >> 7 & 1) | (b >> 3 & 1) << 1 | (b >> 5 & 1) << 2 | (b >> 1 & 1) << 3
                rows[r][2 * j + 1] = (b >> 6 & 1) | (b >> 2 & 1) << 1 | (b >> 4 & 1) << 2 | (b & 1) << 3
        assert not any(rows[r][5] for r in range(5))
        pic = [0] * 8
        for r in range(5):
            for nn in range(8):
                if rows[r][2 * nn // 3]:
                    pic[r + 1] |= 0x80 >> nn
        out += pic
    return out


def keep6(b):
    v = 0
    for j, k in enumerate(geom15.KEEP):
        if b & (0x80 >> k):
            v |= 0x80 >> j
    return v


def geom15_tables():
    """x1.5: tiles of 6 px (gen/tiles6.asm, in place of the ZX tiles), column table, custom tiles for the holes and
    the idol (unused tile numbers), weapon pictures of 6 px"""
    img = geom15.zx_img()
    Z = lambda a: img[a - 0x4000]
    used = {160, 156}
    for t in range(21):
        for r in geom15.room40(img, t):
            used |= set(r)
    free = [t for t in range(225) if t not in used]
    assert not any(Z(0xD00C + k) for k in range(8)), 'тайл 0 не пуст'
    d = cpcroom.ram()
    t6, tb = cpcroom.tile_planes(d)
    # плотная таблица (место): только тайлы комнат (+ $9C/$A0) и 24 своих тайла дыр/идола; tremap — номер ZX -> плотный
    comp = sorted(used) + free[:24]
    tremap = [0] * 256
    for i, t in enumerate(comp):
        tremap[t] = i
    A = [b for t in comp for b in t6[8 * t:8 * t + 8]]
    B = [b for t in comp for b in tb[8 * t:8 * t + 8]]
    lines = ['; generated by tools/mkcpc.py: CPC tiles ($4721) x1.5, pen bit 0 (bits 7..2 = 6 points), dense table',
             f'T_N\t\tEQU\t{len(comp)}\t\t; тайлов', f'T_9C\t\tEQU\t{tremap[0x9C]}', f'T_A0\t\tEQU\t{tremap[0xA0]}']
    lines += ['\t\t\tDB\t' + ','.join(f'0x{b:02X}' for b in A[i:i + 16]) for i in range(0, len(A), 16)]
    lines.append('tremap:\t\t\t\t\t; номер тайла ZX -> плотный')
    lines += ['\t\t\tDB\t' + ','.join(str(b) for b in tremap[i:i + 32]) for i in range(0, 225, 32)]
    open(os.path.join(ROOT, 'src/vec/gen/tiles6.asm'), 'w').write('\n'.join(lines) + '\n')
    out = ['; тайлы CPC x1.5: бит 1 пера (бит 0 — gen/tiles6.asm на месте тайлов ZX), плотная таблица', 'tile_b:']
    out += ['\t\t\tDB\t' + ','.join(f'0x{b:02X}' for b in B[i:i + 16]) for i in range(0, len(B), 16)]
    # группы своих тайлов: DB число; записи: DB смещение клетки (от строки группы), номер тайла, исходный (место),
    # 8 байт узора (OR к тайлу 6 точек)
    k = 0
    def grp(name, row, ents):
        nonlocal k
        res = [f'{name}:\t\t\t\t; строка {row}', f'\t\t\tDW\t{row * 32}', f'\t\t\tDB\t{len(ents)}']
        for off, pat in ents:
            res.append(f'\t\t\tDB\t{off},{free[k]},0,' + ','.join(f'0x{keep6(b):02X}' for b in pat))
            k += 1
        return res
    def grp6(name, row, ents):               # узор уже в 6 точках
        nonlocal k
        res = [f'{name}:\t\t\t\t; строка {row}', f'\t\t\tDW\t{row * 32}', f'\t\t\tDB\t{len(ents)}']
        for off, pat in ents:
            res.append(f'\t\t\tDB\t{off},{free[k]},0,' + ','.join(f'0x{b:02X}' for b in pat))
            k += 1
        return res
    # идол CPC (снимок MAME): 11 x 8 точек режима 0, Y — жёлтый (перо 3 -> жёлтый номер комнаты в строках 152..159),
    # B — чёрный узор (перо 1); 11 точек -> 16 Вектора (3 тайла), строка тайлов 19; ct_idol — силуэт (перо 3),
    # ct_idolb — узор (те же свои тайлы, бит 1 пера &= ~узор)
    # владелец 18.11: идол как в версии Atari ST (снимок atarilegend, фигурка 10 x 12): 7 x 8 точек Вектора (по высоте —
    # одна строка клеток), тело — перо 3 (оранжевый), контур — чёрный узор, глаза и руки — просветы пола; по центру 3 тайлов
    pic = ['......KRK.......',
           '.....KRRRK......',
           '.....K.R.K......',
           '......KRK.......',
           '.....KRRRK......',
           '....KR.R.RK.....',
           '....KRRRRRK.....',
           '.....KKKKK......']
    def ipat(kk, ch):
        return [sum(0x80 >> j for j in range(6) if pic[r].ljust(18, '.')[6 * kk + j] in ch) for r in range(8)]
    out += grp6('ct_idol', 19, [(kk, ipat(kk, 'KR')) for kk in (0, 1, 2)])
    k -= 3
    out += grp6('ct_idolb', 19, [(kk, ipat(kk, 'K')) for kk in (0, 1, 2)])
    for name, row, base in (('ct_hc', 0, 0xDBFF), ('ct_hf', 19, 0xDBDF)):
        p = [Z(base + i) for i in range(32)]
        ents = []
        for rr in (0, 1):
            for d in range(5):
                pat = []
                for c in range(8 * rr, 8 * rr + 8):
                    if d == 0: pat.append(p[c if c < 8 else c + 8])
                    elif d == 4: pat.append(p[c + 8 if c + 8 < 16 else c + 16])
                    else: pat.append(0xFF)
                ents.append((32 * rr + d, pat))
        out += grp(name, row, ents)
    out.append('p6_ff62:\tDB\t' + ','.join(f'0x{keep6(Z(0xFF62 + i)):02X}' for i in range(16)))
    out.append('p6_8d57:\tDB\t' + ','.join(f'0x{keep6(Z(0x8D57 + i)):02X}' for i in range(32)))   # кадры 0..3 (+5 оружия — 0..3)
    # (оружие CPC — cpc_weapon: $69CF, таблицы $72BF/$72C7 — владелец 15.11 вернул ZX: с 8 точками тормозило)
    return out

def plane_funcs():
    """16 routines: A = f(p0 = C, p1 = B) for every truth table f over the pen (bit p of f = value for pen p),
    (HL) = A; shortest sequences of 8080 operations (breadth-first search)"""
    ops = [('LD\tA,C', lambda a: 0b1010, 5), ('LD\tA,B', lambda a: 0b1100, 5), ('XOR\tA', lambda a: 0, 4),
           ('LD\tA,0xFF', lambda a: 0b1111, 7), ('CPL', lambda a: a ^ 15, 4), ('AND\tC', lambda a: a & 0b1010, 4),
           ('AND\tB', lambda a: a & 0b1100, 4), ('OR\tC', lambda a: a | 0b1010, 4), ('OR\tB', lambda a: a | 0b1100, 4),
           ('XOR\tC', lambda a: a ^ 0b1010, 4), ('XOR\tB', lambda a: a ^ 0b1100, 4)]
    best = {}
    frontier = [(0, None, [])]
    import heapq
    heap = [(0, 0, [], -1)]
    seen = {}
    # state: value of A (None at start); Dijkstra by cycles
    heap = [(0, -1, [])]
    while heap:
        c, a, seq = heapq.heappop(heap)
        if a in seen:
            continue
        seen[a] = (c, seq)
        for name, f, cy in ops:
            if a == -1 and name in ('CPL', 'AND\tC', 'AND\tB', 'OR\tC', 'OR\tB', 'XOR\tC', 'XOR\tB'):
                continue
            na = f(a)
            if na not in seen:
                heapq.heappush(heap, (c + cy, na, seq + [name]))
    out = ['; generated by tools/mkcpc.py: плоскость = f(перо): C = бит 0 пера, B = бит 1; (HL) = A',
           'plf_tab:\t' + 'DW\t' + ', '.join(f'plf{f}' for f in range(16))]
    for f in range(16):
        out.append(f'plf{f}:')
        out += ['\t\t\t' + x for x in seen[f][1]]
        out += ['\t\t\tLD\t(HL),A', '\t\t\tRET']
    open(os.path.join(ROOT, 'src/vec/gen/plfun.asm'), 'w').write('\n'.join(out) + '\n')


if __name__ == '__main__':
    plane_funcs()
    main()
