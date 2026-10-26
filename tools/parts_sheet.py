"""取り出した部品の確認用一覧：部品だけ（水色の地）と、素体に重ねた絵を並べる。

使い方: parts_sheet.py 出力.png "部品.png|素体.jpg" ["部品.png|素体.jpg" ...]
"""
import sys

import numpy as np
from PIL import Image

out, pairs = sys.argv[1], [s.split("|") for s in sys.argv[2:]]
SZ = 300
sheet = Image.new("RGB", (2 * SZ * 3, SZ * ((len(pairs) + 2) // 3)), "white")
for i, (part_path, base_path) in enumerate(pairs):
    part = Image.open(part_path).convert("RGBA")
    alone = Image.new("RGBA", part.size, "#CFE6FF")
    alone.alpha_composite(part)
    base = np.asarray(Image.open(base_path).convert("RGB")).astype(int)
    magenta = (base[..., 0] > 170) & (base[..., 2] > 170) & (base[..., 1] < 110)
    base_rgba = Image.fromarray(np.dstack([base, np.where(magenta, 0, 255)]).astype(np.uint8), "RGBA")
    over = Image.new("RGBA", part.size, "#FFF8EE")
    over.alpha_composite(base_rgba)
    over.alpha_composite(part)
    x, y = (i % 3) * 2 * SZ, (i // 3) * SZ
    sheet.paste(alone.convert("RGB").resize((SZ, SZ)), (x, y))
    sheet.paste(over.convert("RGB").resize((SZ, SZ)), (x + SZ, y))
sheet.save(out)
