#!/usr/bin/env python3
"""Варианты звука входа в комнату с бойцом для ВИ53 (владелец 15.11: «подберём»): WAV для прослушивания.
Модель: 3 счётчика ВИ53 по 1,5 МГц, режим 3 (меандр), выходы складываются; делитель обновляется 50 раз в секунду
(прерывание), драйвер Atari — 6 вызовов на 5 кадров. Atari: AUDF канала 3 от $3E до 0 по вызову (шум), канал 4 —
AUDF $A0 (4-битный полином).  python3 -I tools/sfxpreview.py -> build/sfx/*.wav"""
import math, os, random, struct, wave
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SR, CLK = 48000, 1500000


def render(name, frames):
    """frames: список кадров (50 Гц), в каждом — делители трёх каналов (0 — тишина)"""
    out = []
    ph = [0.0, 0.0, 0.0]
    spf = SR // 50
    for divs in frames:
        for _ in range(spf):
            v = 0
            for k, dv in enumerate(divs):
                if dv:
                    ph[k] = (ph[k] + CLK / dv / SR) % 1.0
                    v += 1 if ph[k] < 0.5 else -1
            out.append(int(v * 6000))
    out += [0] * (SR // 2)
    w = wave.open(os.path.join(ROOT, 'build/sfx', name), 'wb')
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', s) for s in out))
    w.close()


def whistle_calls():
    """AUDF канала 3 по кадрам 50 Гц (63 вызова Atari на 60 Гц ≈ 52 кадра)"""
    res, v, acc = [], 0x3F, 0
    while v > 0:
        acc += 6
        while acc >= 5 and v > 0:
            acc -= 5; v -= 1
        res.append(v)
    return res


random.seed(1)
W = whistle_calls()
render('1_tone_whistle_buzz.wav', [(0, 0, (a + 1) * 47 if a else 0) if False else ((a + 1) * 47 * 4, 0, 0xA1 * 47) for a in W])
render('2_tone_whistle.wav', [((a + 1) * 47 * 4, 0, 0) for a in W])
render('3_noisy_whistle.wav', [(int((a + 1) * 47 * 4 * random.uniform(0.6, 1.4)), int((a + 1) * 47 * 6 * random.uniform(0.6, 1.4)), 0) for a in W])
render('4_short_chirp.wav', [(int(3000 / (1 + 0.25 * i)), 0, 0) for i in range(12)])
render('5_two_notes.wav', [(1500 * 2, 0, 0)] * 6 + [(1125 * 2, 0, 0)] * 10)
print('build/sfx: 0_atari_entry.wav (оригинал), 1..5 — варианты')
