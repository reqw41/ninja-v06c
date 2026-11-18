#!/usr/bin/env python3
"""Лист кадров ходьбы героя: CPC (сетка — тайл CPC 4 точки x 8 строк) и Вектор x0.75 (сетка — байт экрана 8 x 8),
начало — левый край рамки кадра ZX.  tools/.venv/bin/python -I tools/walksheet.py -> docs/cpc/walk_cpc_vs_vec.png"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw
from cpcspr import load_cpc, cpc_frame, align, walk_dx

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
c = load_cpc()
wdx = walk_dx(c)
s = open(os.path.join(ROOT, 'src/vec/gen/cpc.asm')).read()
data, cur = {}, None
for line in s.split('\n'):
    m = re.match(r'(cpc_c\d+_\d+):', line)
    if m:
        cur = m.group(1); data[cur] = []; continue
    if cur and line.strip().startswith('DB'):
        data[cur] += [int(x, 16) for x in line.split('DB')[1].split(',')]
    elif cur:
        cur = None
fr = {int(f): (h, cols) for f, h, cols in re.findall(r'cpc_f(\d+):[^\n]*\n\t\t\tDB\t([^\n]+)\n((?:\t\t\tDW\t[^\n]+\n\t\t\tDB\t[^\n]+\n)+)', s)}
pal = {1: (0, 0, 0), 2: (255, 128, 0), 3: (255, 128, 128)}
BG, GRID = (110, 110, 100), (70, 170, 255)
frames = [int(x) for x in (sys.argv[1].split(',') if len(sys.argv) > 1 else '9,10,11,12,13,14'.split(','))]
SC, TW, TH = 5, 56, 56
W, H = len(frames) * TW * SC, 2 * (TH * SC + 40)
im = Image.new('RGB', (W, H), (40, 40, 40)); dr = ImageDraw.Draw(im)


def panel(t, x0, y0):
    big = t.resize((TW * SC, TH * SC), Image.NEAREST); d = ImageDraw.Draw(big)
    for g in range(0, TW + 1, 8):
        d.line([(g * SC, 0), (g * SC, TH * SC)], fill=GRID)
        d.line([(0, g * SC), (TW * SC, g * SC)], fill=GRID)
    im.paste(big, (x0, y0))


dr.text((6, 4), 'CPC: grid = CPC tile 4 px x 8 rows (CPC px = 2 units); origin = left edge of the ZX frame box', fill=(255, 255, 255))
dr.text((6, TH * SC + 44), 'Vector x0.75: grid = screen byte 8 x 8; origin = left edge of the ZX frame box', fill=(255, 255, 255))
for i, f in enumerate(frames):
    x0 = i * TW * SC
    rows, _ = cpc_frame(c, f)
    dx, dy, q = align(f, c)
    dx = wdx.get(f, dx)
    ys = [y for y, r in enumerate(rows) if any(r)]
    hl = 2 * min(x for y in ys[:2] for x, p in enumerate(rows[y]) if p)
    dx = int(round((dx + hl) / 4.0)) * 4 - hl
    t = Image.new('RGB', (TW, TH), BG)
    for y, r in enumerate(rows):
        for x, p in enumerate(r):
            X = int(round(2 * x + dx)) + 12
            if p and 0 <= X < TW - 1 and 0 <= y + dy < TH:
                t.putpixel((X, y + dy), pal[p]); t.putpixel((X + 1, y + dy), pal[p])
    panel(t, x0, 18); dr.text((x0 + 4, 20 + TH * SC), f'frame {f}', fill=(255, 255, 0))
    h, cols = fr[f]
    ox = int(h.split(',')[0]); ox = ox - 256 if ox > 127 else ox
    top = int(h.split(',')[2]); top = top - 256 if top > 127 else top
    t = Image.new('RGB', (TW, TH), BG)
    for j, (p, r0, n) in enumerate(re.findall(r'DW\t(\S+)\n\t\t\tDB\t(\d+),(\d+)', cols)):
        if p == '0':
            continue
        d = data[p]
        for r in range(int(n)):
            p0, p1 = d[2 * r], d[2 * r + 1]
            for b in range(8):
                v = ((p0 >> (7 - b)) & 1) | (((p1 >> (7 - b)) & 1) << 1)
                X, Y = 8 * j + b + ox + 8, int(r0) + r + top
                if v and 0 <= X < TW and 0 <= Y < TH:
                    t.putpixel((X, Y), pal[v])
    panel(t, x0, TH * SC + 58); dr.text((x0 + 4, TH * SC + 60 + TH * SC), f'frame {f}  ox={ox}', fill=(255, 255, 0))
out = os.environ.get('OUT', 'docs/cpc/walk_cpc_vs_vec.png'); im.save(os.path.join(ROOT, out))
print(out)
