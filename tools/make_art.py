"""アプリに入れる SVG を、下絵と取り出した部品から一括で作り、Hajime/Art/ のテーマごとのフォルダに書き出す。

使い方: python -P tools/make_art.py [名前 ...]   （名前を渡すと、その素材だけ作り直す）
下絵は C:\\Users\\user\\Hajime\\ai-trial-20261026（gen/ と gen/parts3/ は split_avatar.py と extract_part.py の出力）。
1つのフォルダは30ファイル以下にする（GitHub のブラウザからのアップロードは1回100ファイルまでで、フォルダごとに上げるため）。

決まり（仕様書「線の太さの決め直し」）: 内側の線は8px（--line-target 8）。顔のパーツ・まつ毛は太らせない。
外形12px と白ふちは、アプリで重ねて合成したあとに付けるので、ここでは描かない。
位置: アバターはどの部品も立ち姿の素体（refs/06_avatar_male_base.jpg）と同じだけ動かす。ワンのすけの小物は手を振る絵と同じだけ動かす。
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

T = Path(r"C:\Users\user\Hajime\ai-trial-20261026")
G, P = T / "gen", T / "gen" / "parts3"
ART = Path(__file__).resolve().parent.parent / "Hajime" / "Art"
AV_BASE = T / "refs" / "06_avatar_male_base.jpg"
WAN_BASE = G / "r01_wan_wave.jpg"
TOOLS = Path(__file__).resolve().parent

L = "#5A3A22"
# 色の組（前の SVG で使った色から、背景のマゼンタのにじみから来た紫の色を外したもの）
AV = [L, "#F1C7AE", "#EFCAAD", "#4AA9A3", "#FEFDFB", "#F4A7A7", "#6B4428"]
HAIR = [L, "#6B4428"]
WAN = [L, "#F0A242", "#FEF7ED", "#1FC7C1", "#F2A8A6", "#FCE3BA"]
PARKA = [L, "#2F5BD3", "#3E4788", "#E4ED43", "#F1C7AE"]
GYARU = ["auto", "3", "#FF5FA2", "#E8B931"]
HOST = [L, "#1E1E1E", "#C8A129", "#FEFDFB", "#F0C8AF"]
SHIBUYA = [L, "#22306B", "#D7333B", "#F2CAB1"]
CONSA = [L, "#D8C2A4", "#F3EDE3", "#C0A07C", "#EEC7AD"]
NEWYEAR = [L, "#C7283C", "#E1C699", "#AC956D", "#7F2936"]
XMAS = [L, "#C8283C", "#2E7D4F", "#FEFDFB", "#E8B931"]
WAN_NEWYEAR = [L, "#C8283C", "#E7B831", "#F7E6CA", "#913228", "#CC9252"]
WAN_GYARU = [L, "#FD60A0", "#E7B831", "#EF949A"]
WAN_HOST = [L, "#1E1E1E", "#C9A227", "#F9F2DF"]
WAN_SHIBUYA = [L, "#22306B", "#D7333B"]
WAN_CONSA = [L, "#F1EBE1", "#CDA070", "#EADDCD"]


def rows(lo, hi):
    """y が lo 以上 hi 未満の行だけを残す"""
    def f(m):
        out = np.zeros_like(m)
        out[lo:hi] = m[lo:hi]
        return out
    return f


def blobs(which):
    """かたまりの大きい順で which 番目（0 から）だけを残す"""
    def f(m):
        lab, n = ndimage.label(ndimage.binary_dilation(m, iterations=3))
        sizes = ndimage.sum(m, lab, range(1, n + 1))
        order = list(np.argsort(sizes)[::-1] + 1)
        keep = [order[i] for i in which if i < len(order)]
        return m & np.isin(lab, keep)
    return f


def bottom_rows(lo, hi):
    """y が lo 以上 hi 未満の行から、立ち姿の手を除いたものを残す。
    手は素体の手の部品が描くので、下の服に手が入ると大喜びのポーズで腰に手が浮く"""
    hands = np.asarray(Image.open(P / "std_hands.png").convert("RGBA"))[..., 3] > 0
    hands = ndimage.binary_dilation(hands, iterations=4)
    keep = rows(lo, hi)

    def f(m):
        return keep(m) & ~hands
    return f


def topmost(m):
    """いちばん上にあるかたまりだけを残す"""
    lab, n = ndimage.label(ndimage.binary_dilation(m, iterations=3))
    tops = [np.nonzero(lab == i)[0].min() for i in range(1, n + 1)]
    return m & (lab == int(np.argmin(tops)) + 1)


def below_top(m):
    return m & ~topmost(m)


# 名前: (フォルダ, 元画像, 切り分け, 色, 位置合わせの素体, 線をそろえるか, ごみの大きさ, 塗り替え)
JOBS = {}


def job(folder, name, src, colors, base=AV_BASE, cut=None, line=True, blob=300, recolor=None):
    JOBS[name] = (folder, src, cut, colors, base, line, blob, recolor or {})


# 初期の服は、どの服と合わせても浮かない無地の白い上と黒のパンツにする（2026-10-31、形とパターンのチーム）。
# 下絵は青緑のスウェットとベージュのパンツなので、塗りの色だけを替える。パンツの中の肌色とピンクは、にじみから来た色
WHITE, PANTS = "#F7F4EE", "#3E3F47"
DEFAULT_OUTFIT = {"top": {"#4AA9A3": WHITE},
                  "bottom": {"#EFCAAD": PANTS, "#F1C7AE": PANTS, "#F4A7A7": PANTS},
                  "feet": {"#EFCAAD": PANTS, "#F4A7A7": PANTS}}

# アバターの素体（部位ごと、2つのポーズ）
for pose in ["std", "joy"]:
    for part in ["headbase", "hands", "top", "bottom", "feet"]:
        job("avatar_body", f"av_{pose}_{part}", P / f"{pose}_{part}.png", AV, recolor=DEFAULT_OUTFIT.get(part))
# 顔（男女共通）、まつ毛、髪
job("avatar_face", "av_face_normal", P / "std_face.png", AV, line=False)
job("avatar_face", "av_face_smile", P / "smile_face.png", AV, line=False)
job("avatar_face", "av_face_joy", P / "joy_face.png", AV, line=False)
job("avatar_face", "av_lashes_std", P / "lstd_lashes.png", [L], line=False, blob=10)
job("avatar_face", "av_lashes_joy", P / "ljoy_lashes.png", [L], line=False, blob=10)
for key, src in [("short", "std"), ("bob", "fstd"), ("mash", "mash"), ("ponytail", "pony")]:
    job("avatar_face", f"av_hair_{key}", P / f"{src}_hair.png", HAIR)
# ワンのすけ（8つのポーズと、首の小物を付けるときのバンダナなし）
for pose, src in [("wave", G / "r01_wan_wave.jpg"), ("banzai", G / "r02_wan_banzai.jpg"),
                  ("clap", G / "r03_wan_clap.jpg"), ("blink", G / "r04_wan_blink.jpg"),
                  ("tehe", T / "01_wan_tehe.jpg"), ("nod", T / "02_wan_nod.jpg"),
                  ("gift", T / "04_wan_gift.jpg"), ("wow", T / "05_wan_wow.jpg")]:
    job("wan", f"wan_{pose}", src, WAN, base=None)
job("wan", "wan_wave_nobandana", G / "r10_wan_wave_nobandana.jpg", WAN, base=WAN_BASE)

# 服（テーマごと）。名前は「種類_テーマ_部位_ポーズ」。下・足・頭・首・手は2つのポーズで同じ絵を使う
job("street", "av_street_top_std", P / "b01_avatar_male_parka.png", PARKA)
job("street", "av_street_top_joy", P / "j01_avatar_male_joy_parka.png", PARKA)
job("gyaru", "av_gyaru_head", P / "o01_avatar_gyaru.png", GYARU, cut=rows(0, 330))
job("gyaru", "av_gyaru_top_std", P / "o01_avatar_gyaru.png", GYARU, cut=rows(330, 780))
job("gyaru", "av_gyaru_top_joy", P / "j02_avatar_male_joy_gyaru_vest.png", GYARU)
job("gyaru", "av_gyaru_feet", P / "o01_avatar_gyaru.png", GYARU, cut=rows(780, 1024))
job("gyaru", "wan_gyaru_head", P / "w02_wan_gyaru.png", WAN_GYARU, base=WAN_BASE)
job("host", "av_host_top_std", P / "o02_avatar_host.png", HOST, cut=rows(0, 530))
job("host", "av_host_top_joy", P / "j03_avatar_male_joy_host.png", HOST)
job("host", "av_host_bottom", P / "o02_avatar_host.png", HOST, cut=bottom_rows(530, 805))
job("host", "av_host_feet", P / "o02_avatar_host.png", HOST, cut=rows(805, 1024))
job("host", "wan_host_neck", P / "w03_wan_host.png", WAN_HOST, base=WAN_BASE)
job("shibuya", "av_shibuya_head", P / "o03_avatar_shibuya.png", SHIBUYA, cut=rows(0, 300))
job("shibuya", "av_shibuya_top_std", P / "o03_avatar_shibuya.png", SHIBUYA, cut=rows(300, 530))
job("shibuya", "av_shibuya_top_joy", P / "j04_avatar_male_joy_shibuya.png", SHIBUYA)
job("shibuya", "av_shibuya_bottom", P / "o03_avatar_shibuya.png", SHIBUYA, cut=bottom_rows(530, 805))
job("shibuya", "av_shibuya_feet", P / "o03_avatar_shibuya.png", SHIBUYA, cut=rows(805, 1024))
job("shibuya", "wan_shibuya_head", P / "w04_wan_shibuya.png", WAN_SHIBUYA, base=WAN_BASE)
job("consa", "av_consa_top_std", P / "o04_avatar_consa.png", CONSA, cut=rows(0, 530))
job("consa", "av_consa_top_joy", P / "j05_avatar_male_joy_consa.png", CONSA)
job("consa", "av_consa_bottom", P / "o04_avatar_consa.png", CONSA, cut=bottom_rows(530, 805))
job("consa", "av_consa_feet", P / "o04_avatar_consa.png", CONSA, cut=rows(805, 1024))
job("consa", "wan_consa_neck", P / "w05_wan_consa.png", WAN_CONSA, base=WAN_BASE)
job("newyear", "av_newyear_neck", P / "o05_avatar_newyear.png", NEWYEAR, cut=blobs([0]))
job("newyear", "av_newyear_hand", P / "o05_avatar_newyear.png", NEWYEAR, cut=blobs([1, 2, 3]))
job("newyear", "wan_newyear_head", P / "w01_wan_newyear.png", WAN_NEWYEAR, base=WAN_BASE, cut=topmost)
job("newyear", "wan_newyear_neck", P / "w01_wan_newyear.png", WAN_NEWYEAR, base=WAN_BASE, cut=below_top)
job("xmas", "av_xmas_head", P / "o06_avatar_xmas.png", XMAS, cut=rows(0, 330))
job("xmas", "av_xmas_hand", P / "o06_avatar_xmas.png", XMAS, cut=rows(330, 1024))


def cut_png(src, cut, tmp):
    img = np.asarray(Image.open(src).convert("RGBA")).copy()
    keep = cut(img[..., 3] > 128)
    img[..., 3] = np.where(keep, img[..., 3], 0)
    out = Path(tmp) / (src.stem + "_cut.png")
    Image.fromarray(img).save(out)
    return out


def main(names):
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        for name in names:
            folder, src, cut, colors, base, line, blob, recolor = JOBS[name]
            if cut:
                src = cut_png(src, cut, tmp)
            (ART / folder).mkdir(parents=True, exist_ok=True)
            cmd = [sys.executable, "-P", str(TOOLS / "svg_layers.py"), str(src), str(ART / folder / name), *colors,
                   "--min-blob", str(blob)]
            cmd += ["--align-from", str(base)] if base else []
            cmd += ["--line-target", "8"] if line else []
            r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
            print(r.stdout.strip() or r.stderr.strip()[-600:])
            if r.returncode:
                bad.append(name)
            fill = ART / folder / f"{name}_fill.svg"
            if recolor and fill.exists():
                text = fill.read_text(encoding="utf-8")
                for old, new in recolor.items():
                    text = text.replace(f'fill="{old}"', f'fill="{new}"')
                fill.write_text(text, encoding="utf-8")
            # 確かめ用の画像は Art/ に置かない（アプリに入れないため）
            check = ART / folder / f"{name}_check.png"
            if check.exists():
                dst = T / "art_check" / folder
                dst.mkdir(parents=True, exist_ok=True)
                check.replace(dst / check.name)
    for folder in sorted({j[0] for j in JOBS.values()}):
        n = len(list((ART / folder).glob("*.svg")))
        print(f"Art/{folder}: {n} ファイル" + ("（30を超えている）" if n > 30 else ""))
    print("NG:", bad)
    return not bad


if __name__ == "__main__":
    sys.exit(0 if main(sys.argv[1:] or list(JOBS)) else 1)
