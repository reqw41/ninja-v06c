#!/usr/bin/env python3
"""Random key script for run_trace.py: randkeys.py START END SEED"""
import random, sys
s, e, seed = map(int, sys.argv[1:4])
r = random.Random(seed)
moves = ['P', 'O', 'Q', 'A', 'P+ENTER', 'O+ENTER', 'Q+ENTER', 'A+ENTER', 'ENTER',
         'Q+P', 'Q+O', 'A+P', 'A+O', 'P', 'P', 'O']
out, f = [], s
while f < e:
    n = r.randint(15, 160)
    out.append(f'{f}-{min(e, f + n)}:{r.choice(moves)}')
    f += n + r.randint(0, 20)
print(','.join(out))
