"""試し描きの評価：マゼンタを抜き、一覧・64px・重ね合わせ・位置と色の数字を出す。"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

trial = Path(sys.argv[1])
out = trial / "eval"
out.mkdir(exist_ok=True)

FUR = np.array([0xF2, 0xA3, 0x41])
LINE = np.array([0x5A, 0x3A, 0x22])


def cut(path):
    """マゼンタに近い画素を透明にした RGBA を返す。"""
    img = Image.open(path).convert("RGB")
    a = np.asarray(img).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    magenta = (r > 170) & (b > 170) & (g < 110) & (abs(r - b) < 90)
    rgba = np.dstack([a, np.where(magenta, 0, 255)]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA"), ~magenta, a


files = sorted(p for p in trial.glob("[0-9][0-9]_*.jpg"))
cuts = {p.stem: cut(p) for p in files}

# 一覧（256px）と 64px の一覧
for size, name in ((256, "sheet_256.png"), (64, "sheet_64.png")):
    pad = 8 if size == 256 else 4
    sheet = Image.new("RGB", (5 * (size + pad) + pad, 2 * (size + pad) + pad), "#FFF8EE")
    for i, p in enumerate(files):
        im = cuts[p.stem][0].resize((size, size), Image.LANCZOS)
        x, y = pad + (i % 5) * (size + pad), pad + (i // 5) * (size + pad)
        sheet.paste(im, (x, y), im)
    sheet.save(out / name)

# 位置（キャンバス1024）と色
print("name\tleft\ttop\tright\tbottom\twidth\theight\tfoot_from_bottom\tfur_dist\tline_dist")
for p in files:
    _, mask, a = cuts[p.stem]
    ys, xs = np.nonzero(mask)
    l, t, r, b = xs.min(), ys.min(), xs.max(), ys.max()
    px = a[mask]
    # 毛の色：きつね色に近い画素の平均と、指定色との距離
    near_fur = px[np.linalg.norm(px - FUR, axis=1) < 70]
    fur = np.linalg.norm(near_fur.mean(0) - FUR) if len(near_fur) > 200 else float("nan")
    dark = px[px.sum(1) < 300]
    line = np.linalg.norm(dark.mean(0) - LINE) if len(dark) > 200 else float("nan")
    print(f"{p.stem}\t{l}\t{t}\t{r}\t{b}\t{r-l}\t{b-t}\t{1024-b}\t{fur:.0f}\t{line:.0f}")

# 部品を男性の素体に重ねる
base = cuts["06_avatar_male_base"][0]
for part in ("08_part_knitcap", "09_part_parka", "10_part_glasses"):
    if part not in cuts:
        continue
    comp = Image.new("RGBA", base.size, "#FFF8EE")
    comp.alpha_composite(base)
    comp.alpha_composite(cuts[part][0])
    comp.convert("RGB").save(out / f"overlay_{part}.png")

# ワンのすけ5枚を半透明で重ねて、頭身と位置のずれを見る
wan = [cuts[p.stem][0] for p in files if p.stem.startswith("0") and "wan" in p.stem]
stack = Image.new("RGBA", (1024, 1024), "#FFFFFF")
for im in wan:
    faded = im.copy()
    faded.putalpha(im.getchannel("A").point(lambda v: v * 0.3))
    stack.alpha_composite(faded)
draw = ImageDraw.Draw(stack)
draw.line([(0, 920), (1024, 920)], fill="#FF0000", width=2)
stack.convert("RGB").save(out / "wan_stack.png")
print("saved to", out)
