#!/usr/bin/env python3
"""Сравнение звуков по спектру (владелец 15.11: «подобрать через анализ звука»): по окнам 50 мс — уровень (дБ),
центр спектра (Гц), тональность (пик / среднее в полосе 200–8000 Гц, дБ: больше — слышен тон, «вой»).
  python3.11 -I tools/sfxana.py эталон.wav вариант.wav ...  (первый — эталон; в конце — расстояние до эталона)"""
import sys, wave
import numpy as np


def load(p):
    w = wave.open(p); r = w.getframerate(); d = np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(float)
    if w.getnchannels() > 1: d = d[::w.getnchannels()]
    return r, d / 32768


def feats(p):
    r, a = load(p)
    n = int(r * 0.05); out = []
    win = np.hanning(n)
    for i in range(0, len(a) - n, n):
        x = a[i:i + n] * win
        rms = np.sqrt(np.mean(a[i:i + n] ** 2)) + 1e-9
        s = np.abs(np.fft.rfft(x)) ** 2; f = np.fft.rfftfreq(n, 1 / r)
        band = (f > 200) & (f < 8000)
        sb = s[band]; fb = f[band]
        cen = (sb * fb).sum() / (sb.sum() + 1e-12)
        ton = 10 * np.log10(sb.max() / (sb.mean() + 1e-12) + 1e-12)
        out.append((20 * np.log10(rms), cen, ton))
    return np.array(out)


ref = feats(sys.argv[1])
alive = ref[:, 0] > ref[:, 0].max() - 40
print(f'{"файл":28s} ' + ' '.join(f'{k:>5d}' for k in range(len(ref)))[:0])
for p in sys.argv[1:]:
    F = feats(p)
    m = min(len(F), len(ref))
    print(p.split('/')[-1])
    for name, j, fmt in (('дБ', 0, '{:5.0f}'), ('центр', 1, '{:5.0f}'), ('тон', 2, '{:5.1f}')):
        print(f'  {name:6s}', ' '.join(fmt.format(v) for v in F[:min(m, 20), j]))
    al = alive[:m]
    lv = F[:m, 0] - F[:m, 0][al].max(); lr = ref[:m, 0] - ref[:m, 0][al].max()
    d_lvl = np.sqrt(np.mean((lv[al] - lr[al]) ** 2))
    d_cen = np.sqrt(np.mean((np.log2(F[:m, 1][al] / ref[:m, 1][al])) ** 2))
    d_ton = np.mean(F[:m, 2][al] - ref[:m, 2][al])
    print(f'  -> огибающая {d_lvl:.1f} дБ, высота {d_cen:.2f} окт, тональность {d_ton:+.1f} дБ')
