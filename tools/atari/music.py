#!/usr/bin/env python3
"""Model of the Ninja (Atari 8-bit, Sculptured Software) music driver $BC10.

  python3 tools/atari/music.py MEM.bin POKEY.log START_FRAME [FRAMES]

MEM.bin is a 64K dump taken at the end of START_FRAME (tools/atari/pokey.lua NINJA_DUMP),
POKEY.log is the register log of the same run. The model starts from the driver state in
the dump and steps one frame per VBI; after each frame AUDF1-3/AUDC1-3 are compared with
the state reconstructed from the log.

Driver (6502, called once per frame from $BBF9):
  per channel X = 2..0: order list (ptr $BDFC/$BDFF[X]) of pattern numbers, $FF = restart;
  pattern ptr $BE02/$BE0D[n]; pattern byte < $80 = note: duration $BD67[b & $1F] frames,
  next byte = note index (+ transpose $BDA0[X]) into AUDF table $BD6C; byte >= $80 =
  command b & $0F: 0 instrument, 1 flicker on (amount), 2 flicker off, 3 transpose,
  4 distortion $80 (noise), 5 distortion $A0 (pure tone), 6 arpeggio on, 7 arpeggio off.
  Every frame: volume envelope of the instrument ($BDC6/$BDCC -> bytes until $FF, ORed with
  distortion -> AUDC); flicker: on even frames AUDF = table[note - amount]; arpeggio:
  AUDF = base + $BDBD[i] (sequence ends with $1F).
"""
import sys

ZP_DUR, ZP_ORD, ZP_POS, ZP_NOTE = 0x87, 0x84, 0x8A, 0x8D


class Driver:
    def __init__(self, mem):
        self.m = bytearray(mem)
        self.audf = [0] * 3
        self.audc = [0] * 3

    def b(self, a):
        return self.m[a & 0xFFFF]

    def frame_writes(self):
        """Step one frame, return POKEY writes [(reg, value)] in driver order."""
        self.frame()
        return self.writes

    def frame(self):
        m = self.m
        self.writes = w = []
        m[0xBD9A] = (m[0xBD9A] + 1) & 0xFF
        for x in (2, 1, 0):
            optr = m[0xBDFC + x] | m[0xBDFF + x] << 8
            if m[ZP_DUR + x] == 0:
                while True:
                    pat = m[optr + m[ZP_ORD + x]]
                    if pat == 0xFF:
                        m[ZP_DUR + x] = m[ZP_ORD + x] = m[ZP_POS + x] = 0
                        continue
                    break
                pptr = m[0xBE02 + pat] | m[0xBE0D + pat] << 8
                y = m[ZP_POS + x]
                while True:
                    a = m[(pptr + y) & 0xFFFF]
                    if not a & 0x80:
                        break
                    c = a & 0x0F
                    if c == 0:
                        y += 1; m[0xBDA6 + x] = m[pptr + y]
                    elif c == 1:
                        y += 1; m[0xBDB2 + x] = m[pptr + y]; m[0xBDAF + x] = 1
                    elif c == 2:
                        m[0xBDAF + x] = 0
                    elif c == 3:
                        y += 1; m[0xBDA0 + x] = m[pptr + y]
                    elif c == 4:
                        m[0xBDAC + x] = 0x80
                    elif c == 5:
                        m[0xBDAC + x] = 0xA0
                    elif c == 6:
                        m[0xBDB9 + x] = 1
                    elif c == 7:
                        m[0xBDB9 + x] = 0
                    y += 1
                m[0xBD9D + x] = a
                m[ZP_DUR + x] = m[0xBD67 + (a & 0x1F)]
                y += 1
                m[ZP_POS + x] = y
                note = (m[pptr + y] + m[0xBDA0 + x]) & 0xFF
                m[ZP_NOTE + x] = note
                m[0xBDA3 + x] = m[0xBD6C + note]
                self.audf[x] = m[0xBDA3 + x]
                w.append((2 * x, self.audf[x]))
                m[0xBDA9 + x] = 0
                m[ZP_POS + x] = (m[ZP_POS + x] + 1) & 0xFF
                if m[(pptr + m[ZP_POS + x]) & 0xFFFF] == 0xFF:
                    m[ZP_POS + x] = 0
                    m[ZP_ORD + x] = (m[ZP_ORD + x] + 1) & 0xFF
            # envelope
            ins = m[0xBDA6 + x]
            eptr = m[0xBDC6 + ins] | m[0xBDCC + ins] << 8
            e = m[eptr + m[0xBDA9 + x]]
            if e != 0xFF:
                m[0xBDA9 + x] = (m[0xBDA9 + x] + 1) & 0xFF
                self.audc[x] = e | m[0xBDAC + x]
                w.append((2 * x + 1, self.audc[x]))
            # flicker
            if m[0xBDAF + x]:
                amt = m[0xBDB2 + x] if not (m[0xBD9A] & 1) else 0
                self.audf[x] = m[0xBD6C + ((m[ZP_NOTE + x] - amt) & 0xFF)]
                w.append((2 * x, self.audf[x]))
            # arpeggio
            if m[0xBDB9 + x]:
                while True:
                    i = m[0xBDB6 + x]
                    m[0xBDB6 + x] = (i + 1) & 0xFF
                    v = m[0xBDBD + i]
                    if v == 0x1F:
                        m[0xBDB6 + x] = 0
                        continue
                    break
                self.audf[x] = (v + m[0xBDA3 + x]) & 0xFF
                w.append((2 * x, self.audf[x]))
            m[ZP_DUR + x] = (m[ZP_DUR + x] - 1) & 0xFF
        return list(self.audf), list(self.audc)


def log_states(path):
    from collections import defaultdict
    ev = defaultdict(list)
    for line in open(path):
        p = line.split()
        ev[int(p[0])].append((int(p[1], 16), int(p[2], 16)))
    st = [0] * 9
    out = []
    for f in range(max(ev) + 1):
        for a, v in ev.get(f, []):
            st[a] = v
        out.append(list(st))
    return out


def main():
    mem = open(sys.argv[1], 'rb').read()
    log = log_states(sys.argv[2])
    start = int(sys.argv[3])
    n = int(sys.argv[4]) if len(sys.argv) > 4 else min(3072, len(log) - start - 1)
    d = Driver(mem)
    # registers the driver last wrote, from the log at START_FRAME
    # the dump is taken at frame_done, before that frame's VBI writes reach the log:
    # model step k corresponds to log frame START + k - 1
    s0 = start - 1
    d.audf = [log[s0][0], log[s0][2], log[s0][4]]
    d.audc = [log[s0][1], log[s0][3], log[s0][5]]
    bad = 0
    for k in range(1, n + 1):
        f, c = d.frame()
        r = log[s0 + k]
        want = ([r[0], r[2], r[4]], [r[1], r[3], r[5]])
        if (f, c) != want:
            bad += 1
            if bad <= 10:
                print(f'frame {s0 + k}: model AUDF {f} AUDC {[hex(x) for x in c]} | log AUDF {want[0]} AUDC {[hex(x) for x in want[1]]}')
    print(f'{n} frames compared, {bad} differ')


if __name__ == '__main__':
    main()
