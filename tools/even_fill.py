"""Gemini の絵の、近い 2 色 (白と薄いクリーム色など) のむらをならす。

使い方: python -P tools/even_fill.py 入力.jpg 出力.png [--colors #FEF7ED #FCE3BA] [--size 13] [--blue 198]

- 各画素を指定した色のどれかに近いか見て、近いものだけを対象にする (線やほかの色はそのまま)
- 対象の画素は、まわり size×size の対象の画素でいちばん多い色に塗り替える
- 2026-11-20、バンダナなしのプレゼントのポーズ (gen/r25) の顔と胸に、白とクリーム色の点々が出たので足した
"""
import argparse

import numpy as np
from PIL import Image
from scipy import ndimage


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)


p = argparse.ArgumentParser()
p.add_argument("src")
p.add_argument("out")
p.add_argument("--colors", nargs="+", default=["#FEF7ED", "#FCE3BA"])
p.add_argument("--size", type=int, default=13)
p.add_argument("--tol", type=float, default=40)
p.add_argument("--blue", type=float, help="青がこの値以上なら 1 色目、未満なら 2 色目とする (2 色のとき)")
a = p.parse_args()

im = np.asarray(Image.open(a.src).convert("RGB")).astype(float)
cols = np.stack([hex_rgb(c) for c in a.colors])
d = np.linalg.norm(im[..., None, :] - cols[None, None], axis=-1)
label = d.argmin(-1)
target = d.min(-1) < a.tol
if a.blue is not None:
    # 白と薄いクリーム色のちょうど中間で描かれた絵では、近い色で分けると画素ごとに揺れる。青の強さで分ける
    label = np.where(im[..., 2] >= a.blue, 0, 1)
counts = np.stack([ndimage.uniform_filter(((label == k) & target).astype(float), a.size)
                   for k in range(len(cols))], -1)
best = counts.argmax(-1)
out = im.copy()
out[target] = cols[best[target]]
changed = int((target & (best != label)).sum())
Image.fromarray(out.astype(np.uint8)).save(a.out)
print(f"{a.out}: {int(target.sum())} 画素のうち {changed} 画素を塗り替えた")
