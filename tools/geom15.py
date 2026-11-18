#!/usr/bin/env python3
"""Geometry x1.5 (owner 14.11.2026: room in the coordinates of the Atari/CPC original): the room is 40 tiles of
6 px = 240 px from x = 8 (margins 8 px). ZX pixel x (visible, 0..255) -> 32 + 0.75 x; ZX column X -> tile X + 4.

Library: full 40-column maps from the ZX room streams, 8 -> 6 px tiles (ZX pixels 0,1,3,4,6,7), CPC pixel -> 1.5 px
(new px n shows CPC pixel 2n // 3). Mock-up: python3 tools/geom15.py -> build/cpc/geom15_rooms.png.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
KEEP = (0, 1, 3, 4, 6, 7)


def zx_img():
    return open(os.path.join(ROOT, 'build/zx/ram4000.bin'), 'rb').read()


def stream40(img, p, cells, col, rows_out, row0, col_start_cell):
    """decode a ZX room stream ($F64C/$EB95) into a 40-column map: returns {(row, col40): tile}"""
    r = lambda a: img[a - 0x4000]
    out = {}
    cell = col_start_cell                 # visible cell counter -> row/col of visible part
    vis = 0
    # track position in 40-wide rows: column counter col (0..39), row advances when col wraps to 0
    row = row0
    while True:
        a = r(p); p += 1
        reps = 1
        if a == 0xFF:
            a, reps = r(p), r(p + 1) + 1; p += 2
        for _ in range(reps):
            col += 1
            if col >= 0x28:
                col = 0
                row += 1
            out[(row, col)] = a
            if 4 <= col < 0x24:
                vis += 1
                if vis == cells:
                    return out


def room40(img, t):
    """21 x 40 tile map of room t (stream rows 0..14, floor rows 14..20, walls at columns 0-3 / 36-39)"""
    r = lambda a: img[a - 0x4000]
    w = lambda a: r(a) | r(a + 1) << 8
    m = [[0] * 40 for _ in range(21)]
    # room stream: col counter starts at $27 (first column = 0 of row 0)
    s = stream40(img, w(0xD9DE + 2 * t), 480, 0x27, None, -1, 0)
    for (y, x), v in s.items():
        if 0 <= y < 21:
            m[y][x] = v
    f = stream40(img, 0x7808, 200, 0x1B, None, 14, 0)
    for (y, x), v in f.items():
        if 0 <= y < 21:
            m[y][x] = v
    nb = [r(0xD897 + 4 * t + k) for k in range(4)]
    for side, base, c0 in ((0, 0x8134, 0), (1, 0x8158, 36)):
        if not nb[side]:
            for yy in range(15):
                for k in range(4):
                    m[2 + yy][c0 + k] = r(base + 40 * yy + k)
    return m


def attrs40(img, t, m):
    """ZX attributes of the 40-column map as the game paints them: $E37E[tile] | $40 (tile $A0: $30 in room 1,
    else $28), recolour $EB68 (rows/address from the end of the list), rainbow of room 0, doors of rooms 19/20"""
    r = lambda a: img[a - 0x4000]
    w = lambda a: r(a) | r(a + 1) << 8
    attr = [r(0xE37E + i) for i in range(256)]
    attr[0xA0] = 0x30 if t == 1 else 0x28
    attr[0x25] = 0x2C if t in [r(0xF694 + k) for k in range(5)] else 0x2A   # $F800
    at = [[attr[x] | 0x40 for x in row] for row in m]
    ks = [k for k in range(6) if r(0xEB56 + k) == t]
    if ks:
        k = 5 - ks[0]
        r0 = (w(0xEB5C + 2 * k) - 0x5800) >> 5
        for y in range(r0, r0 + r(0xEB50 + k)):
            for x in range(40):
                if 0x68 <= at[y][x] < 0x70:
                    at[y][x] = (at[y][x] & 0xC7) | 8
    if t == 0:
        for y in range(4, 11):
            for x in range(40):
                at[y][x] = (at[y][x] & 0xC7) + 8 * (y - 3)
    if t in (19, 20):
        for y in range(5, 13):
            for x in range(16, 24):
                at[y][x] = 0x60 if t == 20 else 0x50
    return at


def tile_gfx(img, t, tl, y):
    """ZX tile row (tile $A0 = tile $9C, zero in room 1 — room_build)"""
    if tl == 0xA0:
        return 0 if t == 1 else img[0xD00C - 0x4000 + 8 * 0x9C + y]
    return img[0xD00C - 0x4000 + 8 * tl + y] if tl < 225 else 0


def tile6(img, t):
    rows = []
    for y in range(8):
        b = img[0xD00C - 0x4000 + 8 * t + y]
        v = 0
        for j, k in enumerate(KEEP):
            if b & (0x80 >> k):
                v |= 0x80 >> j
        rows.append(v)
    return rows


if __name__ == '__main__':
    from PIL import Image
    import cpcpal
    img = zx_img()
    pals = cpcpal.palettes(cpcpal.main())
    attr = [img[0xE37E - 0x4000 + t] for t in range(256)]
    W = Image.new('RGB', (3 * 264, 7 * 172), (30, 30, 30))
    for t in range(21):
        m = room40(img, t)
        at = attrs40(img, t, m)
        remap, rgb = pals[t]
        im = Image.new('RGB', (256, 168))
        for R in range(21):
            for C in range(40):
                tl = m[R][C]
                a = at[R][C]
                tab = remap[0 if R < 14 else 1]
                ink, paper = rgb[tab[a & 7]], rgb[tab[(a >> 3) & 7]]
                g = tile6(img, tl)
                for y in range(8):
                    for x in range(6):
                        im.putpixel((8 + 6 * C + x, 8 * R + y), ink if g[y] & (0x80 >> x) else paper)
        W.paste(im, ((t % 3) * 264, (t // 3) * 172))
    W = W.resize((W.width * 2, W.height * 2), Image.NEAREST)
    W.save(os.path.join(ROOT, 'build/cpc/geom15_rooms.png'))
    print('ok')
