"""腰の下絵 (parts3/waist_<テーマ>.png) を作る (2026-11-26)。
元の絵で上着に隠れていた腰が描かれていないズボンは、上端が初期のズボン (y 591) より下にあり、丈の短い上着と合わせると
胴とのあいだに隙間ができた (ユーザーの指摘「ワイドスラックス、パジャマのパンツ、クリーム色のスラックス、コーデュロイパンツ」)。

1 回目 (ビルド #346) は、ズボンの地の色の帯をズボンの下に敷いた。実機で次の指摘があった。
- ワイドスラックス・コーデュロイパンツ: 折れ線が帯のところで切れる
- パジャマのパンツ・コーデュロイパンツ: もとのズボンの上端の線が、股の上に横線として残る
- ベージュのパンツ: 上着の裾の名残り (裾の折り返し) がズボンの上に描かれていて、上着の裾がズボンに入って見える

2 回目 (今の作り方) は、ズボンのきれいな 1 行 (上端の線や裾の名残りより下) を、初期のズボンの腰の幅まで
縮めながら上へ引き伸ばし、上端に線を引く。折れ線と脇の線はそのまま上へつながる。
股の線は腰まで伸ばすと不自然なので、真ん中 (CENTER) の線だけ地の色で塗る。
アプリでは Costumes.json の "waist" で、ズボンの上 (上着の下) に重ね、もとの上端の線や裾の名残りを隠す。
クリーム色のスラックスは 1 回目のまま (指摘なし。"under" の帯)。
make_art.py の job で SVG にする。
使い方: python -P make_waist.py テーマ ...  (例: fuwari ouchi amekaji consa)"""
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
TOP = 586  # 腰の上端 (SVG。初期のズボンの上端 591 より少し上で、上着の裾の下に入る)
W = 8  # 線の太さ
CENTER = (500, 524)  # 股の線を消す範囲 (x)
# 引き伸ばす元の行 (SVG の y): 上端の線・裾の名残りより下で、折れ線がまっすぐな行
SOURCE = {"fuwari": 652, "ouchi": 646, "amekaji": 622, "consa": 648}
# ベージュのパンツは、上端 (裾の名残りがあり左右に広がる) を make_art.py の cut で描かないので (y 640 から下だけ)、
# 腰はこの帯だけでまっすぐにつなぐ。1 回目は上端の幅まで広げたので、腰回りが左右に膨らんだ (11-26 のユーザーの指摘)


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
ls, rs = extent(std, 596)
for theme in sys.argv[1:]:
    item = load(f"av_{theme}_bottom")
    m = item[..., 3] > 128
    src = SOURCE[theme]
    li, ri = extent(m, src)
    row = item[src, li:ri + 1]
    light = [p for p in row if p[3] > 200 and sum(int(v) for v in p[:3]) > 250]
    fill = Counter(tuple(int(v) for v in p[:3]) for p in light).most_common(1)[0][0] + (255,)
    out = np.zeros((1024, 1024, 4), np.uint8)
    for y in range(TOP, src + 1):  # 元の行まで重ね、ズボンとのつなぎ目に線の切れ目を作らない
        t = (y - TOP) / (src - TOP)
        l = int(round(ls + (li - ls) * t))
        r = int(round(rs + (ri - rs) * t))
        xs = np.clip(np.round(np.linspace(0, ri - li, r - l + 1)).astype(int), 0, ri - li)
        out[y, l:r + 1] = row[xs]
        out[y, l:r + 1, 3] = 255
        c0, c1 = CENTER
        seg = out[y, c0:c1 + 1]
        dark = seg[..., :3].astype(int).sum(-1) < 300
        seg[dark] = fill
        if y < TOP + W:
            out[y, l:r + 1] = LINE
    # 帯の下端のすぐ下は、ズボンの脇の線だけを写して重ねる。帯の地の色が線の上に 1 ピクセル出て、
    # 脇の線に切れ目が見えたため (ベージュのパンツ)
    for y in range(src + 1, src + 5):
        dark = (item[y, :, :3].astype(int).sum(-1) < 300) & (item[y, :, 3] > 200)
        dark[CENTER[0]:CENTER[1] + 1] = False
        out[y][dark] = item[y][dark]
    png = np.zeros_like(out)
    png[:1024 - SHIFT] = out[SHIFT:]
    Image.fromarray(png).save(P / f"waist_{theme}.png")
    print(theme, "元の行", src, "腰", TOP, "〜", src - 1, "地の色", "#%02X%02X%02X" % fill[:3])
