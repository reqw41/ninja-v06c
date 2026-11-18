#!/usr/bin/env python3
"""Model of the whole Atari Ninja sound VBI: effects $2418, score tick $2BE8, music $BBE6.

  python3 tools/atari/sound.py build/a8run/full/mem2250.bin build/a8run/full/pokey.log 2250 FIRST_VBI_FRAME

The log is written by tools/atari/pokey.lua with NINJA_FULL=1: POKEY writes, RANDOM reads and
writes to the sound variables, in execution order. Game writes (from PCs outside the sound code)
are applied to the model's memory as they come; each OS write to RTCLOK $14 starts a VBI, where
the model runs the sound code and its POKEY writes are compared with the logged ones (RANDOM
values are taken from the log in order).

Sound VBI (called from $159A/$159D/$15C1):
  $2418  hit thud on ch1 ($2416 counts down: AUDC1 = n | $A0, AUDF1 = 8)
         if $CC < 0 (no music): once per 256 frames ($14 = 0) count $24E8 down and with
         RANDOM & 3 = 0 start the whistle ($2417 = $40) and stop ambient notes; whistle:
         AUDF3 = $2417, AUDC3 = n >> 3 (noise), AUDC4 = $C0 | n >> 3, AUDF4 = $A0;
         effects per channel X=2..0 ($240D volume += $2410 step, at 5 the step turns to -1;
         AUDC = volume (noise), AUDF = volume + $2413[X]);
  $24EA  ambient notes (every 2nd frame, both modes): volume of the current note goes 0..2 and
         back; while $24E8 < 0 a random pause (4 or RANDOM & $18) then a random walk ±1 over
         the note table $2405 (AUDF 91,0,81,72,60,53,45,0 -> ch3);
  $2BE8  score tick: while $9F5A > 0: AUDC4 = 0, $9F5A -= 1, AUDF4 = $60 - $9F5A (SBC with the
         carry left by the code above), AUDC4 = $C4 (0 when the count ends);
  $BBE6  music ($BDBC: $40 restart, $00 play, $C0 silence + stop, $80 stopped) -> $BC10.
"""
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from music import Driver  # noqa: E402

# code run by the sound VBI; $249F-$24CA (start an effect) and $24D6-$24E3 (silence) are
# called by the game, so their writes are game events
SOUND_PCS = [(0x2418, 0x249E), (0x24EA, 0x255C), (0x2BE8, 0x2C30), (0xBBE6, 0xBBFF), (0xBC00, 0xBD56)]


def is_sound_pc(pc):
    return any(a <= pc <= b for a, b in SOUND_PCS)


