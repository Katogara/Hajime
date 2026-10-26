"""マゼンタ（または透明）を抜き、決まった色だけに塗り直してから vtracer で SVG にする。

使い方:
  to_svg.py 元画像 出力.svg 色1 色2 ...   （#RRGGBB を並べる）
  to_svg.py 元画像 出力.svg auto N         （絵から N 色を自動で選ぶ。いちばん濃い色は線のこげ茶 #5A3A22 にそろえる）
元画像は JPEG（マゼンタの背景）でも、透過 PNG（extract_part.py の出力）でもよい。
線と塗りの2枚に分け、決まりに合わせた SVG にするときは svg_layers.py を使う（塗り直しはこのファイルの flatten を使う）。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

LINE = np.array([0x5A, 0x3A, 0x22])


def hex_rgb(c):
    return [int(c[i:i + 2], 16) for i in (1, 3, 5)]


def background(a, alpha=None):
    """背景の画素: 背景そのもののマゼンタ（およそ 248, 7, 235）を含む、マゼンタに近い色のかたまりと、透明なところ。
    腕と胴のあいだのような囲まれた背景も取れる。絵の中のピンクや紫（ギャル系の #FF5FA2、原宿系の #A04BD8 など）は、
    背景そのものの色を含まないので背景にしない。"""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    magenta = (r > 170) & (b > 170) & (g < 110) & (abs(r - b) < 90)
    pure = (r > 215) & (b > 195) & (g < 45)
    lab, _ = ndimage.label(magenta)
    seeds = np.unique(lab[pure & magenta])
    empty = np.isin(lab, seeds[seeds > 0])
    if alpha is not None:
        empty |= alpha < 128
    return empty


def fringe_of(a, empty, reach=3, strength=60):
    """マゼンタがにじんだふち: 背景から reach px 以内の、赤と青が緑より strength 以上強い色。
    離れたところの同じような色（濃いピンクなど）は絵の色なので残す。"""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    near = ndimage.binary_dilation(empty, iterations=reach) & ~empty
    return near & ((r - g) > strength) & ((b - g) > strength)


def figure_mask(img):
    """背景（マゼンタか透明）でない画素。"""
    alpha = np.asarray(img.convert("RGBA"))[..., 3] if img.mode in ("RGBA", "LA", "P") else None
    a = np.asarray(img.convert("RGB").filter(ImageFilter.MedianFilter(3))).astype(int)
    return ~background(a, alpha), a


def flatten(src, spec):
    """決まった色だけに塗り直す。spec は ["#色", ...] か ["auto", "N", "#色", ...]。
    戻り値: (塗り直した RGB の配列, 絵の画素の bool 配列, 使った色の配列)"""
    solid, a = figure_mask(Image.open(src))
    # 絵から離れた小さな点のごみ（300px 未満のかたまり）を消す
    lab, cnt = ndimage.label(solid)
    if cnt:
        sizes = ndimage.sum(solid, lab, range(1, cnt + 1))
        solid &= np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 300])
    # マゼンタがにじんだふちの色は、線のこげ茶とみなす
    a[solid & fringe_of(a, ~solid)] = LINE

    if spec[0] == "auto":
        # auto N [#色 ...]: 決まった色（後ろに並べた色と線のこげ茶）を必ず残し、足りない分を絵から N 色まで選ぶ
        n = int(spec[1])
        keep = np.array([hex_rgb(c) for c in spec[2:]] + [LINE.tolist()])
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
        palette = np.array([hex_rgb(c) for c in spec])

    d = ((a[..., None, :] - palette[None, None]) ** 2).sum(-1)
    mapped = palette[d.argmin(-1)].astype(np.uint8)
    return mapped, solid, palette


if __name__ == "__main__":
    import vtracer

    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    mapped, solid, _ = flatten(src, sys.argv[3:])
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
