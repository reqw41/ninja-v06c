#!/usr/bin/env python3
"""Record ZX goldens of Ninja, one step per main-loop pass ($ED23).

  tools/.venv/bin/python tools/golden.py OUT.jsonl.gz --frames N --keys "f0-f1:K+K,..." \
      [--at-step "N:ADDR=VAL;ADDR=VAL"]... [--orig] [--seed-r R]

Starts from build/snap/ninja.z80 (after tape load, PC=$5CEF). By default the port's fixes are
applied (docs/PORT_PLAN.md): enemy melee ($EF4F B3->B4), room number moved to $E4BB (bugfix 2,
22 references), ROM BEEPER calls replaced by CALL $03F7 (RET) so interrupts are never enabled.
--orig records the original game instead (interrupts on, as on a real Spectrum).

Output (gzip JSON lines): line 0 {"kind":"init", "mem": hex of $7300-$FF7F at the first $ED23,
"pre"}; then one line per later $ED23 boundary {"step", "frame", "t", "in": [[port, value, count], ...]
(run-length) read during the pass that just ended, "d": [[addr, val]] memory changes of that pass, "pre":
external writes (--at-step) applied at this boundary, after "d"}. The model replays: apply the
previous line's "pre", run one pass consuming "in" (port reads) and "r" (values of LD A,R),
compare memory with "d".
"""
import argparse
import gzip
import json
import os
import sys

from skoolkit.simulator import Simulator
from skoolkit.simutils import from_snapshot, PC, T, IFF, IM
from skoolkit.snapshot import Snapshot

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
LO, HI = 0x7300, 0xFF80
LOOP = 0xED23
KEYS = {
    'SHIFT': (0, 0), 'Z': (0, 1), 'X': (0, 2), 'C': (0, 3), 'V': (0, 4),
    'A': (1, 0), 'S': (1, 1), 'D': (1, 2), 'F': (1, 3), 'G': (1, 4),
    'Q': (2, 0), 'W': (2, 1), 'E': (2, 2), 'R': (2, 3), 'T': (2, 4),
    '1': (3, 0), '2': (3, 1), '3': (3, 2), '4': (3, 3), '5': (3, 4),
    '0': (4, 0), '9': (4, 1), '8': (4, 2), '7': (4, 3), '6': (4, 4),
    'P': (5, 0), 'O': (5, 1), 'I': (5, 2), 'U': (5, 3), 'Y': (5, 4),
    'ENTER': (6, 0), 'L': (6, 1), 'K': (6, 2), 'J': (6, 3), 'H': (6, 4),
    'SPACE': (7, 0), 'SYM': (7, 1), 'M': (7, 2), 'N': (7, 3), 'B': (7, 4),
}
# bugfix 2 (Bandit / Einar Saukas): LD A,($E4BA) etc. -> $E4BB
ROOM_REFS = [0xEABD, 0xEAE7, 0xEAFC, 0xEB3A, 0xED08, 0xED69, 0xED71, 0xF108, 0xF59B, 0xF76F, 0xF806,
             0xF818, 0xFA28, 0xFA40, 0xFAF4, 0xFB2C, 0xFB3E, 0xFB44, 0xFB5A, 0xFD78, 0xFDCD, 0xFDDD]
FIXES = [(0xEF4F, 0xB4), (0xE2CB, 0xF7), (0xF909, 0xF7)] + [(a, 0xBB) for a in ROOM_REFS]


# tour: (source room, hero X[, extra pokes]) -> the game itself moves to the neighbour
# (X >= $19: right, X < 2: left; HERO_INPUT=1 under the ceiling hole: up)
TOUR = [(15, 0x19), (15, 0x01), (6, 0x01), (5, 0x19), (5, 0x01), (3, 0x01), (2, 0x19), (17, 0x01),
        (2, 0x01), (18, 0x19), (12, 0x01), (11, 0x19), (14, 0x01), (13, 0x19), (0, 0x01), (0, 0x19),
        (7, 0x19), (9, 0x01), (1, 0x01),
        (9, 0x08, [(0xE4D9, 0x08), (0xE1ED, 1)]),         # up through the ceiling hole -> 20
        # 17 -> 10 (Akuma's chamber) opens after the 6th idol ($F5BC: $D8DD = $0B, NEIGHBOURS[17].up);
        # 17 has no ceiling hole either, so the hole X is forced too
        (17, 0x0A, [(0xD8DD, 0x0B), (0xE4CC, 6), (0xE4D9, 0x0A), (0xE1ED, 1)]),
        # down through the floor hole of room 7 (X=18) -> 14: input 2 in crouch phase 2 ($E4CD)
        (7, 0x12, [(0xE4DA, 0x12), (0xE1ED, 2), (0xE4CD, 2)])]


def tour_pokes(entry, room_addr):
    p, x = entry[0], entry[1]
    extra = entry[2] if len(entry) > 2 else []
    return [(room_addr, p), (0xE461, x)] + list(extra)


def regs_dict(regs):
    from skoolkit.simutils import REGISTERS as RG
    r = {k.lower().replace('^', "'"): regs[i] for k, i in RG.items() if k not in ('MEMPTR', 'T')}
    r['ix'] = r.pop('ixh') * 256 + r.pop('ixl')
    r['iy'] = r.pop('iyh') * 256 + r.pop('iyl')
    r['iff'], r['im'] = regs[IFF], regs[IM]
    return r


