"""マゼンタを抜き、決まった色だけに塗り直してから vtracer で SVG にする試し。

使い方: to_svg.py 元画像 出力.svg 色1 色2 ...（#RRGGBB）
"""
import sys
from pathlib import Path

import numpy as np
import vtracer
from PIL import Image, ImageFilter

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
palette = np.array([[int(c[i:i + 2], 16) for i in (1, 3, 5)] for c in sys.argv[3:]])

img = Image.open(src).convert("RGB").filter(ImageFilter.MedianFilter(3))
a = np.asarray(img).astype(int)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
magenta = (r > 170) & (b > 170) & (g < 110) & (abs(r - b) < 90)

# 各画素をいちばん近い決まった色に置き換える
d = ((a[..., None, :] - palette[None, None]) ** 2).sum(-1)
mapped = palette[d.argmin(-1)].astype(np.uint8)
rgba = np.dstack([mapped, np.where(magenta, 0, 255)]).astype(np.uint8)
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
