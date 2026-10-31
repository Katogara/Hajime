"""Hajime/Art/ の下の SVG を集めて、Hajime/Art.xcassets を作る (CI で xcodegen の前に実行する)。

ブラウザからのアップロードではアセットカタログのフォルダの階層を保てないので、SVG は Hajime/Art/<テーマ>/ に置き、
ここで 1 つずつ imageset にする。ベクターのまま入れる (preserves-vector-representation)。
名前の重複は失敗にする (どのテーマの絵か分からなくなるため)。
"""
import json
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
art = root / "Hajime" / "Art"
out = root / "Hajime" / "Art.xcassets"

if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)
(out / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))

seen = {}
for svg in sorted(art.rglob("*.svg")):
    name = svg.stem
    if name in seen:
        sys.exit(f"同じ名前の絵が 2 つある: {seen[name]} と {svg}")
    seen[name] = svg
    folder = out / f"{name}.imageset"
    folder.mkdir()
    shutil.copy(svg, folder / svg.name)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": svg.name, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True},
    }, indent=2))
print(f"Art.xcassets: {len(seen)} 枚")
