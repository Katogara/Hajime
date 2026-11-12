"""手に持つ小物を、小物だけを描いた絵から切り抜き、立ち姿のアバターの右手 (見る人の右) に置く。

使い方: python -P tools/place_item.py 小物の絵.jpg 出力.png --height H [--grip GX GY] [--deg D] [--at X Y]

- 小物の絵: Gemini に「小物だけを、背景はマゼンタで」描かせたもの (羽子板 gen/n01_hagoita と同じ作り方)
- --height: 置いたときの小物の高さ (1024 のキャンバスで px)
- --grip: 小物のうち、手で握るところ (小物の外接枠の中の割合。0〜1。既定は下の真ん中 0.5 0.9)
- --deg: 時計回りの回転 (度)
- --at: 握るところを置く位置 (既定は素体の右手の真ん中 632 552。parts3/std_hands.png の右手のかたまりの中心)

手の小物は大喜びのポーズでは出さないので、立ち姿だけに合わせればよい (Costumes.swift)。
Costumes.json で "grip": true にすると素体の手より後ろに描かれ、手が握って見える。
2026-11-13、季節ものの手の小物 (豆の升・花見団子など) を作るために足した。Gemini は腕を下ろしたまま小物を持たせられないため
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).parent))
from to_svg import background, fringe_of  # noqa: E402

p = argparse.ArgumentParser()
p.add_argument("src")
p.add_argument("out")
p.add_argument("--height", type=float, required=True)
p.add_argument("--grip", type=float, nargs=2, default=[0.5, 0.9])
p.add_argument("--deg", type=float, default=0)
p.add_argument("--at", type=float, nargs=2, default=[632, 552])
p.add_argument("--crop", type=int, nargs=4, help="元の絵から切り出す範囲 x0 y0 x1 y1 (2×2 に並べて描かせた絵から 1 つ取るとき)")
p.add_argument("--flip", action="store_true", help="左右を反転する")
a = p.parse_args()

src = Image.open(a.src).convert("RGB")
if a.crop:
    src = src.crop(tuple(a.crop))
if a.flip:
    src = src.transpose(Image.FLIP_LEFT_RIGHT)
img = np.asarray(src).astype(int)
mag = background(img)
fr = fringe_of(img, mag, strength=70)
keep = ~mag & ~fr
lab, n = ndimage.label(keep)
if n:
    sizes = ndimage.sum(keep, lab, range(1, n + 1))
    keep = np.isin(lab, [int(np.argmax(sizes)) + 1])  # いちばん大きい小物だけ
keep = ndimage.binary_fill_holes(keep)
# Gemini がステッカーの白いふちを付けることがある (アプリで白ふちを付けるので二重になる)。外側から白い点をはがす
white = img.mean(-1) > 200  # 白いふちと、ふちにまじったマゼンタのにじみ。内側はこげ茶の線で止まる
for _ in range(40):
    edge = keep & ~ndimage.binary_erosion(keep)
    peel = edge & white
    if not peel.any():
        break
    keep &= ~peel
rgba = np.dstack([img.astype(np.uint8), (keep * 255).astype(np.uint8)])
ys, xs = np.nonzero(keep)
x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
item = Image.fromarray(rgba[y0:y1, x0:x1])
gx, gy = a.grip[0] * (x1 - x0), a.grip[1] * (y1 - y0)
s = a.height / (y1 - y0)
item = item.resize((max(1, round((x1 - x0) * s)), max(1, round((y1 - y0) * s))), Image.LANCZOS)
gx, gy = gx * s, gy * s
# 握るところを中心に回す: 大きなキャンバスの真ん中に握るところを置いてから回す
W = 2048
big = Image.new("RGBA", (W, W), (0, 0, 0, 0))
big.paste(item, (round(W / 2 - gx), round(W / 2 - gy)))
big = big.rotate(-a.deg, resample=Image.BICUBIC, center=(W / 2, W / 2))
out = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
out.paste(big, (round(a.at[0] - W / 2), round(a.at[1] - W / 2)), big)
arr = np.asarray(out).copy()
arr[..., 3] = np.where(arr[..., 3] > 128, 255, 0)
Image.fromarray(arr).save(a.out)
ys, xs = np.nonzero(arr[..., 3])
print(f"{a.out}: x {xs.min()}-{xs.max()} y {ys.min()}-{ys.max()}")
