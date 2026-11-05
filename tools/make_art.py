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
# 2026-11-05、衣装の目利きチームの判定で描き直したストリート（キャップの穴から見える髪と首の肌を含む）と、ふんわり淡色（社内の呼び名は韓国系）
STREET = [L, "#2F5BD3", "#E3F03A", "#6B4428", "#F1C7AE"]
FUWARI = [L, "#B9A8DC", "#B5ABA0"]
WAN_STREET = [L, "#2F5BD3", "#E3F03A", "#F0A242"]
WAN_FUWARI = [L, "#B9A8DC", "#B5ABA0", "#FEF7ED"]
WAN_XMAS = [L, "#B5814A", "#2E7D4F", "#C8283C", "#E8B931"]
OUCHI = [L, "#D3A6AE", "#B9B7B2", "#F1C7AE"]
WAN_OUCHI = [L, "#D3A6AE", "#B9B7B2"]
KISSA = [L, "#6CBF52", "#F3E3A0", "#E6CF7A"]
WAN_KISSA = [L, "#C8283C", "#6CBF52"]
OUTDOOR = [L, "#8C8B4E", "#86B8E8", "#6B4428"]
WAN_OUTDOOR = [L, "#8C8B4E", "#86B8E8"]
SPORTS = [L, "#1E9E5A", "#F2C230", "#F1C7AE"]
WAN_SPORTS = [L, "#1E9E5A", "#F2C230"]


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


def frame_of(src, color, lo, hi, reach=5):
    """めがねの縁だけを残す（y が lo 以上 hi 未満で、縁の色とそのすぐそばの線）。
    レンズの中に描かれた目を残すと、大喜びの顔の上に開いた目が出るため"""
    rgb = np.array([int(color[i:i + 2], 16) for i in (1, 3, 5)])

    def f(m):
        img = np.asarray(Image.open(src).convert("RGB")).astype(int)
        near = np.abs(img - rgb).sum(-1) < 60
        keep = ndimage.binary_dilation(near, iterations=reach)
        return rows(lo, hi)(m & keep)
    return f


def colors_of(src, colors, then=None, reach=5, tol=70):
    """決まった色とそのすぐそばの線だけを残す。ワンのすけの首の小物に毛の色がまじって取れたとき、
    ほかのポーズで小物を動かすと毛の色がずれて見えるので外す"""
    rgbs = [np.array([int(c[i:i + 2], 16) for i in (1, 3, 5)]) for c in colors]

    def f(m):
        img = np.asarray(Image.open(src).convert("RGB")).astype(int)
        near = np.zeros(m.shape, bool)
        for rgb in rgbs:
            near |= np.abs(img - rgb).sum(-1) < tol
        keep = m & ndimage.binary_dilation(near, iterations=reach)
        return then(keep) if then else keep
    return f


# 名前: (フォルダ, 元画像, 切り分け, 色, 位置合わせの素体, 線をそろえるか, ごみの大きさ, 塗り替え)
JOBS = {}


_current = {}
AV_JOY_BASE = G / "r06_avatar_male_joy.jpg"


def foreign(base_path, then=None, tol=45, close=2, edge=12):
    """素体の絵にもともとある線や色 (髪・あご・手・腕・耳) の切れ端を消す。
    部品の絵 (着せた全身から取ったもの) のうち、素体の同じ位置とほぼ同じ色のところは、服ではなく体なので除く。
    除いたあとにできた細いすき間は閉じ、小さな島は捨てる。
    2026-11-05、ユーザーの指摘 (丸めがねの左右に髪、雲のベストの裾に手、ハートのサングラスの左下がガタガタ) で足した"""
    def f(m):
        m = then(m) if then else m
        img = _current["img"][..., :3].astype(int)
        base = np.asarray(Image.open(base_path).convert("RGB").resize(img.shape[1::-1])).astype(int)
        same = np.abs(img - base).sum(-1) < tol
        # 切れ端は部品の外側の縁にだけある。内側まで消すと、素体と色が近い帽子などに穴や切れ目ができるので、縁から edge px 以内に限る
        rim = m & ~ndimage.binary_erosion(m, iterations=edge)
        keep = m & ~(same & rim)
        keep = ndimage.binary_closing(keep, iterations=close) & m
        keep = ndimage.binary_fill_holes(keep) & m
        lab, n = ndimage.label(keep)
        if n:
            sizes = ndimage.sum(keep, lab, range(1, n + 1))
            keep &= np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 80])
        return keep
    return f


