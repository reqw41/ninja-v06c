#!/usr/bin/env python3
"""Preview of the Atari Ninja music as the Vector-06C would play it (3 x VI53 + speaker).

  python3 tools/atari/vi53_preview.py build/a8run/s/mem.bin [--slow]

Scheme (docs/MUSIC.md, owner 14.11.2026: all 3 VI53 counters for music):
  - the original driver (tools/atari/music.py) is stepped 6 times per 5 Vector frames
    (60 Hz tempo at 50 Hz), or once per frame with --slow;
  - counter = POKEY channel: divisor (AUDF+1)*47 at 1.5 MHz (POKEY 63.92 kHz / 2 / (AUDF+1),
    error 0.15 %); VI53 has no volume: the voice sounds while the envelope volume > 0;
  - distortion 8 (noise): that counter is silent, random bits go to the speaker at the
    channel's rate (as Bruce Lee does noise); distortion C is played as a tone;
  - output = sum of three square waves + speaker bit, equal weights.
Writes data/music/ninja_vi53.wav (one loop).
"""
import os
import random
import struct
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from music import Driver  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
VI53_CLOCK = 1_500_000
RATE = 44100
CALLS = 3072


def main():
    mem = open(sys.argv[1], 'rb').read()
    slow = '--slow' in sys.argv
    d = Driver(mem)
    frames = []            # per Vector frame: (divisors or None, noise rates)
    calls = 0
    acc = 0
    while calls < CALLS:
        acc += 6 if not slow else 5
        while acc >= 5 and calls < CALLS:
            acc -= 5
            f, c = d.frame()
            calls += 1
        voices = []
        for ch in range(3):
            vol, dist = c[ch] & 15, c[ch] >> 4
            if vol == 0:
                voices.append(None)
            elif dist == 8:
                voices.append(('noise', 63921.0 / (2 * (f[ch] + 1))))
            else:
                voices.append(('tone', VI53_CLOCK / ((f[ch] + 1) * 47)))
        frames.append(voices)
    spf = RATE / 50.0
    phase = [0.0] * 3
    lvl = [1, 1, 1]
    spk = 1
    rnd = random.Random(7)
    out = bytearray()
    acc = 0.0
    for voices in frames:
        acc += spf
        n = int(acc)
        acc -= n
        for _ in range(n):
            s = 0
            for ch, v in enumerate(voices):
                if v is None:
                    continue
                kind, fr = v
                step = fr / RATE * (2 if kind == 'tone' else 1)
                phase[ch] += step
                if phase[ch] >= 1:
                    phase[ch] -= int(phase[ch])
                    if kind == 'tone':
                        lvl[ch] ^= 1
                    else:
                        spk = rnd.getrandbits(1)
                if kind == 'tone':
                    s += 1 if lvl[ch] else -1
                else:
                    s += 1 if spk else -1
            out += struct.pack('<h', int(s * 7000))
    name = 'ninja_vi53_slow.wav' if slow else 'ninja_vi53.wav'
    path = os.path.join(ROOT, 'data', 'music', name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(bytes(out))
    print(f'{len(frames)} Vector frames ({len(frames) / 50:.1f} s) -> {path}')


if __name__ == '__main__':
    main()
