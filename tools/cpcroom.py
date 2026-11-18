#!/usr/bin/env python3
"""CPC room pictures (owner 15.11.2026: «графику комнат и раскраску полностью с CPC»). From a CPC RAM dump
(build/cpcrun/dump/ram.bin, MAME): tiles $4721 (16 bytes = 8 rows x 2 bytes, 4 mode-0 pixels, pens 0..3 as stored),
the rooms are the ZX streams (same tile numbers, tools/geom15.room40), then the per-room recolour list $7A31[room]:
entries (line index c: line 199 - c, b lines down, pen 'from' -> 'to' as left-pixel bit patterns), 0 ends.
Inks: $7C54..$7C63 (hardware colours of pens 0..15).

  tools/.venv/bin/python -I tools/cpcroom.py   -> build/cpc/cpcrooms.png (+ check against the dumped screen)
"""
import os, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geom15

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
HW = {0x14: (0, 0, 0), 0x04: (0, 0, 0x80), 0x15: (0, 0, 0xFF), 0x1C: (0x80, 0, 0), 0x18: (0x80, 0, 0x80),
      0x1D: (0x80, 0, 0xFF), 0x0C: (0xFF, 0, 0), 0x05: (0xFF, 0, 0x80), 0x0D: (0xFF, 0, 0xFF), 0x16: (0, 0x80, 0),
      0x06: (0, 0x80, 0x80), 0x17: (0, 0x80, 0xFF), 0x1E: (0x80, 0x80, 0), 0x00: (0x80, 0x80, 0x80),
      0x1F: (0x80, 0x80, 0xFF), 0x0E: (0xFF, 0x80, 0), 0x07: (0xFF, 0x80, 0x80), 0x0F: (0xFF, 0x80, 0xFF),
      0x12: (0, 0xFF, 0), 0x02: (0, 0xFF, 0x80), 0x13: (0, 0xFF, 0xFF), 0x1A: (0x80, 0xFF, 0), 0x19: (0x80, 0xFF, 0x80),
      0x1B: (0x80, 0xFF, 0xFF), 0x0A: (0xFF, 0xFF, 0), 0x03: (0xFF, 0xFF, 0x80), 0x0B: (0xFF, 0xFF, 0xFF),
      0x01: (0x80, 0x80, 0x80), 0x08: (0xFF, 0, 0x80), 0x09: (0, 0x80, 0), 0x10: (0xFF, 0x80, 0), 0x11: (0, 0, 0x80)}


def ram():
    return open(os.path.join(ROOT, 'build/cpcrun/dump/ram.bin'), 'rb').read()


def pen_of(byte, right):
    if right:
        byte <<= 1
    return (byte >> 7 & 1) | (byte >> 2 & 2) | (byte >> 3 & 4) << 0 | (byte << 2 & 8)


def lpix(byte):
    return (byte >> 7 & 1) | (byte >> 2 & 2) | (byte >> 3 & 4) | (byte << 2 & 8)


def screen_bytes(d, img, t):
    """room t drawn as the CPC does: 200 x 80 screen bytes (rows 0..167 = room)"""
    m = geom15.room40(img, t)
    scr = [[0] * 80 for _ in range(200)]
    for R in range(21):
        for C in range(40):
            tl = m[R][C]
            if tl == 0xA0 and t != 1:        # логика: $A0 = $9C, в комнате 1 — перо 2 (так в снимке памяти)
                tl = 0x9C
            a = 0x4721 + 16 * tl
            for k in range(8):
                scr[8 * R + k][2 * C] = d[a + 2 * k]
                scr[8 * R + k][2 * C + 1] = d[a + 2 * k + 1]
    w = lambda a: d[a] | d[a + 1] << 8
    p = w(0x7A31 + 2 * t)
    while d[p]:
        c, b, fr, to = d[p], d[p + 1], d[p + 2], d[p + 3]
        p += 4
        for i in range(b):
            y = 199 - c + i
            if not 0 <= y < 200:
                continue
            row = scr[y]
            for x in range(80):
                v = row[x]
                if v & 0xAA == fr:
                    v = (v & 0x55) | to
                if v & 0x55 == fr >> 1:
                    v = (v & 0xAA) | to >> 1
                row[x] = v
    return scr