def row_hull(colors, margin=9, then=None, tol=70):
    """行ごとに、部品の決まった塗りの色がある左右の端から margin px より外を消す。
    袖のないベストの脇に残る腕や手のとげ、めがねのつるの外に垂れた髪など、横に飛び出した切れ端に効く"""
    fills = [np.array([int(c[i:i + 2], 16) for i in (1, 3, 5)]) for c in colors
             if c.startswith("#") and c.upper() != L]

    def f(m):
        m = then(m) if then else m
        img = _current["img"][..., :3].astype(int)
        fill = np.zeros(m.shape, bool)
        for rgb in fills:
            fill |= np.abs(img - rgb).sum(-1) < tol
        fill &= m
        fill = ndimage.binary_opening(fill, iterations=1)  # にじみの細い点は端に数えない
        out = np.zeros_like(m)
        h = m.shape[0]
        for y in range(h):
            ys = slice(max(y - 2, 0), min(y + 3, h))  # 上下 2 行も見て、線だけの行 (裾や縁) を残す
            xs = np.nonzero(fill[ys].any(0))[0]
            if len(xs):
                lo, hi = max(xs.min() - margin, 0), xs.max() + margin + 1
                out[y, lo:hi] = m[y, lo:hi]
            else:  # 塗りの色が見つからない行 (細いつるなど) は削らない
                out[y] = m[y]
        return out
    return f


def trimmed(reach, colors, then=None, close=3, tol=70):
    """部品の外側に残った、ほかの体の線や色の切れ端 (髪の毛・手・腕・目のまわり・背景のにじみ) を削る。
    取り出すときに部品のそばの線を拾い直すので、隣の髪や手の線まで付いてくる。
    部品の塗りの面 (その部品の決まった色に近いところ。穴は埋める) から reach px より外にあるものを消す。
    reach は線 1 本ぶん (6〜10)。
    2026-11-05、ユーザーの指摘 (丸めがねの左右に髪、雲のベストの裾に手、ハートのサングラスの左下がガタガタ) で足した"""
    fills = [np.array([int(c[i:i + 2], 16) for i in (1, 3, 5)]) for c in colors
             if c.startswith("#") and c.upper() != L]

    def f(m):
        m = then(m) if then else m
        img = _current["img"][..., :3].astype(int)
        fill = np.zeros(m.shape, bool)
        for rgb in fills:
            fill |= np.abs(img - rgb).sum(-1) < tol
        fill &= m
        lab, n = ndimage.label(fill)
        if n:  # 線のすき間に残った小さな塗りの点は、面として扱わない
            sizes = ndimage.sum(fill, lab, range(1, n + 1))
            fill &= np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 20])
        body = ndimage.binary_fill_holes(ndimage.binary_closing(fill, iterations=close))
        keep = m & ndimage.binary_dilation(body, iterations=reach)
        lab, n = ndimage.label(keep)
        if n:
            sizes = ndimage.sum(keep, lab, range(1, n + 1))
            keep &= np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 40])
        return keep
    return f


# デザイナーのチェック (2026-11-05) で、優先度「高」「中」で切れ端を指摘された部品と、そのあと足した部品。
# 全部にかけると、素体と色が近い帽子 (ワンのすけのバケットハット、ストリートのキャップ) に切れ目ができたので、指摘されたものだけにする
CLEAN = {
    "av_gyaru_head", "av_fuwari_face", "av_fuwari_top_std", "av_fuwari_top_joy", "av_newyear_hand", "av_xmas_hand",
    "av_outdoor_head", "wan_kissa_head", "av_consa_top_joy", "av_consa_top_std", "av_host_top_std", "av_shibuya_top_std",
    "wan_consa_neck", "av_kissa_top_joy", "av_kissa_top_std", "av_outdoor_top_joy", "av_outdoor_top_std",
    "av_gyaru_top_joy", "av_gyaru_top_std", "av_newyear_neck", "av_shibuya_head", "wan_shibuya_head",
    "av_street_top_joy", "wan_street_head", "wan_host_neck",
    "av_amekaji_top_std", "av_amekaji_top_joy",  # wan_amekaji_head は掃除で横に白い切れ目が出たのでかけない
    "av_trad_head", "av_trad_top_std", "av_trad_top_joy", "wan_trad_head",
}


def body_of(name, src):
    """服の部品を取り出したときの素体 (切れ端を見分けるのに使う)"""
    if name.startswith("wan_"):
        return G / "r10_wan_wave_nobandana.jpg" if "_neck" in name else WAN_BASE
    return AV_JOY_BASE if "_joy" in name else AV_BASE


