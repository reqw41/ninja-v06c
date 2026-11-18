#!/usr/bin/env python3
"""Room palettes as CPC (owner 14.11.2026): for every room, which CPC colour lies under each ZX colour.

  python3 -I tools/cpcpal.py   -> table + build/cpc/pal_votes.txt, preview build/cpc/rooms_recolor.png

ZX rooms: data/png/roomNN.png (256x168, ZX colours). CPC: tour screenshots build/cpcrun/tour (room t = shot
10 + t; play area x 64..703 = 40 tiles x 16 px, y from 37). ZX column c = CPC tile c + 4; ZX pixel x -> CPC
screenshot x = 64 + 2 * (x + 32). Votes skip the fighters' rows (ZX rows 104..167) for colours that occur above.
"""
import glob, os
from collections import Counter, defaultdict
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
ZXPAL = {(0, 0, 0): 0, (0, 0, 255): 1, (255, 0, 0): 2, (255, 0, 255): 3, (0, 255, 0): 4, (0, 255, 255): 5,
         (255, 255, 0): 6, (255, 255, 255): 7}


def vec_byte(rgb):
    lv = lambda v, top: 0 if v < 48 else (top // 2 if v < 160 else top)
    r, g, b = rgb
    return (lv(b, 3) << 6) | (lv(g, 7) << 3) | lv(r, 7)


def main():
    fs = sorted(glob.glob(os.path.join(ROOT, 'build/cpcrun/tour/snap/cpc6128/*.png')))
    res = {}
    out = []
    import geom15
    img = geom15.zx_img()
    attr = [img[0xE37E - 0x4000 + i] for i in range(256)]
    tg = {}
    for t in range(21):
        m40 = geom15.room40(img, t)
        at40 = geom15.attrs40(img, t, m40)
        cpc = Image.open(fs[10 + t]).convert('RGB')

        class ZX40:
            @staticmethod
            def getpixel(xy):
                x, y = xy
                C, R = x // 8, y // 8
                tl = m40[R][C]
                a = at40[R][C]
                g = geom15.tile_gfx(img, t, tl, y & 7)
                c = a & 7 if g & (0x80 >> (x & 7)) else (a >> 3) & 7
                return list(ZXPAL)[c]
        zx = ZX40
        res[t] = []
        for y0, y1 in ((0, 112), (112, 168)):      # верх (строки 0..13) и пол (14..20)
            votes = defaultdict(Counter)
            for y in range(y0, y1):
                for x in range(320):                # 40 тайлов по 8 точек ZX = CPC 40 x 16 точек снимка
                    zc = ZXPAL[zx.getpixel((x, y))]
                    cc = cpc.getpixel((64 + 2 * x, 37 + y))
                    votes[zc][cc] += 1
            pal = {}
            for zc in range(8):
                if votes[zc]:
                    (cc, n), = votes[zc].most_common(1)
                    pal[zc] = (cc, n / sum(votes[zc].values()))
            res[t].append(pal)
            out.append(f'{t:2d} {"верх" if y0 == 0 else "пол "} ' + ' '.join(f'{zc}:{pal[zc][0]}({pal[zc][1]:.2f})' for zc in sorted(pal)))
    open(os.path.join(ROOT, 'build/cpc/pal_votes.txt'), 'w').write('\n'.join(out) + '\n')
    print('\n'.join(out))
    return res


FIX = {(0, 0, 0): 0, (255, 96, 0): 2, (255, 96, 96): 3}     # бойцы: чёрный, оранжевый, телесный
FREE = [1, 4, 5, 6, 7]


def palettes(res):
    """per room: remap ZX colour -> palette index, palette RGB[8] (indices 0, 2, 3 fixed)"""
    out = {}
    for t, pals2 in res.items():
        rgb = [None] * 8
        for c, i in FIX.items():
            rgb[i] = c
        cols = Counter()
        for pal in pals2:
            for zc, (cc, q) in pal.items():
                cols[cc] += 1
        slots = list(FREE)
        idx_of = dict(FIX)
        for cc, _ in cols.most_common():
            if cc in idx_of:
                continue
            if slots:
                i = slots.pop(0); idx_of[cc] = i; rgb[i] = cc
            else:                                   # нет места — ближайший уже выбранный
                d = lambda a: sum((x - y) ** 2 for x, y in zip(a, cc))
                idx_of[cc] = min((i for i in range(8) if rgb[i]), key=lambda i: d(rgb[i]))
        remap = [[idx_of[pal[zc][0]] if zc in pal else 0 for zc in range(8)] for pal in pals2]
        for i in range(8):
            if rgb[i] is None:
                rgb[i] = (0, 0, 0)
        out[t] = (remap, rgb)
    return out


def preview(pals):
    from cpcspr import load_cpc, cpc_frame
    W = Image.new('RGB', (3 * 260, 7 * 172), (30, 30, 30))
    c = load_cpc()
    for t in range(21):
        remap, rgb = pals[t]
        zx = Image.open(os.path.join(ROOT, f'data/png/room{t:02d}.png')).convert('RGB')
        im = Image.new('RGB', (256, 168))
        for y in range(168):
            for x in range(256):
                im.putpixel((x, y), rgb[remap[0 if y < 112 else 1][ZXPAL[zx.getpixel((x, y))]]])
        # бойцы: герой (кадр 8) и враг (кадр 42) на полу
        PEN = {1: rgb[0], 2: rgb[2], 3: rgb[3]}
        for f, x0 in ((8, 60), (42, 160)):
            rows, _ = cpc_frame(c, f)
            for r, row in enumerate(rows):
                for cx, pen in enumerate(row):
                    if pen:
                        for k in (0, 1):
                            X, Y = x0 + 2 * cx + k, 168 - 48 - 4 + r
                            if 0 <= X < 256 and 0 <= Y < 168:
                                im.putpixel((X, Y), PEN[pen])
        W.paste(im, ((t % 3) * 260, (t // 3) * 172))
    W = W.resize((W.width * 2, W.height * 2), Image.NEAREST)
    W.save(os.path.join(ROOT, 'build/cpc/rooms_recolor.png'))


if __name__ == '__main__':
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    pals = palettes(main())
    for t in range(21):
        print(t, pals[t][0], [hex(vec_byte(c)) for c in pals[t][1]])
    preview(pals)
