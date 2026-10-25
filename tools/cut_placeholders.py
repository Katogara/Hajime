"""Gemini で作ったキャラクターの一覧画像 (マゼンタ背景) から、1 体ずつ透過 PNG を切り出して
Hajime/Placeholder に置く。仮素材用 (製品はベクターでなぞり直し、Assets.xcassets に入れる)。
ブラウザからのアップロードではフォルダの階層を保てないので、仮素材は imageset にせず、PNG をそのまま置く。

使い方: python tools/cut_placeholders.py   (リポジトリの直下で実行)
必要なもの: Pillow
"""
import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DRAFTS = os.path.join(ROOT, "art", "drafts")
OUT = os.path.join(ROOT, "Hajime", "Placeholder")

# 書き出すキャンバス。製品の 1024 と同じ比率で、足元を 920/1024 の高さにそろえる
CANVAS = 512
FOOT = CANVAS * 920 // 1024
FIGURE_HEIGHT = CANVAS * 760 // 1024

# 一覧画像ごとの、左上から右下への並び順の名前と、塗りつぶして消す範囲 (取り込んだときのマウスの矢印)
SHEETS = {
    # 名前が "_" で始まるものは使わない (Gemini が同じポーズを 2 つ描いたときなど)
    "wan_expressions.png": {
        "names": ["wan_banzai", "_wan_banzai2", "wan_clap", "wan_wow",
                  "wan_tehe", "wan_nod", "wan_gift", "wan_blink"],
        "erase": [],
        # 立ち姿 (うなずき) の背の高さを基準にする。跳んでいる絵は少し大きくなる
        "reference": {name: "wan_nod" for name in ["wan_banzai", "_wan_banzai2", "wan_clap", "wan_wow",
                                                   "wan_tehe", "wan_nod", "wan_gift", "wan_blink"]},
    },
    # 目を開けて手を振る絵は、一覧に入らなかったので 1 体だけ別に作った
    "wan_wave.png": {
        "names": ["wan_wave"],
        "erase": [],
    },
    "avatar_expressions.png": {
        "names": ["avatar_male_normal", "avatar_male_smile", "avatar_male_joy",
                  "avatar_female_normal", "avatar_female_smile", "avatar_female_joy"],
        "erase": [],
        # 男女とも、ふつうの立ち姿の背の高さを基準にして同じ身長にそろえる
        "reference": {
            "avatar_male_normal": "avatar_male_normal",
            "avatar_male_smile": "avatar_male_normal",
            "avatar_male_joy": "avatar_male_normal",
            "avatar_female_normal": "avatar_female_normal",
            "avatar_female_smile": "avatar_female_normal",
            "avatar_female_joy": "avatar_female_normal",
        },
    },
}


def magenta_level(r, g, b):
    """マゼンタらしさ。R と B が G よりどれだけ大きいか (背景の影の暗いマゼンタも高くなる)"""
    return min(r, b) - g


def key_out(image):
    """マゼンタの画素を透明にし、境目のにじみは輪郭線の色に寄せて半透明にする"""
    pixels = image.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            level = magenta_level(r, g, b)
            if level > 110:
                pixels[x, y] = (0, 0, 0, 0)
            elif level > 45:
                alpha = int(255 * (110 - level) / 65)
                pixels[x, y] = (0x5A, 0x3A, 0x22, min(a, alpha))
    return image


