"""ワンのすけの頭と首の小物を、手を振る絵（wan_wave）以外のポーズに合わせるための、頭の位置・大きさ・傾きを求める。

使い方: python -P tools/wan_anchors.py [確かめ用の一覧.png]
  Hajime/Art/wan/ の SVG を読み、Hajime/Costumes.json の "wanAnchors" に入れる値を出す。
  一覧を渡すと、各ポーズに頭の小物（ギャル系のサングラス）を重ねた画像を作る。
手を振る絵の頭（耳から口の下まで）の線を、ほかのポーズの線の中で、大きさと傾きを変えながら探し（FFT の相互相関）、
いちばん重なるところを選ぶ。初日に描いた絵（てへ・うなずき・おみやげ・びっくり）は、ワンのすけの大きさが少し違う。
値は 1024 のキャンバスで、頭の真ん中（center）を中心に scale 倍・deg 度回してから (dx, dy) ずらす。
"""
import json
import sys
from pathlib import Path

import numpy as np
from scipy import ndimage, signal

sys.path.insert(0, str(Path(__file__).parent))
from svg_layers import raster  # noqa: E402

ART = Path(__file__).resolve().parent.parent / "Hajime" / "Art"
POSES = ["banzai", "clap", "blink", "tehe", "nod", "gift", "wow"]


def line_mask(pose):
    a = raster((ART / "wan" / f"wan_{pose}_line.svg").read_text(encoding="utf-8"))
    return ndimage.binary_dilation(a[..., 3] > 0, iterations=3).astype(np.float32)


ref = line_mask("wave")
fill = raster((ART / "wan" / "wan_wave_fill.svg").read_text(encoding="utf-8"))[..., 3] > 0
ys = np.nonzero(fill.any(1))[0]
top, bottom = ys.min(), ys.min() + int((ys.max() - ys.min()) * 0.45)
xs = np.nonzero(fill[top:bottom].any(0))[0]
left, right = xs.min(), xs.max()
cy, cx = (top + bottom) / 2, (left + right) / 2
patch = ref[top:bottom, left:right]


def transform(p, scale, deg):
    q = ndimage.zoom(p, scale, order=1) if scale != 1 else p
    return ndimage.rotate(q, deg, reshape=False, order=1) if deg else q


out = {}
for pose in POSES:
    target = line_mask(pose)
    best = (-1.0, 0.0, 0.0, 1.0, 0)
    for scale in np.arange(0.80, 1.21, 0.04):
        for deg in range(-12, 13, 3):
            q = transform(patch, scale, deg)
            corr = signal.fftconvolve(target, q[::-1, ::-1], mode="valid")
            i = np.unravel_index(np.argmax(corr), corr.shape)
            s = corr[i] / q.sum()
            if s > best[0]:
                h, w = q.shape
                # 見つけた枠の真ん中と、手を振る絵の頭の真ん中の差
                best = (s, i[1] + w / 2 - cx, i[0] + h / 2 - cy, float(scale), deg)
    s, dx, dy, scale, deg = best
    out[pose] = {"dx": round(dx), "dy": round(dy), "scale": round(scale, 2), "deg": -deg}
    print(f"{pose}: ずらし ({dx:+.0f}, {dy:+.0f}) 大きさ {scale:.2f} 回転 {-deg:+d}°  重なり {s:.2f}")
result = {"center": [round(cx), round(cy)], "poses": out}
print(json.dumps(result, ensure_ascii=False))

if len(sys.argv) > 1:
    from PIL import Image
    item = raster((ART / "gyaru" / "wan_gyaru_head_fill.svg").read_text(encoding="utf-8"))
    item_line = raster((ART / "gyaru" / "wan_gyaru_head_line.svg").read_text(encoding="utf-8"))
    hat = Image.alpha_composite(Image.fromarray(item), Image.fromarray(item_line))
    sheet = Image.new("RGB", (8 * 256, 256), "#FFF8EE")
    for k, pose in enumerate(["wave"] + POSES):
        im = Image.new("RGBA", (1024, 1024), "#FFF8EE")
        for l in ("fill", "line"):
            im.alpha_composite(Image.fromarray(raster((ART / "wan" / f"wan_{pose}_{l}.svg").read_text(encoding="utf-8"))))
        a = out.get(pose, {"dx": 0, "dy": 0, "scale": 1, "deg": 0})
        # 頭の真ん中を中心に拡大と回転をしてから、ずらす（アプリと同じ手順）
        s, r = a["scale"], np.deg2rad(a["deg"])
        # 出力の点 o から入力の点 i: i = R^-1 ((o - c - d) / s) + c
        c, si = np.cos(r), np.sin(r)
        A = np.array([[c, si], [-si, c]]) / s
        ox, oy = cx + a["dx"], cy + a["dy"]
        bx = cx - (A[0, 0] * ox + A[0, 1] * oy)
        by = cy - (A[1, 0] * ox + A[1, 1] * oy)
        h = hat.transform(hat.size, Image.Transform.AFFINE, (A[0, 0], A[0, 1], bx, A[1, 0], A[1, 1], by),
                          Image.Resampling.BILINEAR)
        im.alpha_composite(h)
        sheet.paste(im.convert("RGB").resize((256, 256)), (k * 256, 0))
    sheet.save(sys.argv[1])
    print(sys.argv[1])
