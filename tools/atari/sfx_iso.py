#!/usr/bin/env python3
"""Звуки Atari Ninja по коду игры, каждый отдельно (владелец 15.11: «не захватом, а по коду»).

Модель звукового VBI — tools/atari/sound.py (сверена с MAME: 0 расхождений). Здесь она запускается на чистой
памяти (песня выключена $CC = $FF, все эффекты и подыгрывание погашены, $14 не доходит до 0 — случайного свиста
нет), событие запускается так же, как его запускает код игры, и поток записей POKEY проигрывается простым
синтезатором POKEY (64 кГц, полиномы 4/5/17, AUDCTL = 0) в отдельный WAV.

  python3 -I tools/atari/sfx_iso.py build/a8run/full/mem2250.bin   -> build/sfx/atari_code/*.wav + журнал записей

События (адрес вызова в игре -> что делает код):
  $2054  удар/замах героя        $249F X=0: шум (AUDC = громкость, искажение 0), громкость 1..5..0, AUDF = громк. + $10
  $23AB  замах врага             $249F X=1/2: то же, AUDF база $14 / $1C
  $2642  бросок оружия           $249F X=боец
  $1A27  попадание оружием       $24B6 X=0: шум с громкости 16 шагом -2, первый AUDF $40, далее громк. + база
  $1AC9  попадание ударом        $24B6 X=$F6 (тот, кто бьёт)
  $1DE2  враг повержен ($1DC7)   $9F5A = $1DC4[тип]: 40/80/60/140 тиков; тик: AUDF4 = $60 - n, AUDC4 = $C4 (полином 4)
  $2CC6  идол взят               $2416 = $0F (AUDC1 = $A0|n — чистый тон, AUDF1 = 8, 15 кадров) + $9F5A = 200 тиков
  $1655  вход в комнату          $2417 = $3F свист (AUDF3 = n шум громк. n>>3, AUDC4 = $C0|n>>3, AUDF4 = $A0) + $24D6
  $2449  случайный свист в бою   раз в 256 кадров с вероятностью 1/4: $2417 = $40
  $24EA  подыгрывание            пока $24E8 < 0: случайное блуждание по нотам $2405, чистый тон громк. 0..2
"""
import os
import struct
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sound import Sound  # noqa: E402

CPU = 1789773            # NTSC (образ US, a800xl)
FPS = 60
SR = 44100
DIV64 = 28               # 64 кГц = CPU / 28


def polys():
    def lfsr(bits, taps, n):
        s, out = (1 << bits) - 1, []
        for _ in range(n):
            out.append(s & 1)
            fb = 0
            for t in taps:
                fb ^= (s >> t) & 1
            s = (s >> 1) | (fb << (bits - 1))
        return out
    return lfsr(4, (0, 1), 15), lfsr(5, (0, 2), 31), lfsr(17, (0, 5), 131071)


P4, P5, P17 = polys()


def synth(frames):
    """frames: список кадров, в каждом — записи [(reg 0..8, value)]; возвращает 16-битные отсчёты"""
    audf, audc = [0] * 4, [0] * 4
    nxt = [0] * 4            # такт следующего срабатывания делителя
    lvl = [0] * 4
    out = []
    cyc_per_frame = CPU // FPS
    t = 0
    smp_t = 0.0
    step = CPU / SR
    for w in frames:
        for r, v in w:
            if r < 8:
                ch = r >> 1
                if r & 1:
                    audc[ch] = v
                else:
                    audf[ch] = v
        end = t + cyc_per_frame
        while smp_t < end:
            ts = int(smp_t)
            acc = 0
            for ch in range(4):
                c = audc[ch]
                if nxt[ch] < t - 100000:
                    nxt[ch] = t
                while nxt[ch] <= ts:
                    e = nxt[ch]
                    nxt[ch] += (audf[ch] + 1) * DIV64
                    if not c & 0x80 and not P5[e % 31]:
                        continue                         # тактирование через 5-битный полином
                    if c & 0x20:
                        lvl[ch] ^= 1                     # чистый тон
                    elif c & 0x40:
                        lvl[ch] = P4[e % 15]
                    else:
                        lvl[ch] = P17[e % 131071]
                vol = c & 15
                if c & 0x10:
                    acc += vol
                else:
                    acc += vol * lvl[ch]
            out.append(acc)
            smp_t += step
        t = end
    # убрать постоянную составляющую фильтром (как ёмкость на выходе)
    res, y, xp = [], 0.0, 0
    for x in out:
        y = 0.995 * (y + x - xp)
        xp = x
        res.append(max(-32767, min(32767, int(y * 900))))
    return res


