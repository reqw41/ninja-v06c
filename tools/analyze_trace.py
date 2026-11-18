#!/usr/bin/env python3
"""Summarise a run_trace.py --hist run.

  tools/.venv/bin/python tools/analyze_trace.py build/trace/hist build/snap/ninja.z80

Writes to the trace dir:
  ranges.txt   executed RAM code ranges (contiguous by instruction length)
  calls.txt    CALL/RST/JP targets reached from executed code, with hit counts
  report.txt   HALT sites, ROM entry points used, IN/OUT sites, hottest routines
"""
import os
import re
import sys

from skoolkit.snapshot import Snapshot
from skoolkit.traceutils import disassemble

d, snapfile = sys.argv[1], sys.argv[2]
hist = {}
tcost = {}
for line in open(os.path.join(d, 'hist.txt')):
    a, n, *t = line.split()
    hist[int(a, 16)] = int(n)
    if t:
        tcost[int(a, 16)] = int(t[0])

mem = [0] * 16384 + list(Snapshot.get(snapfile).ram(-1))
ins = {a: disassemble(mem, a) for a in hist}

# contiguous ranges of executed RAM code
ranges = []
for a in sorted(x for x in hist if x >= 0x4000):
    text, size = ins[a]
    if ranges and a <= ranges[-1][1]:
        ranges[-1][1] = max(ranges[-1][1], a + size)
    else:
        ranges.append([a, a + size])
with open(os.path.join(d, 'ranges.txt'), 'w') as f:
    for s, e in ranges:
        f.write(f'${s:04X}-${e - 1:04X} {e - s}\n')

# call / jump targets
calls = {}
jumps = {}
rom = {}
halts, ios = [], []
for a in sorted(hist):
    text = ins[a][0]
    m = re.match(r'(CALL|JP|RST)\b(?:\s+\w+,)?\s*\$?([0-9A-F]+)$', text.replace(' ', ' ', 1))
    if text.startswith('HALT'):
        halts.append(a)
    if text.startswith(('IN ', 'OUT ')):
        ios.append((a, text))
    m = re.match(r'(CALL|JP|RST)\s+(?:(?:NZ|Z|NC|C|PO|PE|P|M),)?\$([0-9A-F]{2,4})$', text)
    if not m:
        continue
    t = int(m.group(2), 16)
    kind = 'CALL' if m.group(1) in ('CALL', 'RST') else 'JP'
    if a < 0x4000:
        continue
    tgt = calls if kind == 'CALL' else jumps
    tgt.setdefault(t, []).append(a)
    if t < 0x4000:
        rom.setdefault(t, []).append(a)

with open(os.path.join(d, 'calls.txt'), 'w') as f:
    for t in sorted(calls):
        f.write(f'${t:04X} hits={hist.get(t, 0):8d} from ' +
                ' '.join(f'${x:04X}' for x in calls[t]) + '\n')

with open(os.path.join(d, 'report.txt'), 'w') as f:
    f.write(f'executed addresses: {len(hist)} (RAM {sum(1 for a in hist if a >= 0x4000)})\n')
    f.write(f'code ranges: {len(ranges)}, bytes {sum(e - s for s, e in ranges)}\n\n')
    f.write('HALT sites:\n')
    for a in halts:
        f.write(f'  ${a:04X} x{hist[a]}\n')
    f.write('\nROM routines used (target <- callers):\n')
    for t in sorted(rom):
        f.write(f'  ${t:04X} <- ' + ' '.join(f'${x:04X}' for x in rom[t]) + '\n')
    f.write('\nIN/OUT sites:\n')
    for a, t in ios:
        f.write(f'  ${a:04X} {t:20s} x{hist[a]}\n')
    f.write('\nCALL targets by hit count (top 60):\n')
    for t in sorted(calls, key=lambda t: -hist.get(t, 0))[:60]:
        f.write(f'  ${t:04X} x{hist.get(t, 0):8d}  callers {len(calls[t])}\n')
print(open(os.path.join(d, 'report.txt')).read())

# ---- timing: main loop period and exclusive T-states per routine ----
loopf = os.path.join(d, 'loop.txt')
if tcost and os.path.exists(loopf):
    FRAME = 69888
    ts = [int(l.split()[1]) for l in open(loopf)]
    per = sorted(b - a for a, b in zip(ts, ts[1:]))
    # passes that include a room change/transition are long; report percentiles
    def pct(p):
        return per[min(len(per) - 1, int(len(per) * p))]
    labels = {}
    ctl = os.path.join(os.path.dirname(__file__), '..', 'src', 'ninja.ctl')
    for line in open(ctl):
        m = re.match(r'@ \$([0-9A-F]{4}) label=(\w+)', line)
        if m:
            labels[int(m.group(1), 16)] = m.group(2)
    starts = sorted(set(labels) | {s for s, e in ranges})
    import bisect
    def owner(a):
        if a < 0x4000:
            return 'ROM'
        i = bisect.bisect_right(starts, a) - 1
        s = starts[i]
        return labels.get(s, f'${s:04X}')
    excl = {}
    for a, t in tcost.items():
        o = owner(a)
        excl[o] = excl.get(o, 0) + t
    total = sum(tcost.values())
    with open(os.path.join(d, 'timing.txt'), 'w') as f:
        f.write(f'main loop passes: {len(ts)}\n')
        f.write('pass length, T-states (frames of 69888 T):\n')
        for p in (0.1, 0.25, 0.5, 0.75, 0.9, 0.99):
            f.write(f'  p{int(p*100):02d}: {pct(p):8d} ({pct(p)/FRAME:.2f})\n')
        f.write(f'\nexclusive T-states by routine (total {total}, {total/FRAME:.0f} frames):\n')
        for o, t in sorted(excl.items(), key=lambda x: -x[1])[:40]:
            f.write(f'  {o:22s} {t:12d} {100*t/total:5.1f}%\n')
    print(open(os.path.join(d, 'timing.txt')).read())
