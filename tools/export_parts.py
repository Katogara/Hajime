"""削り用ツール (tools/kezuri.html) で開く部品の画像と、どの画像がどの品かの一覧を書き出す。

使い方: python -P tools/export_parts.py
Hajime/Art/ の線と塗りの SVG を重ねて 1024x1024 の PNG にし、C:\\Users\\user\\Hajime\\kezuri\\部品\\ に置く。
フォルダはテーマごと（「01_ギャル系」など）、ファイル名は「アバター_ハートのサングラス（頭）__av_gyaru_head.png」のように
キャラ・品名・部位と、元の部品の名前（__ のあと）を付ける。削った印の名前もこれに _erase を付けたものになり、
make_art.py は __ のあとの部品の名前で印を探す。
座標は SVG と同じ（位置合わせのあと）なので、ツールで塗った印はそのまま svg_layers.py の --erase に使える。
kezuri\\一覧.html には、品ごとに見本の絵・フォルダ・ファイル名を並べ、絵を押すとその部品をツールで開く。
"""
import base64
import html
import io
import json
import re
import shutil
import sys
from pathlib import Path
from urllib.parse import quote

from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from svg_layers import SIZE, raster  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "Hajime" / "Art"
OUT = Path(r"C:\Users\user\Hajime\kezuri")
PARTS = OUT / "部品"

PART_JA = {"head": "頭", "face": "顔", "top": "上", "bottom": "下", "feet": "靴", "neck": "首", "hand": "手"}
POSE_JA = {"std": "ふつう", "joy": "大喜び"}
CHAR_JA = {"avatar": "アバター", "wan": "ワンのすけ"}
BASE_FOLDER = "00_体・顔・髪・ワンのすけ"
BASE = {
    "av_std_headbase": "アバター_頭と首（ふつう）", "av_joy_headbase": "アバター_頭と首（大喜び）",
    "av_std_top": "アバター_初期の上の服（ふつう）", "av_joy_top": "アバター_初期の上の服（大喜び）",
    "av_std_bottom": "アバター_初期のズボン（ふつう）", "av_joy_bottom": "アバター_初期のズボン（大喜び）",
    "av_std_feet": "アバター_初期の靴（ふつう）", "av_joy_feet": "アバター_初期の靴（大喜び）",
    "av_std_hands": "アバター_手（ふつう）", "av_joy_hands": "アバター_手（大喜び）",
    "av_face_normal": "アバター_顔（ふつう）", "av_face_smile": "アバター_顔（にっこり）", "av_face_joy": "アバター_顔（大喜び）",
    "av_lashes_std": "アバター_まつ毛（ふつう）", "av_lashes_joy": "アバター_まつ毛（大喜び）",
    "av_hair_short": "アバター_髪（ショート）", "av_hair_bob": "アバター_髪（ボブ）",
    "av_hair_mash": "アバター_髪（マッシュ）", "av_hair_ponytail": "アバター_髪（ひとつ結び）",
    "wan_wave": "ワンのすけ（手を振る）", "wan_wave_nobandana": "ワンのすけ（手を振る・バンダナなし）",
    "wan_banzai": "ワンのすけ（ばんざい）", "wan_clap": "ワンのすけ（拍手）", "wan_wow": "ワンのすけ（キラキラ目）",
    "wan_tehe": "ワンのすけ（てへ）", "wan_nod": "ワンのすけ（うなずき）", "wan_gift": "ワンのすけ（おみやげ）",
    "wan_blink": "ワンのすけ（まばたき）",
}


def safe(s):
    return re.sub(r'[\\/:*?"<>|]', "・", s)


def catalog():
    """部品の名前 → (フォルダ名, 並べる順, テーマ名, 表示名)"""
    data = json.loads((ROOT / "Hajime" / "Costumes.json").read_text(encoding="utf-8"))
    out = {name: (BASE_FOLDER, (0, 0, i), "体・顔・髪・ワンのすけ", label) for i, (name, label) in enumerate(BASE.items())}
    for t in data["themes"]:
        season = t["shelf"] == "season"
        folder = (f"季節_{t['order']:02d}月_" if season else f"{t['order']:02d}_") + t["name"]
        for k, item in enumerate(t["items"]):
            for pose, name in item["art"].items():
                label = f"{CHAR_JA[t['character']]}_{item['name']}（{PART_JA.get(item['part'], item['part'])}"
                label += f"・{POSE_JA[pose]}）" if pose in POSE_JA else "）"
                key = (2 if season else 1, t["order"], 0 if t["character"] == "avatar" else 1, k, pose)
                out[name] = (safe(folder), key, t["name"], label)
            if item.get("under"):   # スカートの裾から下の脚 (靴より下に描く部品)
                out[item["under"]] = (safe(folder), (2 if season else 1, t["order"], 0, k, "under"), t["name"],
                                      f"{CHAR_JA[t['character']]}_{item['name']}（裾から下の脚）")
    return out


def bbox(img):
    b = img.getchannel("A").getbbox() or (0, 0, SIZE, SIZE)
    m = 20
    return max(b[0] - m, 0), max(b[1] - m, 0), min(b[2] + m, SIZE), min(b[3] + m, SIZE)