def parse_keys(spec):
    out = []
    for item in filter(None, spec.split(',')):
        rng, keys = item.split(':')
        a, _, b = rng.partition('-')
        out.append((int(a), int(b or a), [KEYS[k] for k in keys.split('+')]))
    return out


class Tracer:
    def __init__(self):
        self.keyboard = [0] * 8
        self.log = []
        self.border = 7
        self.outfe = 0

    def read_port(self, registers, port):
        if port & 0xFF == 0x1F:
            v = 0
        elif port % 2 == 0:
            h = (port >> 8) ^ 0xFF
            v = 0x40
            i = 0
            while h:
                if h & 1:
                    v |= self.keyboard[i]
                h >>= 1
                i += 1
            v ^= 0xFF
        else:
            v = 0xFF
        lg = self.log
        if lg and lg[-1][0] == port and lg[-1][1] == v:
            lg[-1][2] += 1
        else:
            lg.append([port, v, 1])
        return v

    def write_port(self, registers, port, value, offset=0):
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--frames', type=int, default=3000)
    ap.add_argument('--keys', default='')
    ap.add_argument('--at-step', action='append', default=[])
    ap.add_argument('--orig', action='store_true')
    ap.add_argument('--map', help='write executed RAM addresses (hex, one per line) to this file')
    ap.add_argument('--watch', default='', help='debug: hex PCs to report as "step: pc" when executed')
    ap.add_argument('--tour', type=int, default=0, help='teleport every N steps (all 21 rooms, cycling)')
    ap.add_argument('--tour-start', type=int, default=20)
    ap.add_argument('--snap', default=os.path.join(ROOT, 'build', 'snap', 'ninja.z80'))
    a = ap.parse_args()

    sim = from_snapshot(Simulator, Snapshot.get(a.snap), config={'fast_djnz': False, 'fast_ldir': False})
    tr = Tracer()
    sim.set_tracer(tr)
    regs, mem = sim.registers, sim.memory
    if not a.orig:
        for ad, v in FIXES:
            mem[ad] = v
    keys = parse_keys(a.keys)
    at = {}
    for spec in a.at_step:
        n, _, av = spec.partition(':')
        at[int(n)] = [(int(x.split('=')[0], 16), int(x.split('=')[1], 16)) for x in av.split(';')]
    room_addr = 0xE4BA if a.orig else 0xE4BB
    if a.tour:
        for k in range(200):
            st = a.tour_start + k * a.tour
            at.setdefault(st, []).extend(tour_pokes(TOUR[k % len(TOUR)], room_addr))
    watch = {int(x, 16) for x in a.watch.split(',') if x}
    exe = set() if a.map else None
    rlog = []
    fd = sim.frame_duration
    opcodes = sim.opcodes
    prev = None
    step = 0
    out = gzip.open(a.out, 'wt')
    for frame in range(a.frames):
        kb = [0] * 8
        for f0, f1, ks in keys:
            if f0 <= frame <= f1:
                for r, b in ks:
                    kb[r] |= 1 << b
        tr.keyboard[:] = kb
        end = (regs[T] // fd + 1) * fd
        while regs[T] < end:
            pc0 = regs[PC]
            if exe is not None:
                exe.add(pc0)
            opcodes[mem[pc0]]()
            if mem[pc0] == 0xED and mem[(pc0 + 1) & 0xFFFF] == 0x5F:   # LD A,R: the model gets A
                rlog.append(regs[0])
            if watch and regs[PC] in watch:
                print(f'step {step}: ${regs[PC]:04X}')
            if regs[PC] == LOOP:
                cur = bytes(mem[LO:HI])
                pre = at.get(step, [])
                if prev is None:
                    out.write(json.dumps({'kind': 'init', 'mem': cur.hex(), 'lo': LO, 'frame': frame,
                                          't': regs[T], 'fixes': not a.orig, 'in': tr.log, 'r': rlog,
                                          'pre': [[ad, v] for ad, v in pre],
                                          'full': bytes(mem[0:0x10000]).hex(),
                                          'regs': regs_dict(regs)}) + '\n')
                else:
                    d = [[LO + i, cur[i]] for i in range(len(cur)) if cur[i] != prev[i]]
                    out.write(json.dumps({'step': step, 'frame': frame, 't': regs[T], 'in': tr.log,
                                          'r': rlog, 'd': d, 'pre': [[ad, v] for ad, v in pre]}) + '\n')
                for ad, v in pre:
                    mem[ad] = v
                tr.log = []
                rlog = []
                prev = bytes(mem[LO:HI])
                step += 1
        if regs[26]:
            sim.accept_interrupt(regs, mem, regs[PC])
    out.close()
    if exe is not None:
        with open(a.map, 'w') as fm:
            fm.write(''.join(f'{x:04X}\n' for x in sorted(exe) if x >= 0x4000))
    print(f'{a.out}: {step} steps, {a.frames} frames, fixes={not a.orig}')


if __name__ == '__main__':
    main()
