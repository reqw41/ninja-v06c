#!/usr/bin/env python3
"""Compare the Vector sound driver (tools/sndcheck.js output) with the Atari model tools/atari/sound.py.

  node tools/sndcheck.js N "plan" > build/tmp/snd.json && python3 tools/atari/sndcheck.py build/tmp/snd.json

The model starts from the Atari dump (build/a8run/full/mem2250.bin) with the song driver area from
data/music/atari_bc00.bin and the Vector start state (song restart, no whistle, no tick, $CC = $FF); events are
the Atari routines $249F/$24B6/$24D6 and the variables they set; RANDOM values are the ones the Vector took.
The score tick's SBC carry comes from Atari game code ($255D), the Vector uses 1: AUDF4 may differ by 1.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sound import Sound  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')


def main():
    runs = json.load(open(sys.argv[1]))
    mem = bytearray(open(os.path.join(ROOT, 'build/a8run/full/mem2250.bin'), 'rb').read())
    mem[0xBC00:0xC000] = open(os.path.join(ROOT, 'data/music/atari_bc00.bin'), 'rb').read()
    mem[0x2405:0x2418] = bytes.fromhex('5b0051483c352d00000000fe010110141c0000')
    mem[0x24E4:0x24EA] = bytes.fromhex('000000000100')
    for a in range(0x84, 0x90):
        mem[a] = 0
    mem[0xBDBC] = 0x40; mem[0x9F5A] = 0; mem[0x9F5B] = 1; mem[0xCC] = 0xFF; mem[0x14] = 0
    s = Sound(bytes(mem)); m = s.m
    pk = [0] * 9
    bad = 0
    for r in runs:
        for e in r['ev']:
            if e == 'cc0': m[0xCC] = 0
            elif e == 'ccff': m[0xCC] = 0xFF
            elif e in ('sw0', 'sw1', 'hit0', 'hit1'):
                x = int(e[-1])
                if e.startswith('sw'):
                    m[0x2410 + x] = 1; m[0x240D + x] = 1; pk[2 * x + 1] = 2 * x; pk[2 * x] = m[0x2413 + x]
                else:
                    m[0x2410 + x] = 0xFE; m[0x240D + x] = 0x10; pk[2 * x + 1] = 2 * x; pk[2 * x] = 0x40
                m[0x24E8] = 1; m[0x24E6] = 0
            elif e == 'ko': m[0x9F5A] = 40
            elif e == 'idol': m[0x9F5A] = 200; m[0x2416] = 0x0F
            elif e == 'room':
                m[0x2417] = 0x3F
                for a in range(1, 9): pk[a] = 0
        m[0x14] = (m[0x14] + 1) & 0xFF
        it = iter(r['rnd'])
        for a, v in s.vbi(lambda: next(it)):
            pk[a] = v
        left = list(it)
        vec = r['pk']
        diff = [i for i in range(9) if pk[i] != vec[i] and not (i == 6 and (pk[i] - vec[i]) & 0xFF in (1, 0xFF))]
        if diff or left:
            bad += 1
            if bad <= 8:
                print(f"вызов {r['n']} {r['ev']}: модель {[hex(x) for x in pk]} Вектор {[hex(x) for x in vec]}" + (f' лишних RANDOM {len(left)}' if left else ''))
            pk = list(vec)                  # дальше — с состояния Вектора по регистрам
    print(f'{len(runs)} вызовов, расхождений {bad}')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
