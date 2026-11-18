#!/usr/bin/env python3
"""CPC Ninja fighters for the Vector (owner 14.11.2026: CPC frames as they are, colours as CPC).

Library + report: python3 -I tools/cpcspr.py  -> alignment of the 48 CPC frames (+4 composites) to the 50 ZX
frames. CPC (NINJA3.BIN at $0040, orig/ CPC disk, not in git): frame table $79D1 (48 words), frame = 48 rows,
row = RLE bytes until 0: high nibble = count of bytes, low nibble = two mode-0 pixels (pen of the left pixel
= bits 3..2, right = bits 1..0; pens 1 black, 2 orange, 3 salmon; 0 transparent). Composite frames ($7DC1, 4
entries): 24 rows from the first pointer + 24 rows from the second. ZX frame f -> CPC frame f (f < 34),
f + 2 (34..45), composite 49 - f (46..49).
"""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
CPC_BIN = os.path.join(ROOT, 'build/cpc/Ninja__UK___1987___Version_MT0015_/NINJA3.BIN.body')


def load_cpc():
    c = bytearray(0x10000)
    d = open(CPC_BIN, 'rb').read()
    c[0x40:0x40 + len(d)] = d
    return c


def rows_at(c, p, n):
    """n RLE rows from p -> list of pen lists (CPC pixels), and the pointer after them."""
    out = []
    for _ in range(n):
        row = []
        while True:
            b = c[p]; p += 1
            if b == 0:
                break
            for _ in range(b >> 4):
                row += [(b >> 2) & 3, b & 3]
        out.append(row)
    return out, p


ATARI_FRAMES = os.path.join(ROOT, 'data/atari/frames.bin')   # кадры Atari ($5300, 48 x 240 Б: 48 строк x 5 байт, 2 бита)
ATARI_ZX = (16,)        # у CPC кадр 16 собран неверно (кусок головы отдельно), у Atari — как у ZX (владелец 15.11)


def atari_rows(k):
    """кадр Atari k в строках CPC (строка Atari r = строка CPC r + 1), точки — коды 0..3 = перья CPC"""
    a = open(ATARI_FRAMES, 'rb').read()[240 * k:240 * k + 240]
    rows = [[]]
    for r in range(47):
        rows.append([(a[r * 5 + x // 4] >> (6 - 2 * (x % 4))) & 3 for x in range(20)])
    return rows


def cpc_frame(c, zf):
    if zf in ATARI_ZX and os.path.exists(ATARI_FRAMES):
        return atari_rows(zf), []
    w = lambda a: c[a] | c[a + 1] << 8
    if zf < 34 or zf <= 45:
        k = zf if zf < 34 else zf + 2
        rows, _ = rows_at(c, w(0x79D1 + 2 * k), 48)
        return rows, [(w(0x79D1 + 2 * k), 48)]
    n = 49 - zf
    p1, p2 = w(0x7DC1 + 4 * n), w(0x7DC3 + 4 * n)
    r1, _ = rows_at(c, p1, 24)
    r2, _ = rows_at(c, p2, 24)
    return r1 + r2, [(p1, 24), (p2, 24)]


def zx_frame(f):
    z = open(os.path.join(ROOT, 'build/zx/ram4000.bin'), 'rb').read()
    Z = lambda a: z[a - 0x4000]
    p = Z(0xDA0C + 2 * f) | Z(0xDA0D + 2 * f) << 8
    h, w = Z(p), Z(p + 1)
    spr = [[(Z(p + 2 + y * w + x // 8) >> (7 - x % 8)) & 1 for x in range(8 * w)] for y in range(h)]
    msk = [[(Z(p + 2 + 0x2140 + y * w + x // 8) >> (7 - x % 8)) & 1 for x in range(8 * w)] for y in range(h)]
    return h, w, spr, msk


def align(f, c):
    """best (dx, dy): CPC pixel (cx, r) -> Vector pixel (2cx + dx, r + dy) in the ZX frame box (top = row 0)."""
    h, w, spr, msk = zx_frame(f)
    rows, _ = cpc_frame(c, f)
    zset = {(x, y) for y in range(h) for x in range(8 * w) if spr[y][x] or not msk[y][x]}
    cset = [(2 * cx + k, r) for r, row in enumerate(rows) for cx, pen in enumerate(row) if pen for k in (0, 1)]
    best = None
    for dy in range(h - 48 - 6, h - 48 + 7):
        for dx in range(-16, 17):
            s = sum(1 for x, y in cset if (x + dx, y + dy) in zset)
            if best is None or s > best[0]:
                best = (s, dx, dy)
    return best[1], best[2], best[0] / max(1, len(zset))


if __name__ == '__main__':
    c = load_cpc()
    for f in range(50):
        dx, dy, q = align(f, c)
        h, w, _, _ = zx_frame(f)
        print(f'{f:2d} zx {h}x{w} dx {dx:3d} dy {dy:3d} (низ {dy + 48 - h:+d}) совпадение {q:.2f}')


WALK_GROUPS = [(9, 10, 11), (12, 13, 14), (42, 43, 44), (32, 48, 49)]


def head_cpc(rows):
    ys = [y for y, r in enumerate(rows) if any(r)]
    xs = [2 * x + 0.5 for y in range(ys[0], ys[0] + 8) for x, p in enumerate(rows[y]) if p]
    return sum(xs) / len(xs)


def head_zx(f):
    h, w, spr, msk = zx_frame(f)
    pts = [(x, y) for y in range(h) for x in range(8 * w) if spr[y][x] or not msk[y][x]]
    y0 = min(y for x, y in pts)
    xs = [x for x, y in pts if y < y0 + 8]
    return sum(xs) / len(xs)


def walk_dx(c):
    """циклы ходьбы (владелец 15.11: без дёрганья): голова на одном месте во всех кадрах цикла — в среднем там же,
    где голова ZX; у ZX голова в кадрах цикла гуляет (8 -> 15 -> 20 точек), у CPC стоит"""
    out = {}
    for g in WALK_GROUPS:
        heads = {f: head_cpc(cpc_frame(c, f)[0]) for f in g}
        C = sum(head_zx(f) for f in g) / len(g)
        for f in g:
            out[f] = C - heads[f] + WALK_ADJ.get(f, 0)
    return out


# опорная нога не скользит (владелец 15.11: «ходьбу естественнее»): при раскрытии ног стоит задняя ступня, при
# сведении — передняя; сетка 4 точки ZX = 3 Вектора; подбор — скольжение 0, 3, 3, 0 точек, тело 3-6-6-9 за шаг
WALK_ADJ = {}                                  # владелец 15.11: ровные 6 точек на шаг (опорная нога была 3-6-6-9)
