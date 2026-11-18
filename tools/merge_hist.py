#!/usr/bin/env python3
"""Merge hist.txt (addr count tstates) from several run_trace dirs: merge_hist.py OUTDIR IN..."""
import os, sys
out, ins = sys.argv[1], sys.argv[2:]
h, t = {}, {}
for d in ins:
    for line in open(os.path.join(d, 'hist.txt')):
        a, n, *c = line.split()
        h[a] = h.get(a, 0) + int(n)
        t[a] = t.get(a, 0) + int(c[0] if c else 0)
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, 'hist.txt'), 'w') as f:
    for a in sorted(h, key=lambda x: int(x, 16)):
        f.write(f'{a} {h[a]} {t[a]}\n')
print(f'{len(h)} addresses from {len(ins)} runs')
