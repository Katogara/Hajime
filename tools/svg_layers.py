"""絵を、決まりに合わせた「線」と「塗り」の2枚の SVG にする。

使い方:
  svg_layers.py 元画像 出力の名前 色の指定... [--align-from 画像 ...] [--no-align] [--height H] [--min-blob N] [--line-target 8]
    色の指定は to_svg.py と同じ（#RRGGBB を並べるか、auto N #色 ...）
    出力: 名前_line.svg（線のこげ茶だけ）、名前_fill.svg（塗り。線の下も周りの色で埋める）、名前_check.png
  svg_layers.py check SVG ...   決まりを守っているかを確かめる（守っていなければ終了コード 1）

足元の位置合わせ: 絵の下端を y=920、重心を x=512 に動かす。部品（素体との差で取り出した透過 PNG）は、
--align-from に素体の画像を渡し、素体と同じだけ動かす（部品だけで合わせると素体とずれる）。
--height は絵の高さ（上端から下端まで）をその px にそろえる（男女の身長をそろえるときなど）。

決まり（仕様書「本格導入の前の検討 → 実装」）: viewBox は 0 0 1024 1024。transform、グラデーション、マスク、
フィルター、文字、style 属性は使わない。線はアウトライン化した塗り、色は fill 属性。
"""
import argparse
import re
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).parent))
from to_svg import LINE, figure_mask, flatten  # noqa: E402

SIZE, FOOT, CENTER = 1024, 920, 512
LINE_HEX = "#5A3A22"
FORBIDDEN = ["transform", "style=", "<linearGradient", "<radialGradient", "<mask", "<filter",
             "<text", "<image", "<use", "<clipPath", "stroke="]


# ---- 位置合わせ ----

def placement(masks, height=None):
    """絵の画素から (倍率, x の移動, y の移動) を決める。下端を FOOT、重心を CENTER に。"""
    m = np.zeros((SIZE, SIZE), bool)
    for k in masks:
        m |= k
    rows = np.nonzero(m.sum(1) >= 3)[0]   # 3px 未満の行はごみとみなす
    top, bottom = rows.min(), rows.max()
    s = 1.0 if height is None else height / (bottom - top + 1)
    cx = np.nonzero(m)[1].mean()
    # 倍率は (cx, bottom) を中心にかけるので、移動はその点を (CENTER, FOOT) へ動かす量
    return s, CENTER - cx, FOOT - bottom, (cx, bottom)


def move(img, s, dx, dy, pivot, order):
    """配列の画像を倍率 s で拡大縮小し、(dx, dy) だけ動かす。order=0 は色を混ぜない最近傍。"""
    px, py = pivot
    # 出力の点 o → 入力の点 i: i = (o - (pivot + d)) / s + pivot
    m = np.array([1 / s, 1 / s])
    off = np.array([py - (py + dy) / s, px - (px + dx) / s])
    if img.ndim == 2:
        return ndimage.affine_transform(img, m, offset=off, order=order, output_shape=(SIZE, SIZE))
    return np.dstack([ndimage.affine_transform(img[..., c], m, offset=off, order=order,
                                               output_shape=(SIZE, SIZE)) for c in range(img.shape[2])])


# ---- SVG の整形 ----

def trace(rgba, speckle=6, **kw):
    import vtracer
    with tempfile.TemporaryDirectory() as d:
        png, svg = Path(d) / "in.png", Path(d) / "out.svg"
        Image.fromarray(rgba, "RGBA").save(png)
        vtracer.convert_image_to_svg_py(
            str(png), str(svg), colormode="color", mode="spline",
            filter_speckle=speckle, color_precision=8, layer_difference=8,
            corner_threshold=60, length_threshold=4.0, splice_threshold=45, path_precision=2, **kw)
        return svg.read_text(encoding="utf-8")


def bake(d, tx, ty):
    """M・C・Z だけの絶対座標のパスに、translate を足し込む。"""
    if re.search(r"[^MCZ0-9.\-\s]", d):
        raise ValueError("M・C・Z 以外の命令がある: " + d[:60])
    out, k = [], 0
    for tok in re.findall(r"[MCZ]|-?\d+(?:\.\d+)?", d):
        if tok in "MCZ":
            out.append(tok)
            continue
        v = float(tok) + (tx if k % 2 == 0 else ty)
        out.append(f"{v:.2f}".rstrip("0").rstrip("."))
        k += 1
    return " ".join(out).replace(" Z", "Z").replace("Z M", "ZM")


