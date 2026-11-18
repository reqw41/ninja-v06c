#!/usr/bin/env python3
"""build/code.txt: the skool listing as 'ADDR  instr', executed instructions only marked '*'.
  python3 tools/code_txt.py [build/golden/all.map]"""
import re, sys, os
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
mp = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build/golden/all.map')
exe = {int(x, 16) for x in open(mp)}
out = []
lab = None
for line in open(os.path.join(ROOT, 'build/zx/ninja.skool')):
    if line.startswith('@label='):
        lab = line.strip()[7:]
        continue
    m = re.match(r'^([cb* ])\$([0-9A-F]{4}) (.*)$', line.rstrip('\n'))
    if m:
        kind, a, rest = m.groups()
        a = int(a, 16)
        ins = rest.split(';')[0].rstrip()
        if ins.startswith('DEFB') or ins.startswith('DEFW') or ins.startswith('DEFM') or ins.startswith('DEFS'):
            if len(ins) > 60: ins = ins[:60] + '...'
        if lab: out.append(f'{lab}:'); lab = None
        out.append(f'{a:04X} {"*" if a in exe else " "} {ins}')
    elif line.startswith('; ') and not line.startswith(';  '):
        pass
open(os.path.join(ROOT, 'build/code.txt'), 'w').write('\n'.join(out) + '\n')
print(len(out), 'lines')
