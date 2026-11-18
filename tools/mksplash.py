#!/usr/bin/env python3
"""Образ ROM Ninja со стартовой заставкой (владелец 15.11.2026): картинка orig/splash/ninja_splash.png (256x256,
8 цветов — каждый цвет свой номер палитры), как в brucelee-v06c.

    python3 -I tools/mksplash.py      -> rom/Ninja-v06c.r0m, rom/Ninja-v06c.c00 (64 КБ с 0x0000), превью

Раскладка (src/vec/splash.asm): 0000 код заставки; 0100.. игра build/vec/ninja.bin (0000..9FFF) в ZX0 (classic);
8000..FFFF — картинка (плоскости 8000 бит 3, A000 бит 2, C000 бит 1, E000 бит 0; номера 0..7 — без плоскости 8000).
После клавиши (или огня джойстика «П») палитра гаснет, игра распаковывается в 0000..9FFF и запускается с 0000.
"""
import os, subprocess
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
B = os.path.join(ROOT, 'build/vec/splash'); os.makedirs(B, exist_ok=True)
img = Image.open(os.path.join(ROOT, 'orig/splash/ninja_splash.png')).convert('RGB')
assert img.size == (256, 256)
cnt = {}
for c in img.getdata():
    cnt[c] = cnt.get(c, 0) + 1
cols = sorted(cnt, key=lambda c: -cnt[c])
assert len(cols) <= 8, f'цветов {len(cols)}'
if (0, 0, 0) in cols:
    cols.remove((0, 0, 0))
cols = [(0, 0, 0)] + cols                       # номер 0 — чёрный: и бордюр (порт 02 = 0)


def vb(c):                                      # RGB -> %BBGGGRRR
    r, g, b = c
    return (round(b * 3 / 255) << 6) | (round(g * 7 / 255) << 3) | round(r * 7 / 255)


idx = {c: i for i, c in enumerate(cols)}
planes = bytearray(0x8000)
for y in range(256):
    for x in range(256):
        i = idx[img.getpixel((x, y))]
        for p, bit in enumerate((8, 4, 2, 1)):
            if i & bit:
                planes[p * 0x2000 + (x >> 3) * 256 + 255 - y] |= 0x80 >> (x & 7)
