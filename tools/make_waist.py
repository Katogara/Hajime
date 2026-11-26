"""腰の帯の下絵 (parts3/waist_<テーマ>.png) を作る (2026-11-26)。
元の絵で上着に隠れていた腰が描かれていないズボンは、上端が初期のズボン (y 591) より下にあり、丈の短い上着と合わせると
胴とのあいだに隙間ができた (ユーザーの指摘「ワイドスラックス、パジャマのパンツ、クリーム色のスラックス、コーデュロイパンツ」)。
初期のズボンの腰の幅からそのズボンの上端の幅へ広がる帯を、ズボンの地の色で塗って線で囲む。
アプリでは Costumes.json の "under" で、ズボンの下に描く。make_art.py の job で SVG にする。
使い方: python -P make_waist.py テーマ ...  (例: fuwari ouchi kissa amekaji)"""
import sys
from collections import Counter
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path(__file__).parent))
from svg_layers import raster  # noqa

A = Path(__file__).parent.parent / "Hajime" / "Art"
P = Path(r"C:\Users\user\Hajime\ai-trial-20261026\gen\parts3")
LINE = (0x5A, 0x3A, 0x22, 255)
SHIFT = 64  # parts3 の PNG は SVG より 64 上
TOP = 586  # 帯の上端 (SVG。初期のズボンの上端 591 より少し上で、上着の裾の下に入る)
W = 8  # 線の太さ


def load(name):
    im = np.zeros((1024, 1024, 4), np.uint8)
    for l in ("fill", "line"):
        for f in A.glob(f"*/{name}_{l}.svg"):
            layer = raster(f.read_text(encoding="utf-8"))
            a = layer[..., 3:4] / 255
            im = (layer * a + im * (1 - a)).astype(np.uint8)
    return im


def extent(m, y):
    xs = np.nonzero(m[y])[0]
    return xs.min(), xs.max()


std = load("av_std_bottom")[..., 3] > 128
for theme in sys.argv[1:]:
    item = load(f"av_{theme}_bottom")
    m = item[..., 3] > 128
    waist = int(np.nonzero(m[:, 500:525].any(axis=1))[0].min())
    low = waist + 14  # ズボンの上端の線の下まで重ねる
    ls, rs = extent(std, 596)
    li, ri = extent(m, low)
    # 地の色: 上端から 20 下の行で、いちばん多い色 (線の色を除く)
    row = item[waist + 20, li + 15:ri - 15]
    colors = Counter(tuple(int(v) for v in p[:3]) for p in row
                     if p[3] > 200 and sum(int(v) for v in p[:3]) > 250)
    fill = colors.most_common(1)[0][0] + (255,)
    band = np.zeros((1024, 1024), bool)
    for y in range(TOP, low + 1):
        t = (y - TOP) / (low - TOP)
        band[y, int(round(ls + (li - ls) * t)):int(round(rs + (ri - rs) * t)) + 1] = True
    inner = np.zeros_like(band)
    for y in range(TOP + W, low + 1):
        xs = np.nonzero(band[y])[0]
        inner[y, xs.min() + W:xs.max() - W + 1] = True
    out = np.zeros((1024, 1024, 4), np.uint8)
    out[band] = LINE
    out[inner] = fill
    # PNG の座標へ (上へ 64)
    png = np.zeros_like(out)
    png[:1024 - SHIFT] = out[SHIFT:]
    Image.fromarray(png).save(P / f"waist_{theme}.png")
    print(theme, "上端", waist, "帯", TOP, "〜", low, "色", "#%02X%02X%02X" % fill[:3])