def job(folder, name, src, colors, base=AV_BASE, cut=None, line=True, blob=300, recolor=None, trim=None, clean=None):
    if trim:
        cut = trimmed(trim, colors, cut)
    # 素体の髪・あご・手・耳の切れ端を消してから横のとげを削る (2026-11-05、デザイナーのチェック)。
    # 下と足は、素体のズボンや靴と同じ形・近い色のことがあり、消しすぎるのでかけない
    if clean is None:
        clean = name in CLEAN
    if clean:
        cut = foreign(body_of(name, src), cut, tol=50)
        # 色を自動で選ぶ組 (auto) は決まった塗りの色がわからないので、横のとげは削らない
        if "auto" not in colors:
            cut = row_hull(colors, 9, cut)
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
# ストリートは 2026-11-05 に描き直した（パーカーを大きめに、矢印を太く。前の版は b01・j01 と PARKA の色）。
# 靴は元より大きく描かれたので、shift_part.py で靴底を素体の足元にそろえたものを使う
job("street", "av_street_head", P / "o07_avatar_street.png", STREET, cut=rows(0, 285))
job("street", "av_street_top_std", P / "o07_avatar_street.png", STREET, cut=rows(285, 612))
job("street", "av_street_top_joy", P / "j06_avatar_male_joy_street.png", STREET)
job("street", "av_street_feet", P / "o07_avatar_street_feet.png", STREET)
job("street", "wan_street_head", P / "w06_wan_street.png", WAN_STREET, base=WAN_BASE)
job("fuwari", "av_fuwari_face", P / "o08_avatar_korea.png", FUWARI,
    cut=frame_of(G / "o08c_avatar_korea.jpg", "#B5ABA0", 200, 290), line=False, blob=30)
job("fuwari", "av_fuwari_top_std", P / "o08_avatar_korea.png", FUWARI, cut=rows(290, 584))
job("fuwari", "av_fuwari_top_joy", P / "j07_avatar_male_joy_korea.png", FUWARI)
job("fuwari", "av_fuwari_bottom", P / "o08_avatar_korea.png", FUWARI, cut=bottom_rows(584, 810))
job("fuwari", "wan_fuwari_neck", P / "w07_wan_korea.png", WAN_FUWARI, base=WAN_BASE)
# クリスマスのワンのすけ（2026-11-05。判定で赤い実をやめ、角を明るい黄土色にした）。首輪は毛の色を外す
job("xmas", "wan_xmas_head", P / "w08_wan_xmas.png", WAN_XMAS, base=WAN_BASE, cut=topmost)
job("xmas", "wan_xmas_neck", P / "w08_wan_xmas.png", WAN_XMAS, base=WAN_BASE,
    cut=colors_of(G / "w08b_wan_xmas.jpg", ["#C8283C", "#E8B931"], then=rows(400, 700), tol=40))
