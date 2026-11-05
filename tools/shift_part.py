"""取り出した部品の一部の行だけを切り出し、足元を素体にそろえて上下に動かす。

使い方: python -P tools/shift_part.py 部品.png 素体.jpg 出力.png --rows 792 1024
AI が靴を元より大きく描くと、靴底が素体の足元より下に出る。部品の下端を素体の下端（背景でない最も下の行）に合わせる。
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from to_svg import background  # noqa: E402

p = argparse.ArgumentParser()
p.add_argument("part")
p.add_argument("base")
p.add_argument("out")
p.add_argument("--rows", type=int, nargs=2, required=True)
a = p.parse_args()

img = np.asarray(Image.open(a.part).convert("RGBA")).copy()
lo, hi = a.rows
img[:lo, :, 3] = 0
img[hi:, :, 3] = 0
ys = np.nonzero((img[..., 3] > 128).any(axis=1))[0]
base = np.asarray(Image.open(a.base).convert("RGB")).astype(int)
base_ys = np.nonzero((~background(base)).any(axis=1))[0]
dy = int(base_ys.max() - ys.max())
out = np.zeros_like(img)
if dy < 0:
    out[:dy] = img[-dy:]
else:
    out[dy:] = img[:img.shape[0] - dy]
Image.fromarray(out).save(a.out)
print(f"部品の下端 {ys.max()}、素体の下端 {base_ys.max()}、{dy:+d}px 動かした")
