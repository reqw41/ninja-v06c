#!/usr/bin/env python3
"""Run Ninja from a post-load snapshot frame by frame with scripted keys.

Collects an execution map (addresses of executed instructions), counts how
often each address runs, logs CALL targets and HALT sites, and dumps SCR
screenshots at chosen frames.

  tools/.venv/bin/python tools/run_trace.py SNAP OUTDIR --frames 3000 \
      --keys "100-110:ENTER,300-2000:P,..." --shots 50,200,500
"""
import argparse
import os
import sys

from skoolkit import CSimulator
from skoolkit.simulator import Simulator
from skoolkit.simutils import from_snapshot, PC, T
from skoolkit.snapshot import Snapshot

# (row, bit) in SkoolKit keyboard array: row i = half-row with A(8+i)=0
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


def parse_keys(spec):
    out = []
    for item in filter(None, spec.split(',')):
        rng, keys = item.split(':')
        a, _, b = rng.partition('-')
        out.append((int(a), int(b or a), [KEYS[k] for k in keys.split('+')]))
    return out


class KTracer:
    """Minimal tracer: keyboard on even ports, Kempston (0x1F) reads 0."""

    def __init__(self):
        self.keyboard = [0] * 8
        self.border = 7
        self.outfe = 0
        self.out7ffd = 0
        self.outfffd = 0
        self.ay = [0] * 16
        self.spkr = None
        self.audio_log = []

    def read_port(self, registers, port):
        if port & 0xFF == 0x1F:
            return 0
        if port % 2 == 0:
            h = (port >> 8) ^ 0xFF
            v = 0x40
            i = 0
            while h:
                if h & 1:
                    v |= self.keyboard[i]
                h >>= 1
                i += 1
            return v ^ 0xFF
        return 0xFF

    def write_port(self, registers, port, value, offset=0):
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('snap')
    ap.add_argument('outdir')
    ap.add_argument('--frames', type=int, default=1000)
    ap.add_argument('--keys', default='')
    ap.add_argument('--shots', default='')
    ap.add_argument('--poke', action='append', default=[],
                    help='FRAME[-END[/STEP]]:ADDR=VAL[;..] (hex addr/val), applied at the start of FRAME; may repeat')
    ap.add_argument('--at', action='append', default=[],
                    help='FRAME@PC:ADDR=VAL[;ADDR=VAL] (hex): once, at the first time PC is '
                         'reached at or after FRAME (needs --hist); may repeat')
    ap.add_argument('--probe', action='append', default=[],
                    help='PC:ADDR[+LEN][,ADDR..][@MAX] (hex): print memory each time PC is hit '
                         '(up to MAX times, default 20; needs --hist)')
    ap.add_argument('--ring', default='',
                    help='hex PC: when first reached, write the last 400 executed PCs with registers to ring.txt (needs --hist)')
    ap.add_argument('--dump', action='append', default=[],
                    help='FRAME@PC:ADDR+LEN (hex): once, at the first hit of PC at/after FRAME, '
                         'write memory to OUTDIR/dump_PC.bin (needs --hist)')
    ap.add_argument('--memwatch', default='',
                    help='hex address: log PC/frame each time its value changes (needs --hist)')
    ap.add_argument('--watch', default='',
                    help='comma list of hex addresses: log frame of first execution')
    ap.add_argument('--loop', default='ED23', help='main loop address (hex) to time')
    ap.add_argument('--hist', action='store_true',
                    help='count executions per address (slow, Python sim)')
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)

    snap = Snapshot.get(a.snap)
    cls = Simulator if a.hist else (CSimulator or Simulator)
    sim = from_snapshot(cls, snap, config={'fast_djnz': False, 'fast_ldir': False})
    tr = KTracer()
    sim.set_tracer(tr)
    regs, mem = sim.registers, sim.memory
    fd = sim.frame_duration
    keys = parse_keys(a.keys)
    pokes = {}
    for p in a.poke:
        fr, _, av = p.partition(':')
        rng, _, step = fr.partition('/')
        f0, _, f1 = rng.partition('-')
        for f in range(int(f0), int(f1 or f0) + 1, int(step or 1)):
            for one in av.split(';'):
                ad, _, v = one.partition('=')
                pokes.setdefault(f, []).append((int(ad, 16), int(v, 16)))
    watch = {int(x, 16) for x in a.watch.split(',') if x}
    ats = []   # [frame, pc, [(addr, val)], done]
    for p in a.at:
        fp, _, av = p.partition(':')
        fr, _, pc_ = fp.partition('@')
        ats.append([int(fr), int(pc_, 16),
                    [(int(x.split('=')[0], 16), int(x.split('=')[1], 16)) for x in av.split(';')], False])
    probes = {}
    for p in a.probe:
        pc_, _, rest = p.partition(':')
        rest, _, mx = rest.partition('@')
        spans = []
        for x in rest.split(','):
            ad, _, ln = x.partition('+')
            spans.append((int(ad, 16), int(ln or '1', 16)))
        probes[int(pc_, 16)] = [spans, int(mx or 20)]
    ring_pc = int(a.ring, 16) if a.ring else None
    mw = int(a.memwatch, 16) if a.memwatch else None
    mw_val = None
    dumps = []
    for p in a.dump:
        fp, _, span = p.partition(':')
        fr, _, pc_ = fp.partition('@')
        ad, _, ln = span.partition('+')
        dumps.append([int(fr), int(pc_, 16), int(ad, 16), int(ln, 16), False])
    ring = []
    at_pcs = {x[1] for x in ats} | set(probes) | ({ring_pc} if ring_pc is not None else set()) | {d[1] for d in dumps}
    seen = {}
    shots = {int(x) for x in a.shots.split(',') if x}
    exec_map = set()
    hist = {}
    tcost = {}
    loop_t = []
    loop_pc = int(a.loop, 16)
    pc = regs[PC]
    for frame in range(a.frames):
        kb = [0] * 8
        for f0, f1, ks in keys:
            if f0 <= frame <= f1:
                for r, b in ks:
                    kb[r] |= 1 << b
        tr.keyboard[:] = kb
        for ad, v in pokes.get(frame, ()):
            mem[ad] = v
        end = (regs[T] // fd + 1) * fd
        if a.hist:
            opcodes = sim.opcodes
            while regs[T] < end:
                pc = regs[PC]
                if ring_pc is not None:
                    ring.append((pc, frame, regs[0], regs[6] * 256 + regs[7], regs[4] * 256 + regs[5], regs[12], regs[2] * 256 + regs[3]))
                    if len(ring) > 400:
                        del ring[0]
                if pc in at_pcs:
                    for d in dumps:
                        if not d[4] and d[1] == pc and frame >= d[0]:
                            with open(os.path.join(a.outdir, f'dump_{pc:04X}.bin'), 'wb') as df:
                                df.write(bytes(mem[d[2]:d[2] + d[3]]))
                            d[4] = True
                    if pc == ring_pc:
                        from skoolkit.traceutils import disassemble
                        with open(os.path.join(a.outdir, 'ring.txt'), 'w') as rf:
                            for (rp, rfr, ra, rhl, rde, rsp, rbc) in ring:
                                rf.write(f'f{rfr} {rp:04X} {disassemble(mem, rp)[0]:24s} A={ra:02X} BC={rbc:04X} DE={rde:04X} HL={rhl:04X} SP={rsp:04X}\n')
                        ring_pc = None
                    pr = probes.get(pc)
                    if pr and pr[1] > 0:
                        pr[1] -= 1
                        print(f'probe ${pc:04X} f{frame} SP={regs[12]:04X}: ' + ' | '.join(
                            f'{ad:04X}:' + ' '.join(f'{mem[ad + i]:02X}' for i in range(ln))
                            for ad, ln in pr[0]))
                    for x in ats:
                        if not x[3] and x[1] == pc and frame >= x[0]:
                            for ad, v in x[2]:
                                mem[ad] = v
                            x[3] = True
                            print(f'at ${pc:04X} frame {frame}: poked')
                t0 = regs[T]
                opcodes[mem[pc]]()
                hist[pc] = hist.get(pc, 0) + 1
                if mw is not None and mem[mw] != mw_val:
                    print(f'memwatch ${mw:04X}: {mw_val} -> {mem[mw]:02X} by ${pc:04X} f{frame}')
                    mw_val = mem[mw]
                tcost[pc] = tcost.get(pc, 0) + regs[T] - t0
                if pc == loop_pc:
                    loop_t.append((frame, t0))
                if regs[T] >= end and regs[26]:
                    pass
            if regs[26]:
                sim.accept_interrupt(regs, mem, regs[PC])
        else:
            sim.trace(regs[PC], -1, 0, end, 1, None, exec_map, kb, None, None)
        if watch:
            got = set(hist) if a.hist else exec_map
            for w in watch - set(seen):
                if w in got:
                    seen[w] = frame
        if frame in shots:
            with open(os.path.join(a.outdir, f'f{frame:05d}.scr'), 'wb') as f:
                f.write(bytes(mem[0x4000:0x5B00]))
    if a.hist:
        exec_map = set(hist)
        with open(os.path.join(a.outdir, 'hist.txt'), 'w') as f:
            for k in sorted(hist):
                f.write(f'{k:04X} {hist[k]} {tcost[k]}\n')
        with open(os.path.join(a.outdir, 'loop.txt'), 'w') as f:
            for fr, t in loop_t:
                f.write(f'{fr} {t}\n')
    with open(os.path.join(a.outdir, 'exec.map'), 'w') as f:
        for k in sorted(exec_map):
            f.write(f'${k:04X}\n')
    with open(os.path.join(a.outdir, 'ram.bin'), 'wb') as f:
        f.write(bytes(mem[0x4000:0x10000]))
    for w in sorted(watch):
        print(f'watch ${w:04X}: ' + (f'frame {seen[w]}' if w in seen else 'not reached'))
    print(f'frames={a.frames} executed={len(exec_map)} PC=${regs[PC]:04X}')


if __name__ == '__main__':
    main()