def pens(scr):
    """200 x 160 pens"""
    out = []
    for row in scr:
        r = []
        for v in row:
            r += [lpix(v), lpix((v << 1) & 0xFF)]
        out.append(r)
    return out


if __name__ == '__main__':
    from PIL import Image
    d = ram()
    img = geom15.zx_img()
    inks = [HW.get(d[0x7C54 + i] & 0x1F, (255, 0, 255)) for i in range(16)]
    print('inks', [hex(d[0x7C54 + i]) for i in range(16)])
    s = screen_bytes(d, img, 0)
    la = lambda y: 0xC000 + (y % 8) * 0x800 + (y // 8) * 80
    bad = sum(1 for y in range(168) for x in range(80) if s[y][x] != d[la(y) + x])
    print('room 0: bytes differing from the dumped screen', bad, 'of', 168 * 80)
    W = Image.new('RGB', (3 * 330, 7 * 176), (30, 30, 30))
    used = []
    for t in range(21):
        P = pens(screen_bytes(d, img, t))
        im = Image.new('RGB', (320, 168))
        for y in range(168):
            for x in range(160):
                for k in (0, 1):
                    im.putpixel((2 * x + k, y), inks[P[y][x]])
        used.append(sorted({P[y][x] for y in range(168) for x in range(160)}))
        W.paste(im, ((t % 3) * 330, (t // 3) * 176))
    for t in range(21):
        print(t, len(used[t]), used[t])
    W.save(os.path.join(ROOT, 'build/cpc/cpcrooms.png'))


# диагонали пола (владелец 17.11: «выровняем оранжевые линии, ступенчатые стали»): x1.5 даёт куски по 2 и 1 точке;
# свои тайлы — линия в 1 точку пером 2, наклон прежний (6 точек на 8 строк, шаг 1,1,1,0 по строкам); 12/13 — с линией
# внизу. Точка x (0..5) строки k; то же — pen4 в tools/vecstep.js
DIAG7 = (5, 4, 3, 3, 2, 1, 0, 0)
DIAG = {7: DIAG7, 8: tuple(5 - x for x in DIAG7), 12: DIAG7, 13: tuple(5 - x for x in DIAG7)}


def diag_pen(t, k, n):
    """pen of point n (0..5) of row k of tile t, None if not a floor diagonal"""
    if t not in DIAG:
        return None
    return 2 if n == DIAG[t][k] or (k == 7 and t in (12, 13)) else 0


def tile_planes(d):
    """225 tiles x 8 rows, x1.5 (new pixel n shows CPC pixel 2n // 3): plane A = pen bit 0, B = pen bit 1 (bits 7..2)"""
    A, B = [], []
    for t in range(225):
        for k in range(8):
            if t in DIAG:
                b = sum(0x80 >> n for n in range(6) if diag_pen(t, k, n))
                A.append(0); B.append(b)
                continue
            v0, v1 = d[0x4721 + 16 * t + 2 * k], d[0x4721 + 16 * t + 2 * k + 1]
            px = [lpix(v0), lpix((v0 << 1) & 0xFF), lpix(v1), lpix((v1 << 1) & 0xFF)]
            a = b = 0
            for n in range(6):
                p = px[2 * n // 3] & 3
                if p & 1: a |= 0x80 >> n
                if p & 2: b |= 0x80 >> n
            A.append(a); B.append(b)
    return A, B


def row_maps(d, t):
    """per row 0..167: stored pen 0..3 -> final pen 0..15 (recolour list of the room)"""
    w = lambda a: d[a] | d[a + 1] << 8
    maps = [list(range(16)) for _ in range(200)]
    p = w(0x7A31 + 2 * t)
    while d[p]:
        c, b, fr, to = d[p], d[p + 1], d[p + 2], d[p + 3]
        p += 4
        f, tt = lpix(fr), lpix(to)
        for i in range(b):
            y = 199 - c + i
            if 0 <= y < 200:
                maps[y] = [tt if v == f else v for v in maps[y]]
    return [m[:4] for m in maps[:168]]


FIXHW = {0x14: 0, 0x0E: 2, 0x07: 3}
BAND_Y = 112                              # полоса пола (строки Вектора i < 80, BAND_I)
LOST = {}                                 # комната -> [(цвет, чем заменён, точек)]
YELLOW = (255, 255, 0)                    # идол (жёлтый, как CPC)
# комнаты без свободного номера 4..7: какой номер отдать жёлтому и куда его цвет (владелец 15.11: «в комнате с
# пагодой самый верхний цвет сделать серым как пол, остальные потом подкорректируем»)
# владелец 18.11: горы комнаты 3 — зелёные; номер отдаёт тёмно-красная крыша ворот (-> малиновый столбов)
MERGE = {3: {0x1C: 0x0C}}
FORCE = {}                   # было {2: {0x1F: 1}} — пагода: верхний сиреневый -> серый (владелец 15.11), красные остаются


def room_colours(d, t, img):
    """palette rgb[8], pen -> index (16), runs [(row, idx of stored pens 0..3)]"""
    maps = row_maps(d, t)
    m = geom15.room40(img, t)
    used = Counter()
    P = pens(screen_bytes(d, img, t))
    for y in range(168):
        for x in range(160):
            used[d[0x7C54 + P[y][x]] & 0x1F] += 1
    hw_idx = dict(FIXHW)
    slots = [1, 4, 5, 6, 7]
    # владелец 15.11: «отсортировать цвета, чтобы вывод при ходьбе работал в 2 плоскости» — пол (самый частый цвет
    # строк 112..167, кроме цветов бойцов) — на номер 1: там все цвета 0..3, плоскость A000 фона пуста
    low = Counter(d[0x7C54 + P[y][x]] & 0x1F for y in range(112, 168) for x in range(160))
    fl = next((h for h, _ in low.most_common() if h not in FIXHW), None)
    rgb = [None] * 8
    if fl is not None:
        hw_idx[fl] = 1; slots.remove(1); rgb[1] = HW[fl]
    # владелец 16.11 (вариант Б): в полосе пола (строки 112..167) только серый пол в C000/E000 — линии пола (перо
    # тайла 2) уходят в A000 номером 5 = A | серый; под бойцом в полосе A000 не трогается (2 плоскости)
    band = Counter(d[0x7C54 + P[y][x]] & 0x1F for y in range(BAND_Y, 168) for x in range(160))
    lh = next((h for h, _ in band.most_common() if h != fl and h != 0x14), None)
    # владелец 18.11 («цвета комнат точнее, как CPC»): линия пола оранжевая (= номер 2 бойцов) -> номер 5 не нужен,
    # он свободен под цвет комнаты; линия и силуэт идола — сразу номер 2 (в C000, полоса пола без A000)
    ln = 2 if lh is not None and hw_idx.get(lh) == 2 else 5
    if lh is not None and ln == 5:
        slots.remove(5); rgb[5] = HW[lh]
    for h, i in FIXHW.items():
        rgb[i] = HW[h]
    for h, i in FORCE.get(t, {}).items():   # ручные решения владельца: цвет -> номер
        if h in used:
            hw_idx[h] = i
    for h, _ in used.most_common():
        if h in hw_idx:
            continue
        if MERGE.get(t, {}).get(h) in hw_idx:       # ручное слияние владельца: цвет -> номер другого цвета
            hw_idx[h] = hw_idx[MERGE[t][h]]
            continue
        same = [i for i in range(8) if rgb[i] == HW[h]]   # другой код CPC того же цвета — тот же номер
        if same:
            hw_idx[h] = same[0]
        elif slots:
            i = slots.pop(0); hw_idx[h] = i; rgb[i] = HW[h]
        else:
            dist = lambda i: sum((a - b) ** 2 for a, b in zip(rgb[i], HW[h]))
            hw_idx[h] = min((i for i in range(8) if rgb[i]), key=dist)
    # идол (владелец 15.11: «как в CPC, жёлтый с чёрным узором; выделим ему цвета с 4 по 7 в зависимости от ситуации»):
    # свободный номер 4..7, иначе самый редкий цвет фона уходит в ближайший; в строках идола (152..159) перо 3 -> он
    # идол (владелец 16.11: «оптимальными цветами, без мигания, чтобы не пересекаться со спрайтами»): силуэт — перо 3
    # -> номер 5 (A000 | серый, цвет линий пола), узор — чёрный (перо 1, C/E); жёлтый номер не нужен
    ys = ln if t != 20 and lh is not None else None
    rgb = [c or (0, 0, 0) for c in rgb]
    lost = [h for h in used if h not in (fl, lh) and h not in FIXHW and rgb[hw_idx[h]] != HW[h]]
    LOST[t] = [(HW[h], rgb[hw_idx[h]], used[h]) for h in lost]
    pen_idx = [hw_idx.get(d[0x7C54 + p] & 0x1F, 0) for p in range(16)]
    runs = []
    for y in range(168):
        idx = tuple(pen_idx[q] for q in maps[y])
        if not runs or runs[-1][1] != idx:
            runs.append((y, idx))
    if lh is not None:                      # полоса пола: перо тайла 2 -> 5 (разрезать полосу на строке BAND_Y)
        k = max(i for i, (y0, _) in enumerate(runs) if y0 <= BAND_Y)
        if runs[k][0] < BAND_Y:
            runs.insert(k + 1, (BAND_Y, runs[k][1]))
        for i in range(len(runs)):
            if runs[i][0] >= BAND_Y:
                idx = list(runs[i][1])
                assert idx[2] != 1 and idx[0] == 1, (t, 'пол', runs[i])
                idx[2] = ln
                runs[i] = (runs[i][0], tuple(idx))
    if ys is not None:                      # полоса строк с идолом (152..159): перо 3 -> жёлтый на всю её высоту
        k = max(i for i, (y0, _) in enumerate(runs) if y0 <= 152)
        y0 = runs[k][0]; y1 = runs[k + 1][0] if k + 1 < len(runs) else 168
        assert y1 >= 160, (t, 'полоса кончается до 160')
        idx = list(runs[k][1])
        assert all(pen_idx[P[y][x]] != idx[3] for y in range(y0, y1) for x in range(160)), (t, 'перо 3 занято')
        idx[3] = ys
        runs[k] = (y0, tuple(idx))
    # владелец 17.11: «пусть цвет полосы перспективы на полу останется в плоскости со спрайтами» — линия пола и силуэт
    # идола одного цвета с оранжевым бойцов (номер 2): номер 5 (A000 | серый) -> 2 (C000), A000 полосы пола пуста;
    # боец пишется поверх в 2 плоскостях, ушёл — клетка из тайла (сборка полосы пола в 2 плоскостях, без мигания)
    BAND_A[t] = band_a(d, img, t, runs)
    return rgb, pen_idx, runs


BAND_A = {}                               # комната -> есть ли точки с номером 4..7 в полосе пола (A000 не пуста)


def band_a(d, img, t, runs):
    """any pixel of the floor band (rows BAND_Y..167, tiles of the room + idol pen 3 in rows 152..159) with index >= 4"""
    A, B = tile_planes(d)
    m = geom15.room40(img, t)
    def idx_at(y):
        return next(idx for y0, idx in reversed(runs) if y0 <= y)
    pens = set()
    for y in range(BAND_Y, 168):
        R, k = y >> 3, y & 7
        for c in range(40):
            tl = m[R][c]
            for n in range(6):
                p = (A[8 * tl + k] >> (7 - n) & 1) | (B[8 * tl + k] >> (7 - n) & 1) << 1
                pens.add((y, p))
    pens |= {(y, 3) for y in range(152, 160)} | {(y, 1) for y in range(BAND_Y, 168)}   # идол (силуэт 3, узор 1), дыры
    pens |= {(y, p) for y in range(152, 168) for p in (0, 2)}                           # fl_patch: ряды 19 / 20
    return any(idx_at(y)[p] >= 4 for y, p in pens)