# おうちゆる（2026-11-05。判定でボタンを大きく3つ、裾に灰ピンクの帯、細いヘアバンド）。
# 下は差では中の色が薄く抜けたので、首より下の肌以外を取った region の絵から切る
job("ouchi", "av_ouchi_top_std", P / "o09_avatar_ouchi.png", OUCHI, cut=rows(290, 572))
job("ouchi", "av_ouchi_top_joy", P / "j08_avatar_male_joy_ouchi.png", OUCHI)
job("ouchi", "av_ouchi_bottom", P / "o09_avatar_ouchi_region.png", OUCHI, cut=bottom_rows(572, 802))
job("ouchi", "av_ouchi_feet", P / "o09_avatar_ouchi_feet.png", OUCHI)
job("ouchi", "wan_ouchi_head", P / "w09_wan_ouchi.png", WAN_OUCHI, base=WAN_BASE)
# レトロ喫茶（2026-11-05）。判定で手に持つクリームソーダを外し、丸いグラスはベストの胸のワッペンにした。
# スラックスは素体のズボンと色が近く差で取れないので、region の絵から切る
job("kissa", "av_kissa_top_std", P / "o10_avatar_kissa.png", KISSA)
job("kissa", "av_kissa_top_joy", P / "j09_avatar_male_joy_kissa.png", KISSA)
job("kissa", "av_kissa_bottom", P / "o10_avatar_kissa_region.png", KISSA, cut=bottom_rows(532, 805))
job("kissa", "wan_kissa_head", P / "w10_wan_kissa.png", WAN_KISSA, base=WAN_BASE)
# アウトドアとスポーツMIX (2026-11-05)。判定でワッペンを大きく、ポケットを空色、靴を 2 色、ワンのすけの帽子を小さく。
# スポーツは上下そろいの緑ジャージが「イカゲーム」や体操服に見えるので、肩から胸を黄の切り替え、袖の短い 2 本線、パンツは無地。
# 大喜びのベストは裾の下にスウェットの色が入るので高さで切る。ジャージの下は差では薄いので region から切る。
# ワンのすけのヘッドバンドは Gemini が線を 2 本描くので one_stripe.py で 1 本にしたものを使う
job("outdoor", "av_outdoor_head", P / "o11_avatar_outdoor.png", OUTDOOR, cut=rows(0, 290))
job("outdoor", "av_outdoor_top_std", P / "o11_avatar_outdoor.png", OUTDOOR, cut=rows(290, 560))
job("outdoor", "av_outdoor_top_joy", P / "j10_avatar_male_joy_outdoor.png", OUTDOOR, cut=rows(0, 530))
job("outdoor", "av_outdoor_feet", P / "o11_avatar_outdoor_feet.png", OUTDOOR)
job("outdoor", "wan_outdoor_head", P / "w11_wan_outdoor.png", WAN_OUTDOOR, base=WAN_BASE)
job("sports", "av_sports_top_std", P / "o12_avatar_sports.png", SPORTS, cut=rows(290, 530))
job("sports", "av_sports_top_joy", P / "j11_avatar_male_joy_sports.png", SPORTS)
job("sports", "av_sports_bottom", P / "o12_avatar_sports_region.png", SPORTS, cut=bottom_rows(528, 805))
job("sports", "av_sports_feet", P / "o12_avatar_sports_feet.png", SPORTS)
job("sports", "wan_sports_head", P / "w12_wan_sports_one.png", WAN_SPORTS, base=WAN_BASE)
# 古着アメカジと雨の日トラッド (2026-11-05。判定は「直して進める」で、直した正面図 o13c・o14c から取る)。
# アメカジは素体のスウェットと色が近く差では青い面が抜けるので、region の絵から高さで切る。
# 大喜びのアメカジも差では青い袖が抜けるので、肌以外すべての絵から、シャツの 2 色とそのそばの線だけを取る
AMEKAJI = [L, "#5B80B0", "#A4603B"]
TRAD = [L, "#2E6B50", "#1F2A44", "#C49A6C", "#85563C"]
WAN_AMEKAJI = [L, "#5B80B0", "#A4603B"]
WAN_TRAD = [L, "#2E6B50", "#1F2A44"]
job("amekaji", "av_amekaji_top_std", P / "o13_avatar_amekaji_region.png", AMEKAJI, cut=bottom_rows(305, 548))
job("amekaji", "av_amekaji_top_joy", P / "j12_avatar_male_joy_amekaji_region.png", AMEKAJI,
    cut=colors_of(G / "j12_avatar_male_joy_amekaji.jpg", ["#5479AD", "#904240"], then=rows(150, 545), reach=6, tol=45))
job("amekaji", "av_amekaji_bottom", P / "o13_avatar_amekaji_region.png", AMEKAJI, cut=bottom_rows(548, 805))
# 靴は元より大きく描かれたので、shift_part.py で靴底を素体の足元にそろえたもの (アメカジ -17px、トラッド -18px)
job("amekaji", "av_amekaji_feet", P / "o13_avatar_amekaji_feet.png", AMEKAJI)
job("amekaji", "wan_amekaji_head", P / "w13_wan_amekaji.png", WAN_AMEKAJI, base=WAN_BASE)
job("trad", "av_trad_head", P / "o14_avatar_trad.png", TRAD, cut=rows(0, 300))
job("trad", "av_trad_top_std", P / "o14_avatar_trad.png", TRAD, cut=rows(300, 600))
job("trad", "av_trad_top_joy", P / "j13_avatar_male_joy_trad.png", TRAD)
job("trad", "av_trad_feet", P / "o14_avatar_trad_feet.png", TRAD)
job("trad", "wan_trad_head", P / "w14_wan_trad.png", WAN_TRAD, base=WAN_BASE)
# ハートのサングラスの下に、ピンクの毛の切れ端が 2 つ浮いていた (デザイナーのチェック) ので、いちばん大きいかたまりだけ残す
job("gyaru", "av_gyaru_head", P / "o01_avatar_gyaru.png", GYARU, cut=lambda m: blobs([0])(rows(0, 330)(m)))
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
    _current["img"] = img
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
