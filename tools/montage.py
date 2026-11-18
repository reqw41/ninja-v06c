#!/usr/bin/env python3
"""Tile PNG screenshots into one image with frame labels: montage.py OUT.png IN..."""
import sys
from PIL import Image, ImageDraw
out, files = sys.argv[1], sys.argv[2:]
cols = 4
ims = [Image.open(f).convert('RGB') for f in files]
w, h = ims[0].size
M = Image.new('RGB', (cols * w, ((len(ims) + cols - 1) // cols) * (h + 12)), 'white')
d = ImageDraw.Draw(M)
for i, (f, im) in enumerate(zip(files, ims)):
    x, y = (i % cols) * w, (i // cols) * (h + 12)
    M.paste(im, (x, y + 12))
    d.text((x + 2, y), f.rsplit('/', 1)[-1], fill='black')
M.save(out)
