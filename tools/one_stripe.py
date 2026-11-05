"""帯の小物の線を 1 本にする。帯の上下の真ん中 (高さの keep 割) 以外にある線の色を、帯の地の色に塗り直す。

使い方: python -P tools/one_stripe.py 部品.png 出力.png 線の色 地の色 [--keep 0.34]
Gemini は「黄の線 1 本」と頼んでも 2 本に描くことがあるため (スポーツMIX のワンのすけのヘッドバンド)。
"""
import argparse

import numpy as np
from PIL import Image

p = argparse.ArgumentParser()
p.add_argument("part")
p.add_argument("out")
p.add_argument("stripe")
p.add_argument("ground")
p.add_argument("--keep", type=float, default=0.34)
a = p.parse_args()


def rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)])


img = np.asarray(Image.open(a.part).convert("RGBA")).copy()
solid = img[..., 3] > 128
stripe = solid & (np.abs(img[..., :3].astype(int) - rgb(a.stripe)).sum(-1) < 120)
changed = 0
for x in range(img.shape[1]):
    ys = np.nonzero(solid[:, x])[0]
    if len(ys) < 4:
        continue
    top, bottom = ys.min(), ys.max()
    mid, half = (top + bottom) / 2, (bottom - top) * a.keep / 2
    for y in np.nonzero(stripe[:, x])[0]:
        if abs(y - mid) > half:
            img[y, x, :3] = rgb(a.ground)
            changed += 1
Image.fromarray(img).save(a.out)
print(f"{changed} 画素を地の色にした")