pal = [vb(c) for c in cols] + [0] * (8 - len(cols))
pal = pal + pal                                 # номера i и i + 8 одинаковы
open(os.path.join(B, 'screen.bin'), 'wb').write(planes)
open(os.path.join(B, 'palette.bin'), 'wb').write(bytes(pal))
prev = Image.new('RGB', (256, 256))
def rgb(v): return ((v & 7) * 255 // 7, ((v >> 3) & 7) * 255 // 7, ((v >> 6) & 3) * 255 // 3)
for y in range(256):
    for x in range(256):
        prev.putpixel((x, y), rgb(pal[idx[img.getpixel((x, y))]]))
prev.save(os.path.join(ROOT, 'build/vec/splash_preview.png'))
# стартовый экран (владелец 18.11: «стартовый экран с названием игры, копирайтами, описанием управления»): после
# заставки, до игры; шрифт игры (CPC: пробел, цифры, заглавные) + свои знаки; 8 цветов, плоскости A000/C000/E000
import re
FONT = {}
for l in open(os.path.join(ROOT, 'src/vec/gen/font.asm')):
    mm = re.match(r"\s*DB\s+([0-9A-Fx,]+)\s*;\s*'(.)'", l)
    if mm:
        FONT[mm.group(2)] = [int(v, 16) for v in mm.group(1).split(',')]
OWN = {'(': [0x0C, 0x18, 0x30, 0x30, 0x30, 0x18, 0x0C, 0], ')': [0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x18, 0x30, 0],
       '-': [0, 0, 0, 0x7C, 0x7C, 0, 0, 0], ':': [0, 0x30, 0x30, 0, 0x30, 0x30, 0, 0], '.': [0, 0, 0, 0, 0, 0x30, 0x30, 0],
       '/': [0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0x80, 0], ',': [0, 0, 0, 0, 0, 0x30, 0x30, 0x60],
       'П': [0xFE, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0], 'У': [0xC6, 0xC6, 0xC6, 0x7E, 0x06, 0xC6, 0x7C, 0],
       'В': FONT.get('B'), 'К': FONT.get('K'), 'А': FONT.get('A'), 'Р': FONT.get('P'), 'С': FONT.get('C')}
FONT.update(OWN)
IPAL = [(0, 0, 0), (255, 109, 0), (255, 255, 0), (182, 182, 170), (255, 255, 255), (219, 0, 0), (0, 0, 0), (0, 0, 0)]
info = [[0] * 256 for _ in range(256)]
def text(x, y, s, col, sc=1):
    for i, ch in enumerate(s):
        g = FONT.get(ch) or [0] * 8
        for r in range(8):
            for b in range(8):
                if g[r] & (0x80 >> b):
                    for dy in range(sc):
                        for dx in range(sc):
                            info[y + r * sc + dy][x + (i * 8 + b) * sc + dx] = col
def centre(y, s, col, sc=1):
    text((256 - len(s) * 8 * sc) // 2, y, s, col, sc)
centre(16, 'NINJA', 1, 3)
centre(48, '(C) 1986 ENTERTAINMENT USA', 2)
centre(60, 'BY STEVE COLEMAN', 2)
centre(72, 'VECTOR-06C VERSION 2026', 2)
centre(108, 'CONTROLS', 1)
rows = [('ARROWS', 'MOVE'), ('SPACE', 'FIRE'), ('JOYSTICK П', 'MOVE, FIRE'), ('ВК', 'PAUSE'), ('АР2', 'QUIT'),
        ('УС', 'SOUND ON/OFF')]
for k, (a, b) in enumerate(rows):
    text(24, 124 + 12 * k, a, 4)
    text(24 + 8 * 13, 124 + 12 * k, b, 3)
centre(208, 'PRESS FIRE', 2)
iplanes = bytearray(0x6000)                     # A000 (бит 2), C000 (бит 1), E000 (бит 0)
for y in range(256):
    for x in range(256):
        i = info[y][x]
        for p, bit in enumerate((4, 2, 1)):
            if i & bit:
                iplanes[p * 0x2000 + (x >> 3) * 256 + 255 - y] |= 0x80 >> (x & 7)
open(os.path.join(B, 'info.raw'), 'wb').write(iplanes)
subprocess.run([os.path.join(ROOT, 'tools/zx0/zx0'), '-f', '-c', os.path.join(B, 'info.raw'), os.path.join(B, 'info.zx0')],
               check=True, capture_output=True)
ipal = [vb(c) for c in IPAL]; ipal = ipal + ipal
open(os.path.join(B, 'ipal.bin'), 'wb').write(bytes(ipal))
iprev = Image.new('RGB', (256, 256))
for y in range(256):
    for x in range(256):
        iprev.putpixel((x, y), rgb(ipal[info[y][x]]))
iprev.save(os.path.join(ROOT, 'build/vec/info_preview.png'))
TSKIP = None
for l in open(os.path.join(ROOT, 'build/vec/ninja.sym'), encoding='latin1'):
    mm = re.match(r'^t_skip:\s+EQU\s+0x([0-9A-F]+)', l)
    if mm:
        TSKIP = int(mm.group(1), 16)
assert TSKIP is not None, 't_skip нет в ninja.sym'
open(os.path.join(B, 'tskip.inc'), 'w').write(f'TSKIP\tEQU\t0x{TSKIP:04X}\n')
game = open(os.path.join(ROOT, 'build/vec/ninja.bin'), 'rb').read()
assert len(game) == 0xA000
open(os.path.join(B, 'game.raw'), 'wb').write(game)
subprocess.run([os.path.join(ROOT, 'tools/zx0/zx0'), '-f', '-c', os.path.join(B, 'game.raw'), os.path.join(B, 'game.zx0')],
               check=True, capture_output=True)
n = os.path.getsize(os.path.join(B, 'game.zx0'))
r = subprocess.run([os.path.join(ROOT, 'tools/sjasmplus'), '--nologo', '--i8080', '--sym=' + os.path.join(B, 'splash.sym'),
                    '-I' + B, os.path.join(ROOT, 'src/vec/splash.asm')], cwd=B, capture_output=True, text=True)
if r.returncode:
    print(r.stdout, r.stderr); raise SystemExit(1)
rom = open(os.path.join(B, 'splash.rom'), 'rb').read()
assert len(rom) == 0x10000
os.makedirs(os.path.join(ROOT, 'rom'), exist_ok=True)
for ext in ('r0m', 'c00'):
    open(os.path.join(ROOT, 'rom/Ninja-v06c.' + ext), 'wb').write(rom)
print(f'цветов заставки {len(cols)}, игра {len(game)} -> {n} Б (ZX0), rom/Ninja-v06c.r0m / .c00')
