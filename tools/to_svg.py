"""マゼンタ（または透明）を抜き、決まった色だけに塗り直してから vtracer で SVG にする。

使い方:
  to_svg.py 元画像 出力.svg 色1 色2 ...   （#RRGGBB を並べる）
  to_svg.py 元画像 出力.svg auto N         （絵から N 色を自動で選ぶ。いちばん濃い色は線のこげ茶 #5A3A22 にそろえる）
元画像は JPEG（マゼンタの背景）でも、透過 PNG（extract_part.py の出力）でもよい。
"""
import sys
from pathlib import Path

import numpy as np
import vtracer
from PIL import Image, ImageFilter

LINE = np.array([0x5A, 0x3A, 0x22])
src, dst = Path(sys.argv[1]), Path(sys.argv[2])

img = Image.open(src)
alpha = np.asarray(img.convert("RGBA"))[..., 3] if img.mode in ("RGBA", "LA", "P") else None
rgb = img.convert("RGB").filter(ImageFilter.MedianFilter(3))
a = np.asarray(rgb).astype(int)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
empty = (r > 170) & (b > 170) & (g < 110) & (abs(r - b) < 90)
if alpha is not None:
    empty |= alpha < 128
solid = ~empty
# 絵から離れた小さな点のごみ（300px 未満のかたまり）を消す
from scipy import ndimage
lab, cnt = ndimage.label(solid)
if cnt:
    sizes = ndimage.sum(solid, lab, range(1, cnt + 1))
    solid &= np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 300])
# マゼンタがにじんだふちの色（赤と青が強く緑が弱い）は、線のこげ茶とみなす
fringe = solid & ((r - g) > 60) & ((b - g) > 60)
a[fringe] = LINE

if sys.argv[3] == "auto":
    # auto N [#色 ...]: 決まった色（後ろに並べた色と線のこげ茶）を必ず残し、足りない分を絵から N 色まで選ぶ
    n = int(sys.argv[4])
    keep = [[int(c[i:i + 2], 16) for i in (1, 3, 5)] for c in sys.argv[5:]] + [LINE.tolist()]
    keep = np.array(keep)
    pixels = a[solid]
    # 決まった色に近い画素は除いて、残りから色を選ぶ
    far = ((pixels[:, None, :] - keep[None]) ** 2).sum(-1).min(1) > 45 ** 2
    rest = pixels[far].astype(np.uint8)
    extra = np.zeros((0, 3), int)
    if len(rest) > 500 and n > 0:
        strip = Image.fromarray(rest.reshape(1, -1, 3), "RGB")
        extra = np.array(strip.quantize(colors=n, method=Image.Quantize.MEDIANCUT,
                                        dither=Image.Dither.NONE).getpalette()[: n * 3]).reshape(-1, 3)
    palette = np.vstack([keep, extra])
else:
    palette = np.array([[int(c[i:i + 2], 16) for i in (1, 3, 5)] for c in sys.argv[3:]])

d = ((a[..., None, :] - palette[None, None]) ** 2).sum(-1)
mapped = palette[d.argmin(-1)].astype(np.uint8)
rgba = np.dstack([mapped, np.where(solid, 255, 0)]).astype(np.uint8)
flat = dst.with_suffix(".flat.png")
Image.fromarray(rgba, "RGBA").save(flat)

vtracer.convert_image_to_svg_py(
    str(flat), str(dst),
    colormode="color", hierarchical="stacked", mode="spline",
    filter_speckle=6, color_precision=8, layer_difference=8,
    corner_threshold=60, length_threshold=4.0, splice_threshold=45, path_precision=2,
)
svg = dst.read_text(encoding="utf-8")
print(dst.name, "bytes", len(svg), "paths", svg.count("<path"))