def main():
    names = sorted({p.stem.rsplit("_", 1)[0] for p in ART.glob("*/*.svg") if p.stem.endswith(("_fill", "_line"))})
    where = {p.stem.rsplit("_", 1)[0]: p.parent for p in ART.glob("*/*.svg")}
    cat = catalog()
    if PARTS.exists():
        shutil.rmtree(PARTS)
    for old in OUT.iterdir():   # 前の書き出し（英語のテーマ名のフォルダ）を消す
        if old.is_dir() and old.name != "部品":
            shutil.rmtree(old)
    rows = []
    for name in names:
        folder, key, theme, label = cat.get(name, ("99_そのほか", (9, 0, name), "そのほか", name))
        img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        for layer in ("fill", "line"):
            p = where[name] / f"{name}_{layer}.svg"
            if p.exists():
                img.alpha_composite(Image.fromarray(raster(p.read_text(encoding="utf-8"))))
        file = f"{safe(label)}__{name}.png"
        dst = PARTS / folder / file
        dst.parent.mkdir(parents=True, exist_ok=True)
        img.save(dst)
        box = bbox(img)
        thumb = img.crop(box)
        thumb.thumbnail((150, 150))
        buf = io.BytesIO()
        thumb.save(buf, "PNG")
        rows.append((key, folder, theme, label, file, box, base64.b64encode(buf.getvalue()).decode()))
    rows.sort(key=lambda r: r[0])
    write_index(rows)
    shutil.copy(Path(__file__).parent / "kezuri.html", OUT / "削りツール.html")
    (OUT / "kezuri.html").unlink(missing_ok=True)
    print(f"{len(rows)} 枚を {PARTS} に書き出し、一覧.html を作った")


def write_index(rows):
    parts, last = [], None
    for key, folder, theme, label, file, box, b64 in rows:
        if folder != last:
            if last is not None:
                parts.append("</div>")
            parts.append(f'<h2>{html.escape(theme)}<span>フォルダ：部品\\{html.escape(folder)}</span></h2><div class="grid">')
            last = folder
        href = "削りツール.html?f=" + quote(f"部品/{folder}/{file}") + "&box=" + ",".join(map(str, box))
        char, _, rest = label.partition("_")
        parts.append(
            f'<a class="card" href="{href}" title="押すと削りツールで開きます">'
            f'<img src="data:image/png;base64,{b64}" alt="">'
            f'<b>{html.escape(rest or char)}</b><small>{html.escape(char if rest else "")}</small>'
            f'<code>{html.escape(file)}</code></a>')
    parts.append("</div>")
    page = INDEX.replace("{{BODY}}", "\n".join(parts))
    (OUT / "一覧.html").write_text(page, encoding="utf-8")


INDEX = """<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>部品の一覧</title>
<style>
 :root { --bg:#FFF8EE; --ink:#3b2a1d; --sub:#7a6656; --line:#e6d8c8; }
 body { margin:0; padding:16px 20px 40px; background:var(--bg); color:var(--ink);
        font-family:"Hiragino Sans","Yu Gothic UI","Meiryo",sans-serif; }
 h1 { font-size:22px; margin:4px 0 8px; }
 .lead { color:var(--sub); line-height:1.8; margin:0 0 8px; max-width:900px; }
 h2 { font-size:17px; margin:28px 0 10px; padding-bottom:4px; border-bottom:2px solid var(--line); }
 h2 span { font-size:12px; font-weight:normal; color:var(--sub); margin-left:12px; }
 .grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(170px, 1fr)); gap:10px; }
 .card { display:flex; flex-direction:column; gap:3px; padding:10px; background:#fff; border:1px solid var(--line);
         border-radius:10px; color:inherit; text-decoration:none; }
 .card:hover { border-color:#e0607e; box-shadow:0 2px 8px rgba(0,0,0,.08); }
 .card img { height:120px; object-fit:contain; background:#fbf6ef; border-radius:6px; padding:4px; }
 .card b { font-size:14px; }
 .card small { color:var(--sub); font-size:12px; }
 .card code { font-size:10px; color:var(--sub); word-break:break-all; }
 #find { font:inherit; padding:6px 10px; border:1px solid var(--line); border-radius:8px; width:260px; }
</style></head><body>
<h1>部品の一覧</h1>
<p class="lead">きせかえの品ごとに、直すときに開く画像を並べています。絵を押すと、その部品が削りツールで開きます。
画像はこのフォルダの「部品」の中に、テーマごとのフォルダで入っています。<br>
「ふつう」と「大喜び」で別の絵になっている服は、両方とも直してください。「体・顔・髪・ワンのすけ」は、どの服を着たときにも出る絵です。</p>
<input id="find" placeholder="品名で探す（例：サングラス）">
{{BODY}}
<script>
document.getElementById('find').oninput = e => {
  const q = e.target.value.trim();
  document.querySelectorAll('.card').forEach(c => c.style.display = !q || c.textContent.includes(q) ? '' : 'none');
  document.querySelectorAll('.grid').forEach(g => {
    const any = [...g.children].some(c => c.style.display !== 'none');
    g.style.display = any ? '' : 'none'; g.previousElementSibling.style.display = any ? '' : 'none';
  });
};
</script>
</body></html>
"""

if __name__ == "__main__":
    main()