def components(image):
    """不透明な画素 (半透明の縁も含む) のつながりに番号を付ける。番号の表と、番号ごとの (面積, 外接矩形) を返す"""
    alpha = image.getchannel("A").load()
    width, height = image.size
    labels = [[0] * width for _ in range(height)]
    found = {}
    for y in range(height):
        for x in range(width):
            if labels[y][x] or alpha[x, y] == 0:
                continue
            label = len(found) + 1
            queue = deque([(x, y)])
            labels[y][x] = label
            area, x0, y0, x1, y1 = 0, x, y, x, y
            while queue:
                cx, cy = queue.popleft()
                area += 1
                x0, y0, x1, y1 = min(x0, cx), min(y0, cy), max(x1, cx), max(y1, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height and not labels[ny][nx] and alpha[nx, ny] > 0:
                        labels[ny][nx] = label
                        queue.append((nx, ny))
            found[label] = (area, (x0, y0, x1 + 1, y1 + 1))
    return labels, found


def split(image, figure):
    """箱の中央付近 (30〜70%) で、不透明な画素がいちばん少ない列を境に 2 つに分ける"""
    label, (x0, y0, x1, y1) = figure
    alpha = image.getchannel("A").load()
    start, end = x0 + (x1 - x0) * 3 // 10, x0 + (x1 - x0) * 7 // 10
    cut = min(range(start, end), key=lambda x: sum(alpha[x, y] >= 128 for y in range(y0, y1)))
    return [(label, (x0, y0, cut, y1)), (label, (cut, y0, x1, y1))]


def in_reading_order(figures):
    """上の段から順に、段の中は左から"""
    figures = sorted(figures, key=lambda figure: figure[1][1])
    rows = []
    for figure in figures:
        box = figure[1]
        center = (box[1] + box[3]) / 2
        for row in rows:
            if row[0][1][1] <= center <= row[0][1][3]:
                row.append(figure)
                break
        else:
            rows.append([figure])
    rows.sort(key=lambda row: min(figure[1][1] for figure in row))
    return [figure for row in rows for figure in sorted(row, key=lambda figure: figure[1][0])]


def cut_out(image, labels, found, figure, margin):
    """その体の画素と、近くの小さな飾り (キラキラなど) だけを残して切り出す。隣の体の端は入れない"""
    label, (x0, y0, x1, y1) = figure
    left, top = max(0, x0 - margin), max(0, y0 - margin)
    right, bottom = min(image.width, x1 + margin), y1
    extras = {other for other, (area, (ox0, oy0, ox1, oy1)) in found.items()
              if area < 3000 and ox0 >= left and oy0 >= top and ox1 <= right and oy1 <= bottom}
    source = image.load()
    crop = Image.new("RGBA", (right - left, bottom - top), (0, 0, 0, 0))
    pixels = crop.load()
    for y in range(top, bottom):
        for x in range(left, right):
            own = labels[y][x] == label and x0 <= x < x1
            if own or labels[y][x] in extras:
                pixels[x - left, y - top] = source[x, y]
    return crop


def place(figure, box_height):
    """足元を FOOT にそろえて、正方形のキャンバスの中央に置く"""
    scale = FIGURE_HEIGHT / box_height
    figure = figure.resize((max(1, round(figure.width * scale)), max(1, round(figure.height * scale))),
                           Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(figure, ((CANVAS - figure.width) // 2, max(0, FOOT - figure.height)))
    return canvas


def main():
    os.makedirs(OUT, exist_ok=True)
    for sheet, spec in SHEETS.items():
        image = Image.open(os.path.join(DRAFTS, sheet)).convert("RGBA")
        for x0, y0, x1, y1 in spec["erase"]:
            image.paste((255, 0, 255, 255), (x0, y0, x1, y1))
        image = key_out(image)
        labels, found = components(image)
        figures = [(label, box) for label, (area, box) in found.items() if area >= 3000]
        # 隣と触れて 1 つにつながった体は、いちばん幅の広いものから、不透明な画素の少ない列で分ける
        while 0 < len(figures) < len(spec["names"]):
            widest = max(figures, key=lambda figure: figure[1][2] - figure[1][0])
            figures.remove(widest)
            figures += split(image, widest)
        figures = in_reading_order(figures)
        if len(figures) != len(spec["names"]):
            raise SystemExit(f"{sheet}: {len(figures)} 体見つかりました ({len(spec['names'])} 体のはず)")
        # 大きさをそろえる。基準の絵 (立ち姿) の背の高さを FIGURE_HEIGHT にし、同じ組の絵は同じ倍率にする。
        # 男女の立ち姿をそれぞれ基準にするので、生成した絵で男女の背が違っていても、アプリでは同じ身長になる
        margin = 12
        boxes = dict(zip(spec["names"], (box for _, box in figures)))
        tallest = max(box[3] - box[1] for box in boxes.values())
        for name, figure in zip(spec["names"], figures):
            if name.startswith("_"):
                continue
            reference = spec.get("reference", {}).get(name)
            height = boxes[reference][3] - boxes[reference][1] if reference else tallest
            place(cut_out(image, labels, found, figure, margin), height + margin) \
                .save(os.path.join(OUT, f"{name}.png"))
            print(name, figure[1])


if __name__ == "__main__":
    main()
