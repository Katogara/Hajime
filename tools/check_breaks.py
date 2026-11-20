"""アプリの日本語の文言を BudouX で文節に分け、PhraseText と同じ手直し (Views/PhraseText.swift の Phrases.split) を
かけたときに、長すぎて画面の幅を超えそうな文節を洗い出す。

使い方: pip install budoux のあと python -X utf8 tools/check_breaks.py Hajime > 結果.txt

- 文節が画面の幅より長いと、iOS は文節を無視して文字の途中で無理に折り返す。9 文字以上の文節と、PhraseText を通さない
  14 文字以上の Text を出す。\\(…) はＸＸに置き換えて数える
- 見出し (HeadlineText) は、ViewThatFits の案が本当に幅に収まるときだけ選ばれるか (fixedSize) も合わせて確かめる。
  2026-11-17、1 行の案がいつも選ばれて「あなたの「／はじめる」を」と切れていた
"""
import re, sys, pathlib, budoux
p = budoux.load_default_japanese_parser()
PROT = ["はじめ", "のこり", "やること"]
PAIRS = {"「": "」", "『": "』", "（": "）", "(": ")"}
OPEN = set("「『（([【〈《“")
NOSTART = set("」』）)]】〉》”、。，．！？!?ー…")

def split(t):
    ch = list(t)
    cuts, pos = set(), 0
    for c in p.parse(t)[:-1]:
        pos += len(c); cuts.add(pos)
    for w in PROT:
        for s in range(len(ch) - len(w) + 1):
            if t[s:s+len(w)] == w: cuts -= set(range(s+1, s+len(w)))
    for s, c in enumerate(ch):
        if c in PAIRS:
            try: e = ch.index(PAIRS[c], s+1)
            except ValueError: continue
            if e - s <= 12: cuts -= set(range(s+1, e+1))
    for c in sorted(cuts):
        if ch[c-1] in OPEN:
            cuts.discard(c)
            if c-1 > 0: cuts.add(c-1)
    cuts = sorted(c for c in cuts if 0 < c < len(ch) and ch[c] not in NOSTART)
    out, st = [], 0
    for c in cuts: out.append(t[st:c]); st = c
    out.append(t[st:]); return out

jp = re.compile(r'[぀-ヿ一-鿿]')
lit = re.compile(r'"((?:[^"\\]|\\.)*)"')
root = pathlib.Path(sys.argv[1])
plain = []
for f in sorted(root.rglob("*.swift")):
    for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
        s = line.strip()
        if s.startswith("//") or s.startswith("///"): continue
        for m in lit.finditer(line):
            t = m.group(1)
            if not jp.search(t): continue
            t2 = re.sub(r'\\\(.*?\)', 'ＸＸ', t)
            chunks = split(t2)
            longest = max(chunks, key=len)
            kind = "Phrase" if "PhraseText(" in line else "Headline" if "HeadlineText(" in line else "Text" if re.search(r'\bText\(', line) else "other"
            if len(longest) >= 9 or (kind == "Text" and len(t2) >= 14):
                print(f"{f.name}:{n} [{kind}] 最長{len(longest)}「{longest}」 ← {t2}")
