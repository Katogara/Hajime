"""初期の服を着たアバターの全身を、部位ごとの透過 PNG に分ける。

使い方: split_avatar.py 全身.jpg 頭の形.png 出力の頭文字 [--face-only]
  頭の形.png は立ち姿の素体（gen/parts3/avatar_body.png）。どのポーズでも頭の位置は同じなので、これで頭を切り分ける
  出力: 頭文字_head.png（髪と顔を含む頭と首）、_hair.png（髪。面は #6B4428 に塗り直す）、_headbase.png（髪のない頭と首）、
        _face.png（顔のパーツ。肌で囲まれた目・眉・鼻・口・ほっぺ）、
        _hands.png（首と手。体の肌の部品で、服を替えても残す）、_top.png（スウェット）、_bottom.png（ズボン）、_feet.png（靴）
  --face-only は _face.png だけを作る（表情だけを変えた絵から顔を取るとき）

部位の見分け方: 青緑はスウェット、下のほうの白は靴、ベージュは大きなかたまりをズボン、離れた小さなかたまりを手とする。
線（こげ茶）とにじみは、いちばん近い部位に入れる。
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).parent))
from to_svg import figure_mask  # noqa: E402

SKIN = np.array([0xF3, 0xD3, 0xB8])
TEAL = np.array([75, 165, 150])

p = argparse.ArgumentParser()
p.add_argument("src")
p.add_argument("head")
p.add_argument("out")
p.add_argument("--face-only", action="store_true")
p.add_argument("--head-like", help="頭をこの PNG の範囲（少し広げる）に限る")
p.add_argument("--lashes-vs", help="男性の同じ表情の _face.png。渡すと、この顔との差からまつ毛を _lashes.png に取る")
a = p.parse_args()

solid, rgb = figure_mask(Image.open(a.src))
raw = np.asarray(Image.open(a.src).convert("RGB"))
head_shape = np.asarray(Image.open(a.head).convert("RGBA"))[..., 3] > 128

dist = lambda c: np.abs(rgb - c).sum(-1)  # noqa: E731
light = rgb.sum(-1) > 330
H, W = solid.shape
ys = np.arange(H)[:, None] * np.ones((1, W), int)

# 頭: 首の線（素体の頭の下端）より上で、スウェット以外の、顔の真ん中につながるかたまり。
# 髪型で頭の大きさが変わる（ボブは素体より大きい）ので、絵ごとに取る。上げた手は離れているので入らない
hy, hx = np.nonzero(head_shape)
cy, cx = int(hy.min() + (hy.max() - hy.min()) * 0.55), int(hx.mean())
lab, _ = ndimage.label(solid & (ys <= hy.max() + 2) & (dist(TEAL) >= 90))
head = lab == lab[cy, cx]
head = ndimage.binary_closing(head, iterations=2) & solid
if a.head_like:
    # 上げた手が髪にふれている絵（女性の大喜び）では、立ち姿の頭の範囲に限る
    like = np.asarray(Image.open(a.head_like).convert("RGBA"))[..., 3] > 128
    head &= ndimage.binary_dilation(like, iterations=6)


def save(mask, name):
    out = np.dstack([raw, np.where(mask, 255, 0)]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(f"{a.out}_{name}.png")
    yy, xx = np.nonzero(mask)
    box = f"{xx.min()},{yy.min()}-{xx.max()},{yy.max()}" if mask.any() else "-"
    print(f"{a.out}_{name}.png  {int(mask.sum())}px  {box}")


# 顔: 頭の中で、肌の色（とほっぺ）の範囲の穴を埋め、顔の真ん中を含むかたまり
skinish = head & ((dist(SKIN) < 60) | ((rgb[..., 0] > 200) & (rgb[..., 1] < 190) & (rgb[..., 1] > 120)))
filled = ndimage.binary_fill_holes(skinish)
lab, _ = ndimage.label(filled)
face =lab == lab[cy, cx] if lab[cy, cx] else np.zeros_like(filled)
save(face, "face")
if a.lashes_vs:
    # まつ毛: この顔の暗い線のうち、まつ毛のない同じ顔（--lashes-vs）の暗い線から 2px より離れたもの。
    # 男性の顔にまつ毛だけを描き足させた絵に使う（女性の顔は目の形も違うので、そのまま比べられない）
    other = np.asarray(Image.open(a.lashes_vs).convert("RGBA"))
    other_dark = (other[..., 3] > 128) & (other[..., :3].astype(int).sum(-1) < 330)
    mine = face & (rgb.sum(-1) < 330) & ~ndimage.binary_dilation(other_dark, iterations=2)
    lab, n = ndimage.label(mine)
    sizes = ndimage.sum(mine, lab, range(1, n + 1)) if n else []
    save(np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 15]), "lashes")
if a.face_only:
    sys.exit(0)

save(head, "head")

# 髪: Gemini は髪を線とほぼ同じこげ茶で塗るので、細い線とは太さで見分ける（半径4px の円が入る暗い面）。
# 面は髪の決まりの色 #6B4428 に塗り直し、まわりの線と一緒に _hair.png にする。残り（顔の輪郭・耳・首）は _headbase.png
dark = head & ~face & (rgb.sum(-1) < 330)
area = ndimage.binary_opening(dark, structure=np.ones((9, 9), bool))
hair = ndimage.binary_dilation(area, iterations=6) & head & ~face & (dark | area)
raw = raw.copy()
raw[area] = [0x6B, 0x44, 0x28]
save(hair, "hair")
# 髪のない頭は、肌の範囲（顔・耳・首）とその輪郭だけにする。髪の輪郭の線が残ると、別の髪型に替えたときに見える
skin_all = ndimage.binary_fill_holes(head & (dist(SKIN) < 60))
save(head & ~hair & ndimage.binary_dilation(skin_all, iterations=7), "headbase")
rest = solid & ~head
top = rest & (dist(TEAL) < 90)
feet = rest & light & (np.abs(rgb - rgb.mean(-1, keepdims=True)).max(-1) < 25) & (ys > H * 0.72)
beige = rest & light & ~top & ~feet
lab, n = ndimage.label(beige)
sizes = ndimage.sum(beige, lab, range(1, n + 1)) if n else []
big = [i + 1 for i, s in enumerate(sizes) if s >= 8000]
bottom = np.isin(lab, big)
hands = beige & ~bottom & np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 300])

# 線とにじみ（どの部位でもない画素）は、いちばん近い部位に入れる
parts = [top, bottom, feet, hands]
label = np.zeros((H, W), int)
for k, m in enumerate(parts, 1):
    label[m] = k
_, (iy, ix) = ndimage.distance_transform_edt(label == 0, return_indices=True)
near = label[iy, ix]
other = rest & (label == 0)
for k, name in enumerate(["top", "bottom", "feet", "hands"], 1):
    save(parts[k - 1] | (other & (near == k)), name)