def clean(svg, palette_hex):
    """vtracer の SVG を決まりの形に書き直す。色はいちばん近い決まった色にそろえる。"""
    pal = np.array([[int(c[i:i + 2], 16) for i in (1, 3, 5)] for c in palette_hex])
    paths = []
    for m in re.finditer(r"<path\b([^>]*)/>", svg):
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        tx = ty = 0.0
        if "transform" in attrs:
            t = re.fullmatch(r"translate\(([-\d.]+),([-\d.]+)\)", attrs["transform"])
            if not t:
                raise ValueError("translate 以外の transform: " + attrs["transform"])
            tx, ty = float(t.group(1)), float(t.group(2))
        rgb = [int(attrs["fill"][i:i + 2], 16) for i in (1, 3, 5)]
        col = palette_hex[int(((pal - rgb) ** 2).sum(1).argmin())]
        paths.append(f'<path fill="{col}" d="{bake(attrs["d"], tx, ty)}"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n'
            + "\n".join(paths) + "\n</svg>\n")


# ---- 確かめる ----

def raster(svg):
    """決まりの形の SVG を画像に戻す（偶奇規則）。戻り値は RGBA の配列。"""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    for m in re.finditer(r'<path fill="(#[0-9A-F]{6})" d="([^"]+)"/>', svg):
        col, d = m.group(1), m.group(2)
        layer = np.zeros((SIZE, SIZE), bool)
        for sub in d.split("M")[1:]:
            v = [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", sub)]
            pts, cur = [(v[0], v[1])], (v[0], v[1])
            for j in range(2, len(v) - 5, 6):
                p = v[j:j + 6]
                for t in np.linspace(0, 1, 8)[1:]:
                    u = 1 - t
                    pts.append((u**3 * cur[0] + 3*u*u*t * p[0] + 3*u*t*t * p[2] + t**3 * p[4],
                                u**3 * cur[1] + 3*u*u*t * p[1] + 3*u*t*t * p[3] + t**3 * p[5]))
                cur = (p[4], p[5])
            if len(pts) > 2:
                im = Image.new("1", (SIZE, SIZE), 0)
                ImageDraw.Draw(im).polygon(pts, fill=1)
                layer ^= np.asarray(im)
        rgb = tuple(int(col[i:i + 2], 16) for i in (1, 3, 5))
        img.paste(Image.new("RGBA", (SIZE, SIZE), rgb + (255,)), mask=Image.fromarray(layer))
    return np.asarray(img)


def line_width(mask):
    """線の太さの目安（px）: 線の芯（距離の山）での距離の2倍の中央値。"""
    if not mask.any():
        return 0.0
    dist = ndimage.distance_transform_edt(mask)
    ridge = mask & (dist >= ndimage.maximum_filter(dist, 3)) & (dist >= 1.5)
    return float(np.median(dist[ridge]) * 2) if ridge.any() else 0.0


def check(path):
    svg = Path(path).read_text(encoding="utf-8")
    problems = [f"{w} を使っている" for w in FORBIDDEN if w in svg]
    if 'viewBox="0 0 1024 1024"' not in svg:
        problems.append("viewBox が 0 0 1024 1024 でない")
    if re.search(r'd="[^"]*[^MCZ0-9.\-\s"]', svg):
        problems.append("M・C・Z 以外の命令がある")
    cols = set(re.findall(r'fill="(#[0-9A-Fa-f]{6})"', svg))
    if path.endswith("_line.svg") and cols - {LINE_HEX}:
        problems.append(f"線のレイヤーに線のこげ茶以外の色がある: {sorted(cols - {LINE_HEX})}")
    ys = [float(y) for d in re.findall(r' d="([^"]+)"', svg)
          for y in re.findall(r"-?\d+(?:\.\d+)? (-?\d+(?:\.\d+)?)", d)]
    info = f"パス {svg.count('<path')}、色 {len(cols)}、{len(svg) // 1024}KB、下端 y={max(ys):.0f}" if ys else "パスなし"
    if path.endswith("_line.svg"):
        a = raster(svg)
        info += f"、線の太さ 約{line_width(a[..., 3] > 0):.0f}px"
    print(("OK  " if not problems else "NG  ") + Path(path).name + "  " + info)
    for p in problems:
        print("    " + p)
    return not problems


# ---- 本体 ----

def build(a):
    mapped, solid, palette = flatten(a.src, a.colors, a.min_blob)
    if a.no_align:
        s, dx, dy, pivot = 1.0, 0.0, 0.0, (0, 0)
    else:
        masks = [figure_mask(Image.open(p))[0] for p in (a.align_from or [a.src])]
        s, dx, dy, pivot = placement(masks, a.height)
    mapped = move(mapped, s, dx, dy, pivot, 0)
    solid = move(solid.astype(np.uint8), s, dx, dy, pivot, 0).astype(bool)

    line = solid & (np.abs(mapped.astype(int) - LINE).sum(-1) == 0)
    if a.line_target:
        # 内側の線を決まりの太さ（外形はアプリで合成のあとに付ける）にそろえる。
        # 顔のパーツのような小さな線のかたまり（2500px 未満）は太らせない（ユーザーが選んだ見本「顔そのまま」）
        lab, n = ndimage.label(line)
        sizes = ndimage.sum(line, lab, range(1, n + 1)) if n else []
        big = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 2500])
        r = int(round((a.line_target - line_width(big)) / 2))
        if r > 0:
            y, x = np.ogrid[-r:r + 1, -r:r + 1]
            line |= ndimage.binary_dilation(big, x * x + y * y <= r * r) & solid
            mapped[line] = LINE
    fill_px = solid & ~line
    # 線の下は、いちばん近い塗りの色で埋める（線を上に重ねたときにすき間が出ないように）
    filled = mapped.copy()
    if fill_px.any():
        _, (iy, ix) = ndimage.distance_transform_edt(~fill_px, return_indices=True)
        filled[line] = mapped[iy[line], ix[line]]

    hexes = ["#%02X%02X%02X" % tuple(c) for c in palette]
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    line_rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
    line_rgba[line] = list(LINE) + [255]
    # 塗りのない部品（まつ毛など線だけのもの）では、塗りの SVG を作らない
    fill_rgba = np.dstack([filled, np.where(solid & fill_px.any(), 255, 0)]).astype(np.uint8)
    speckle = 2 if a.min_blob < 50 else 6   # 細かい部品では、vtracer の点の切り捨ても弱める
    names = []
    for layer, rgba, kw, cols in [("fill", fill_rgba, dict(hierarchical="stacked"), hexes),
                                  ("line", line_rgba, dict(hierarchical="cutout"), [LINE_HEX])]:
        p = out.with_name(out.name + f"_{layer}.svg")
        if not rgba[..., 3].any():
            p.unlink(missing_ok=True)
            continue
        p.write_text(clean(trace(rgba, speckle, **kw), cols), encoding="utf-8")
        names.append(p)

    # 確かめ用: 左が塗り直した元の絵、右が SVG を重ねて画像に戻したもの
    flat = Image.fromarray(np.dstack([mapped, np.where(solid, 255, 0)]).astype(np.uint8), "RGBA")
    back = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    for p in sorted(names, key=lambda q: q.name.endswith("_line.svg")):
        back.alpha_composite(Image.fromarray(raster(p.read_text(encoding="utf-8"))))
    sheet = Image.new("RGBA", (SIZE * 2, SIZE), "#FFF8EE")
    sheet.alpha_composite(flat, (0, 0))
    sheet.alpha_composite(back, (SIZE, 0))
    ImageDraw.Draw(sheet).line([(0, FOOT), (SIZE * 2, FOOT)], fill="#3399FF", width=1)
    sheet.convert("RGB").resize((SIZE, SIZE // 2)).save(out.with_name(out.name + "_check.png"))
    ref = np.asarray(flat)[..., 3] > 0
    got = np.asarray(back)[..., 3] > 0
    iou = (ref & got).sum() / max((ref | got).sum(), 1)
    print(f"{out.name}: 倍率 {s:.3f} 移動 ({dx:+.0f}, {dy:+.0f})  形の一致 {iou:.3f}")
    ok = all([check(str(p)) for p in names])
    return ok


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "check":
        sys.exit(0 if all([check(p) for p in sys.argv[2:]]) else 1)
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("colors", nargs="+")
    ap.add_argument("--align-from", nargs="+")
    ap.add_argument("--no-align", action="store_true")
    ap.add_argument("--height", type=float)
    ap.add_argument("--min-blob", type=int, default=300, help="これより小さい離れた点はごみとして消す（まつ毛は 10）")
    ap.add_argument("--line-target", type=float, help="内側の線をこの太さ（px）まで太らせる。決まりは 8。顔のパーツの部品には付けない")
    sys.exit(0 if build(ap.parse_args()) else 1)