def save(path, smp):
    smp = smp + [0] * (SR // 3)
    with wave.open(path, 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes(b''.join(struct.pack('<h', s) for s in smp))


class Iso:
    def __init__(self, mem):
        self.s = Sound(mem)
        m = self.s.m
        m[0xCC] = 0xFF
        m[0x14] = 1
        for a in (0x2416, 0x2417, 0x240D, 0x240E, 0x240F, 0x24E5, 0x24E6, 0x9F5A, 0x9F46):
            m[a] = 0
        m[0x24E8] = 1            # подыгрывание стоит
        m[0x24E7] = 0
        import random
        self.rng = random.Random(1986)
        self.frames = []          # записи по кадрам
        self.pending = []         # записи кода игры (между VBI)

    def rnd(self):
        # RANDOM POKEY — старшие биты 17-битного полинома, читаются в случайный момент: биты независимы
        # (простой ГСЧ со «шагом» давал всё время одну ноту подыгрывания)
        return self.rng.getrandbits(8)

    # ---- то, что делает код игры ----
    def g249f(self, x):          # всплеск шума
        m = self.s.m
        m[0x2410 + x] = 1; m[0x240D + x] = 1
        self.pending += [(2 * x + 1, 2 * x), (2 * x, m[0x2413 + x])]
        self.g24cb()

    def g24b6(self, x):          # удар: затухающий шум
        m = self.s.m
        m[0x2410 + x] = 0xFE; m[0x240D + x] = 0x10
        self.pending += [(2 * x + 1, 2 * x), (2 * x, 0x40)]
        self.g24cb()

    def g24cb(self):
        self.s.m[0x24E8] = 1; self.s.m[0x24E6] = 0

    def g24d6(self):
        self.pending += [(8, 0)] + [(a, 0) for a in range(7, -1, -1)]

    def run(self, n, keep_rt=True):
        for _ in range(n):
            m = self.s.m
            w = self.pending + self.s.vbi(self.rnd, True, False)
            self.pending = []
            self.frames.append(w)
            if keep_rt:
                m[0x14] = 1
            else:
                m[0x14] = (m[0x14] + 1) & 0xFF


def scenario(mem, name):
    z = Iso(mem)
    m = z.s.m
    if name == 'swing_hero':
        z.g249f(0); z.run(20)
    elif name == 'swing_enemy1':
        z.g249f(1); z.run(20)
    elif name == 'swing_enemy2':
        z.g249f(2); z.run(20)
    elif name == 'hit':
        z.g24b6(0); z.run(20)
    elif name == 'hit_enemy':
        z.g24b6(1); z.run(20)
    elif name.startswith('ko'):
        typ = int(name[-1])
        z.g24b6(0); m[0x9F5A] = m[0x1DC4 + typ]; z.run(m[0x1DC4 + typ] + 10)
    elif name == 'idol_chime':
        m[0x2416] = 0x0F; z.run(20)
    elif name == 'idol_ticks':
        m[0x9F5A] = 200; z.run(210)
    elif name == 'idol':
        m[0x2416] = 0x0F; m[0x9F5A] = 200; z.run(210)
    elif name == 'whistle_room':
        m[0x2417] = 0x3F; z.g24d6(); z.run(70)
    elif name == 'whistle_rand':
        m[0x2417] = 0x40; z.g24cb(); z.run(70)
    elif name == 'ambient':
        m[0x24E8] = 0xFF; z.run(FPS * 12)
    elif name == 'fight_combo':
        # замах героя, через 10 кадров замах врага, попадание, ещё раз замах
        z.g249f(0); z.run(10); z.g249f(1); z.run(12); z.g24b6(0); z.run(14); z.g249f(0); z.run(20)
    return z.frames


NAMES = ['swing_hero', 'swing_enemy1', 'swing_enemy2', 'hit', 'hit_enemy', 'ko_t0', 'ko_t1', 'ko_t2', 'ko_t3',
         'idol_chime', 'idol_ticks', 'idol', 'whistle_room', 'whistle_rand', 'ambient', 'fight_combo']


def main():
    mem = open(sys.argv[1], 'rb').read()
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
    od = os.path.join(root, 'build/sfx/atari_code')
    os.makedirs(od, exist_ok=True)
    names = sys.argv[2:] or NAMES
    with open(os.path.join(od, 'writes.txt'), 'w') as log:
        for i, n in enumerate(names):
            fr = scenario(mem, n)
            last = max((k for k, w in enumerate(fr) if any(r < 8 and r & 1 and v & 15 for r, v in w)), default=0)
            log.write(f'== {n}: {len(fr)} кадров, последний звучащий {last} ({(last + 1) / FPS:.2f} с)\n')
            for k, w in enumerate(fr[:last + 2]):
                if w:
                    log.write(f'  {k:3d}: ' + ' '.join(f'{"FC"[r & 1] if r < 8 else "X"}{(r >> 1) + 1}={v:02X}'
                                                   for r, v in w) + '\n')
            save(os.path.join(od, f'{i:02d}_{n}.wav'), synth(fr))
            print(f'{n}: {(last + 1) / FPS:.2f} с')


if __name__ == '__main__':
    main()
