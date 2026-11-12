"""Gemini が素体の位置や大きさを変えて描いた絵を、素体に重なるよう拡大・移動し直す。

使い方: python -P tools/align_to_base.py 素体.jpg 着せた絵.jpg 出力.jpg [--ignore-top Y]

- シルエット (マゼンタ以外) の重なり (IoU) がいちばん大きくなる倍率と位置を探す
- 小物が足された頭の上や首は形が変わるので、素体のシルエットのうち y < ignore-top の行は比べない
- 出力は 1024x1024 で、はみ出した余白はマゼンタで埋める (extract_part.py にそのまま渡せる)

2026-11-13、ひなまつりのワンのすけ (gen/w24) が元の絵より大きく左に描かれたので足した
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).parent))
from to_svg import background  # noqa: E402

p = argparse.ArgumentParser()
p.add_argument("base")
p.add_argument("worn")
p.add_argument("out")
p.add_argument("--ignore-top", type=int, default=0)
a = p.parse_args()

S = 256  # 粗く探すときの大きさ
base = np.asarray(Image.open(a.base).convert("RGB")).astype(int)
worn_img = Image.open(a.worn).convert("RGB")
worn = np.asarray(worn_img).astype(int)
bm = ~background(base)
wm = ~background(worn)


def small(m):
    return np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize((S, S), Image.BILINEAR)) > 127


bs, ws = small(bm), small(wm)
k = S / 1024
use = np.ones_like(bs)
use[: int(a.ignore_top * k)] = False


def score(s, dx, dy):
    """倍率 s で拡大し (dx, dy) だけ動かした worn と base の重なり"""
    m = ndimage.affine_transform(ws.astype(float), [1 / s, 1 / s], offset=[-dy / s, -dx / s], order=0) > 0.5
    inter = (m & bs & use).sum()
    union = ((m | bs) & use).sum()
    return inter / max(union, 1)


# worn の外接枠と base の外接枠から最初の見当を付け、まわりを探す
def box(m):
    ys, xs = np.nonzero(m)
    return xs.min(), xs.max(), ys.min(), ys.max()


bx0, bx1, by0, by1 = box(bs)
wx0, wx1, wy0, wy1 = box(ws)
s0 = (by1 - by0) / max(wy1 - wy0, 1)
best = (-1, 1, 0, 0)
for s in np.linspace(s0 * 0.85, s0 * 1.15, 13):
    cx = (bx0 + bx1) / 2 - s * (wx0 + wx1) / 2
    cy = by1 - s * wy1
    for dx in np.arange(cx - 12, cx + 13, 2):
        for dy in np.arange(cy - 12, cy + 13, 2):
            v = score(s, dx, dy)
            if v > best[0]:
                best = (v, s, dx, dy)
# 細かく詰める
v, s, dx, dy = best
for ds in np.linspace(-0.02, 0.02, 5):
    for ddx in (-1, -0.5, 0, 0.5, 1):
        for ddy in (-1, -0.5, 0, 0.5, 1):
            w = score(s + ds, dx + ddx, dy + ddy)
            if w > best[0]:
                best = (w, s + ds, dx + ddx, dy + ddy)
v, s, dx, dy = best
DX, DY = dx / k, dy / k
out = Image.new("RGB", (1024, 1024), (255, 0, 255))
big = worn_img.resize((round(1024 * s), round(1024 * s)), Image.LANCZOS)
out.paste(big, (round(DX), round(DY)))
out.save(a.out, quality=97)
print(f"IoU {v:.3f} scale {s:.3f} offset {DX:.0f},{DY:.0f} -> {a.out}")
