"""素体と「着せた絵」から、服や小物だけを欠けなく取り出す（extract_diff.py の改良版）。

使い方:
  extract_part.py diff   素体.jpg 着せた絵.jpg 出力.png
  extract_part.py region 素体.jpg 着せた絵.jpg 出力.png --neck Y

diff:   素体との違いを取り、穴を埋め、すぐ外側のこげ茶の線を拾い直す（小物、重ね着）。
region: 首より下で、肌の色以外をすべて服として取る（上下とも取り替えた服）。
        首より上は diff と同じ（帽子など）。
どちらも、背景のマゼンタと、マゼンタがにじんだふちを透明にし、小さな点のごみを消す。
"""
import argparse

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

p = argparse.ArgumentParser()
p.add_argument("mode", choices=["diff", "region"])
p.add_argument("base")
p.add_argument("worn")
p.add_argument("out")
p.add_argument("--neck", type=int, default=0, help="region モードで、ここより下を服として扱う y")
p.add_argument("--line-reach", type=int, default=7, help="線を拾い直す幅（px）")
p.add_argument("--min-area", type=int, default=300, help="これより小さい点のかたまりは消す")
a = p.parse_args()

base = np.asarray(Image.open(a.base).convert("RGB")).astype(int)
worn = np.asarray(Image.open(a.worn).convert("RGB")).astype(int)
r, g, b = worn[..., 0], worn[..., 1], worn[..., 2]
magenta = (r > 170) & (b > 170) & (g < 110) & (abs(r - b) < 90)
fringe = ((r - g) > 70) & ((b - g) > 70)   # マゼンタがにじんだ色
figure = ~magenta
dark = worn.sum(-1) < 330                   # こげ茶の線
skin_ref = np.array([0xF3, 0xD3, 0xB8])
skin = np.linalg.norm(worn - skin_ref, axis=-1) < 38

diff = (np.abs(worn - base).sum(-1) > 90) & figure
diff = ndimage.binary_opening(diff, iterations=1)

if a.mode == "region":
    ys = np.arange(worn.shape[0])[:, None]
    below = (ys >= a.neck) & figure & ~skin
    above = (ys < a.neck) & diff
    mask = below | above
else:
    mask = diff

mask = ndimage.binary_closing(mask, iterations=3)
mask = ndimage.binary_fill_holes(mask)
# すぐ外側の線を拾い直す
near = ndimage.binary_dilation(mask, iterations=a.line_reach)
mask |= near & dark & figure
mask = ndimage.binary_fill_holes(mask)
mask &= figure & ~fringe

# 小さなかたまりを消す
lab, n = ndimage.label(mask)
if n:
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= a.min_area])
    mask &= keep

ys, xs = np.nonzero(mask)
print("bbox", xs.min(), ys.min(), xs.max(), ys.max(), "pixels", int(mask.sum()))
alpha = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
rgba = np.dstack([worn.astype(np.uint8), np.asarray(alpha)])
Image.fromarray(rgba, "RGBA").save(a.out)
