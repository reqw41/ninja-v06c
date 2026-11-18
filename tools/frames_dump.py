#!/usr/bin/env python3
"""Кадры бойцов Вектора из src/vec/gen/cpc.asm: frame(f) -> {(x, y): перо}, x от левого края рамки ZX (точки x0.75)."""
import os, re
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def load():
    s = open(os.path.join(ROOT, 'src/vec/gen/cpc.asm')).read()
    data, cur = {}, None
    for line in s[:s.index('cpc_data_end:')].split('\n'):
        line = line.split(';')[0]
        m = re.match(r'(cpc_c\d+_\d+):', line)
        if m:
            cur = m.group(1); data[cur] = []; continue
        if cur and line.strip().startswith('DB\t0x'):
            data[cur] += [int(x, 16) for x in line.split('DB\t', 1)[1].split(',')]
        else:
            cur = None
    fr = {int(f): (h, cols) for f, h, cols in re.findall(r'cpc_f(\d+):[^\n]*\n\t\t\tDB\t([^\n]+)\n((?:\t\t\tDW\t[^\n]+\n\t\t\tDB\t[^\n]+\n)+)', s)}

    def frame(f):
        h, cols = fr[f]
        ox = int(h.split(',')[0]); ox = ox - 256 if ox > 127 else ox
        top = int(h.split(',')[2])
        P = {}
        for j, (p, r0, n) in enumerate(re.findall(r'DW\t(\S+)\n\t\t\tDB\t(\d+),(\d+)', cols)):
            if p == '0':
                continue
            d = data[p]
            for r in range(int(n)):
                for b in range(8):
                    v = ((d[2 * r] >> (7 - b)) & 1) | (((d[2 * r + 1] >> (7 - b)) & 1) << 1)
                    if v:
                        P[(8 * j + b + ox, int(r0) + r + top)] = v
        return P
    return frame