class Sound:
    def __init__(self, mem):
        self.d = Driver(mem)
        self.m = self.d.m          # shared memory
        self.c = 1                 # 6502 carry, tracked where the sound code changes it

    def vbi(self, rnd, part_a=True, part_b=None):
        """part_a: $2418/$24EA/$2BE8; part_b: music ($BBE6). part_b=None: as the main VBI
        ($1590) does it, only while $CC >= 0."""
        m = self.m
        out = []
        # carry at $2418 = last CMP #7 of $255D (projectile 0 state $9F46 >= 7), the game VBI
        # code run just before; it reaches the score tick $2C02 when nothing else changes it
        self.c = 1 if m[0x9F46] >= 7 else 0
        if not part_a:
            return out + self.music(part_b)
        # $2418
        if m[0x2416]:
            m[0x2416] -= 1; self.c = 1
            out += [(1, m[0x2416] | 0xA0), (0, 8)]
        if m[0xCC] & 0x80:
            if m[0x14] == 0:
                if not m[0x24E8] & 0x80:
                    m[0x24E8] = (m[0x24E8] - 1) & 0xFF
                if rnd() & 3 == 0:
                    m[0x2417] = 0x40; m[0x24E8] = 1; m[0x24E6] = 0
            if m[0x2417]:
                v = m[0x2417] - 1; m[0x2417] = v
                self.c = (v >> 2) & 1          # three LSR A: carry = bit 2
                out += [(4, v), (7, (v >> 3) | 0xC0), (5, v >> 3), (6, 0xA0)]
            for x, y in ((2, 4), (1, 2), (0, 0)):
                a = m[0x240D + x]
                if not a:
                    continue
                s = a + m[0x2410 + x]; a = s & 0xFF; self.c = s >> 8
                m[0x240D + x] = a
                out.append((y + 1, a))
                self.c = 1 if a >= 5 else 0
                if a == 5:
                    m[0x2410 + x] = 0xFF
                s = a + m[0x2413 + x]; self.c = s >> 8
                out.append((y, s & 0xFF))
        # $24EA
        m[0x24E7] = (m[0x24E7] - 1) & 0xFF
        if m[0x24E7] & 0x80:
            m[0x24E7] = 1
            if m[0x24E6] == 0:
                if m[0x24E5]:
                    v = m[0x24E5] - 1; m[0x24E5] = v; self.c = 1
                    out.append((5, v | 0xA0))
            else:
                v = m[0x24E5]
                self.c = 1 if v >= 2 else 0
                if v != 2:
                    s = v + 1; m[0x24E5] = s & 0xFF; self.c = s >> 8
                    out.append((5, (s & 0xFF) | 0xA0))
            if m[0x24E8] & 0x80:
                m[0x24E4] = (m[0x24E4] - 1) & 0xFF
                if m[0x24E4] & 0x80:
                    r = rnd()
                    m[0x24E4] = 4 if r & 3 else (rnd() & 0x18)
                    r = rnd() & 3
                    a = (r - 1) & 0xFF; self.c = 1 if r >= 1 else 0
                    s = a + m[0x24E9]; self.c = s >> 8
                    a = s & 7
                    m[0x24E9] = a
                    n = m[0x2405 + a]
                    m[0x24E6] = n
                    if n:
                        out += [(4, n)]
                        m[0x24E5] = 1
                        out += [(5, 0xA1)]
        # $2BE8
        if m[0x9F5A]:
            while True:
                m[0x9F5B] = (m[0x9F5B] - 1) & 0xFF
                if m[0x9F5B] & 0x80:
                    break
                out.append((7, 0))
            m[0x9F5A] = (m[0x9F5A] - 1) & 0xFF
            if m[0x9F5A]:
                s = 0x60 - m[0x9F5A] - (1 - self.c)
                self.c = 1 if s >= 0 else 0
                out += [(6, s & 0xFF), (7, 0xC4)]
            else:
                out.append((7, 0))
            m[0x9F5B] = 1
        return out + self.music(part_b)

    def music(self, part_b):
        m = self.m
        out = []
        if part_b is None:
            part_b = not m[0xCC] & 0x80
        if part_b:
            st = m[0xBDBC]
            if st & 0x80:
                if st & 0x40:
                    for a in range(8, -1, -1):
                        out.append((a, 0))
                    m[0xBDBC] = 0x80
            else:
                if st & 0x40:
                    for a in range(0x84, 0x90):
                        m[a] = 0
                    m[0xBDBC] = 0
                f0, c0 = list(self.d.audf), list(self.d.audc)
                writes = self.d.frame_writes()
                out += writes
        return out


def run(mem_path, log_path, start, first_vbi):
    """Split the log into intervals between RTCLOK changes. A VBI runs atomically at the start
    of its interval: the model runs it on the state before the interval's game writes, then the
    game writes are applied."""
    mem = open(mem_path, 'rb').read()
    s = Sound(mem)
    segs = [[None, []]]
    last14 = s.m[0x14]
    for line in open(log_path):
        p = line.split()
        f = int(p[0])
        if f <= start:
            continue
        if p[1] == 'W' and int(p[2], 16) == 0x14 and not is_sound_pc(int(p[4], 16)):
            v = int(p[3], 16)
            if v == last14:                 # INC $14 writes the old value first (6502 RMW)
                continue
            last14 = v
            segs.append([(f, v), []])
            continue
        segs[-1][1].append(p)
    vbis = bad = 0
    for head, evs in segs:
        ran = any(p[1] == 'W' and int(p[2], 16) == 0x24E7 and int(p[4], 16) == 0x24EA for p in evs)
        # music part ran: any write by $BBE6-$BD56 (driver always bumps its frame counter)
        ranb = any((p[1] == 'W' and 0xBBE6 <= int(p[4], 16) <= 0xBD56) or
                   (p[1] not in ('W', 'R') and 0xBBE6 <= int(p[3], 16) <= 0xBD56) for p in evs)
        if head is not None:
            f, v = head
            s.m[0x14] = v
            if (ran or ranb) and f >= first_vbi:
                rq = [int(p[3], 16) for p in evs if p[1] == 'R' and is_sound_pc(int(p[4], 16))]
                logged = [(int(p[1], 16), int(p[2], 16)) for p in evs
                          if p[1] not in ('W', 'R') and is_sound_pc(int(p[3], 16))]
                it = iter(rq)
                model = s.vbi(lambda: next(it), part_a=ran, part_b=ranb if not ran else (ranb or None))
                vbis += 1
                if model != logged:
                    bad += 1
                    if bad <= 8:
                        print(f'VBI f{f}: model {[(a, hex(v)) for a, v in model]}\n'
                              f'           log   {[(a, hex(v)) for a, v in logged]}')
        for p in evs:
            if p[1] == 'W' and not is_sound_pc(int(p[4], 16)):
                s.m[int(p[2], 16)] = int(p[3], 16)
    print(f'{vbis} VBIs compared, {bad} differ')
    return bad


if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]) if len(sys.argv) > 4 else 0)
