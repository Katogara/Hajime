"""素体と「服を着せた全身」の違いから、服の部分だけを透過 PNG で取り出す。

使い方: extract_diff.py 素体.jpg 着せた絵.jpg 出力.png [確認用の重ね合わせ.png]
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

base = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(int)
worn_img = Image.open(sys.argv[2]).convert("RGB")
worn = np.asarray(worn_img).astype(int)
r, g, b = worn[..., 0], worn[..., 1], worn[..., 2]
magenta = (r > 170) & (b > 170) & (g < 110) & (abs(r - b) < 90)

diff = np.abs(worn - base).sum(-1) > 90
mask = Image.fromarray((diff & ~magenta).astype(np.uint8) * 255)
# 小さな点を消し、線の切れ目を埋める
mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(3))
m = np.asarray(mask) > 0
m &= ~magenta

ys, xs = np.nonzero(m)
print("bbox", xs.min(), ys.min(), xs.max(), ys.max(), "pixels", m.sum())
rgba = np.dstack([worn, np.where(m, 255, 0)]).astype(np.uint8)
Image.fromarray(rgba, "RGBA").save(sys.argv[3])

if len(sys.argv) > 4:
    bg = Image.new("RGBA", worn_img.size, "#FFF8EE")
    b_rgba = np.dstack([base, np.where(
        (base[..., 0] > 170) & (base[..., 2] > 170) & (base[..., 1] < 110), 0, 255)]).astype(np.uint8)
    bg.alpha_composite(Image.fromarray(b_rgba, "RGBA"))
    bg.alpha_composite(Image.fromarray(rgba, "RGBA"))
    bg.convert("RGB").save(sys.argv[4])
