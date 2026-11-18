#!/usr/bin/env python3
"""Export the Atari Ninja music: driver+data, decoded song, per-frame registers, WAV.

  python3 tools/atari/export_music.py build/a8run/s/mem.bin

MEM.bin: 64K dump taken before the song starts (NINJA_DUMP=2250, see docs/MUSIC.md).
Writes data/music/: atari_bc00.bin (driver $BC00-$BFFF with song data), song.json (order
lists, patterns, tables), frames.txt (one loop, per frame AUDF1-3 AUDC1-3 at 60 Hz),
ninja_atari.wav (rough POKEY render of one loop).
"""
import json
import math
import os
import random
import struct
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from music import Driver  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
LOOP = 3072
CMD = {0: 'instrument', 1: 'flicker', 2: 'flicker_off', 3: 'transpose', 4: 'noise',
       5: 'tone', 6: 'arpeggio', 7: 'arpeggio_off'}
ARGS = {0, 1, 3}


def decode(mem):
    w = lambda lo, hi, i: mem[lo + i] | mem[hi + i] << 8
    orders = []
    for c in range(3):
        o, s = w(0xBDFC, 0xBDFF, c), []
        while mem[o] != 0xFF:
            s.append(mem[o]); o += 1
        orders.append(s)
    pats = []
    for n in range(11):
        p, ev = w(0xBE02, 0xBE0D, n), []
        while mem[p] != 0xFF:
            b = mem[p]
            if b & 0x80:
                c = b & 0x0F
                if c in ARGS:
                    ev.append([CMD[c], mem[p + 1]]); p += 2
                else:
                    ev.append([CMD[c]]); p += 1
            else:
                ev.append(['note', mem[0xBD67 + (b & 0x1F)], mem[p + 1]]); p += 2
        pats.append(ev)
    envs = []
    for i in range(6):
        p, e = w(0xBDC6, 0xBDCC, i), []
        while mem[p] != 0xFF:
            e.append(mem[p]); p += 1
        envs.append(e)
    arp, p = [], 0xBDBD
    while mem[p] != 0x1F:
        arp.append(mem[p]); p += 1
    return {'orders': orders, 'patterns': pats, 'envelopes': envs, 'arpeggio': arp,
            'durations': list(mem[0xBD67:0xBD6C]), 'audf_table': list(mem[0xBD6C:0xBD9A]),
            'loop_frames_60hz': LOOP}


def render(frames, path, rate=22050):
    clock = 63921.0
    phase = [0.0] * 3
    lvl = [1] * 3
    out = bytearray()
    spf = rate / 60.0
    acc = 0.0
    rnd = random.Random(1)
    for f, c in frames:
        acc += spf
        n = int(acc); acc -= n
        for _ in range(n):
            s = 0.0
            for ch in range(3):
                vol = c[ch] & 15
                if not vol:
                    continue
                fr = clock / (2 * (f[ch] + 1))
                phase[ch] += fr / rate
                if phase[ch] >= 1:
                    phase[ch] -= int(phase[ch])
                    lvl[ch] = rnd.choice((0, 1)) if (c[ch] >> 4) != 0xA else 1 - lvl[ch]
                s += (vol / 15.0) * (1 if lvl[ch] else -1)
            out += struct.pack('<h', int(s / 3 * 12000))
    with wave.open(path, 'wb') as wv:
        wv.setnchannels(1); wv.setsampwidth(2); wv.setframerate(rate)
        wv.writeframes(bytes(out))


def main():
    mem = open(sys.argv[1], 'rb').read()
    out = os.path.join(ROOT, 'data', 'music')
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, 'atari_bc00.bin'), 'wb').write(mem[0xBC00:0xC000])
    song = decode(mem)
    song['state_init'] = {'zp_80_8f': mem[0x80:0x90].hex(), 'bd9a_bdbc': mem[0xBD9A:0xBDBD].hex()}
    json.dump(song, open(os.path.join(out, 'song.json'), 'w'), indent=1)
    d = Driver(mem)
    frames = [d.frame() for _ in range(LOOP)]
    with open(os.path.join(out, 'frames.txt'), 'w') as fo:
        fo.write('# frame AUDF1 AUDF2 AUDF3 AUDC1 AUDC2 AUDC3 (60 Hz, one loop)\n')
        for i, (f, c) in enumerate(frames):
            fo.write(f'{i} ' + ' '.join(f'{x:02X}' for x in f + c) + '\n')
    render(frames * 2, os.path.join(out, 'ninja_atari.wav'))
    sz = sum(2 * len(p) for p in song['patterns'])
    print(f'orders {[len(o) for o in song["orders"]]}, patterns {len(song["patterns"])}, '
          f'envelopes {len(song["envelopes"])}, wav 2 loops ({2 * LOOP / 60:.0f} s)')


if __name__ == '__main__':
    main()
