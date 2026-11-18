#!/usr/bin/env python3
"""Executed-PC map (one hex address per line) -> ranges.txt for gen_ctl.py, using real instruction lengths.
  tools/.venv/bin/python tools/map2ranges.py build/golden/all.map [old ranges.txt ...] > ranges.txt"""
import sys, os
from skoolkit.snapshot import Snapshot
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
mem = Snapshot.get(os.path.join(ROOT, 'build/snap/ninja.z80')).ram(-1)
mem = [0] * 0x4000 + list(mem) if len(mem) == 0xC000 else list(mem)

def base_len(op):
    if op in (0x01, 0x11, 0x21, 0x31, 0x22, 0x2A, 0x32, 0x3A, 0xC3, 0xCD) or (op & 0xC7) in (0xC2, 0xC4):
        return 3
    if op in (0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38,
              0xD3, 0xDB, 0xCB) or (op & 0xC7) == 0xC6:
        return 2
    return 1


def ilen(pc):
    op = mem[pc]
    if op == 0xED:
        return 4 if mem[pc + 1] in (0x43, 0x4B, 0x53, 0x5B, 0x63, 0x6B, 0x73, 0x7B) else 2
    if op in (0xDD, 0xFD):
        o = mem[pc + 1]
        if o == 0xCB:
            return 4
        n = 1 + base_len(o)
        if o in (0x34, 0x35, 0x36) or (0x40 <= o <= 0xBF and o != 0x76 and ((o & 7) == 6 or (o & 0x38) == 0x30)):
            n += 1
        return n
    return base_len(op)


cov = set()
for pc in (int(x, 16) for x in open(sys.argv[1])):
    n = ilen(pc)
    cov.update(range(pc, pc + n))
for f in sys.argv[2:]:
    for line in open(f):
        a, b = line.split()[0].split('-')
        cov.update(range(int(a[1:], 16), int(b[1:], 16) + 1))
s = sorted(cov); out = []
for a in s:
    if out and a == out[-1][1] + 1: out[-1][1] = a
    else: out.append([a, a])
for a, b in out:
    print(f'${a:04X}-${b:04X} {b - a + 1}')
