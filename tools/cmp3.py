#!/usr/bin/env python3
"""Лист сравнения комнат: ZX (эталон) | Вектор (наш образ, тот же шаг) | CPC (модель комнаты из снимка памяти CPC).
Снимки ZX/Вектора — ROOMSHOT=build/cmp VECIMG=build/vec/ninja node tools/vecstep.js build/golden/g1_tour.jsonl.gz
  tools/.venv/bin/python tools/cmp3.py build/cmp docs/cmp/rooms_zx_vec_cpc.png [масштаб]"""
import os, sys
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpcroom, geom15

D, OUT = sys.argv[1], sys.argv[2]
S = int(sys.argv[3]) if len(sys.argv) > 3 else 1
ZXC = [(0, 0, 0), (0, 0, 0xD7), (0xD7, 0, 0), (0xD7, 0, 0xD7), (0, 0xD7, 0), (0, 0xD7, 0xD7), (0xD7, 0xD7, 0), (0xD7, 0xD7, 0xD7)]
ZXB = [(0, 0, 0), (0, 0, 0xFF), (0xFF, 0, 0), (0xFF, 0, 0xFF), (0, 0xFF, 0), (0, 0xFF, 0xFF), (0xFF, 0xFF, 0), (0xFF, 0xFF, 0xFF)]


def zx(room):
    m = open(f'{D}/zx{room}.bin', 'rb').read()
    im = Image.new('RGB', (256, 192))
    px = im.load()
    for y in range(192):
        a = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
        for c in range(32):
            b, at = m[a + c], m[0x1800 + (y >> 3) * 32 + c]
            pal = ZXB if at & 0x40 else ZXC
            ink, paper = pal[at & 7], pal[(at >> 3) & 7]
            for k in range(8):
                px[c * 8 + k, y] = ink if b >> (7 - k) & 1 else paper
    return im


def vec(room, y0=16, y1=240):
    m = open(f'{D}/vec{room}.bin', 'rb').read()
    pal = open(f'{D}/pal{room}.bin', 'rb').read()
    rgb = [((v & 7) * 255 // 7, ((v >> 3) & 7) * 255 // 7, ((v >> 6) & 3) * 255 // 3) for v in pal]
    im = Image.new('RGB', (256, y1 - y0))
    px = im.load()
    for y in range(y0, y1):
        lo = 255 - y
        for c in range(32):
            a, cc, e = (m[(p * 0x20 + c) << 8 | lo] for p in range(3))
            for k in range(8):
                i = (a >> (7 - k) & 1) << 2 | (cc >> (7 - k) & 1) << 1 | (e >> (7 - k) & 1)
                px[c * 8 + k, y - y0] = rgb[i]
    return im


d = cpcroom.ram()
img = geom15.zx_img()
inks = [cpcroom.HW.get(d[0x7C54 + i] & 0x1F, (255, 0, 255)) for i in range(16)]


def cpc(t):
    P = cpcroom.pens(cpcroom.screen_bytes(d, img, t))
    im = Image.new('RGB', (320, 168))
    px = im.load()
    for y in range(168):
        for x in range(160):
            px[2 * x, y] = px[2 * x + 1, y] = inks[P[y][x]]
    return im


rooms = sorted(int(f[2:-4]) for f in os.listdir(D) if f.startswith('zx') and f.endswith('.bin'))
W, H, G, T = 256 + 256 + 320 + 2 * 8, 224, 8, 14
sheet = Image.new('RGB', ((W) * S, (len(rooms) * (H + T) + T) * S), (40, 40, 40))
dr = ImageDraw.Draw(sheet)
FONT = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 11 * S)
for i, h in enumerate(('ZX (эталон)', 'Вектор (наш)', 'CPC (комната)')):
    dr.text(((i * (256 + G)) * S + 4, 1 * S), h, fill=(255, 255, 255), font=FONT)
for j, r in enumerate(rooms):
    y = (T + j * (H + T)) * S
    dr.text((4, y + 1 * S), f'комната {r}  ' + open(f'{D}/room{r}.txt').read().split(',')[0], fill=(255, 255, 160), font=FONT)
    for k, (pic, x) in enumerate(((zx(r), 0), (vec(r), 256 + G), (cpc(r), 2 * (256 + G)))):
        sheet.paste(pic.resize((pic.width * S, pic.height * S), Image.NEAREST), (x * S, y + T * S))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
sheet.save(OUT)
print(OUT, sheet.size)
