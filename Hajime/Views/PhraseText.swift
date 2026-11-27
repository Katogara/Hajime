import BudouX
import SwiftUI

/// 日本語を文節の切れ目だけで折り返す。
/// 日本語には単語の間の空白がないので、そのままでは「イノベーシ／ョン」のように語の途中で折り返されることがある。
/// 改行の位置は `\n` で決め打ちせず (画面の幅が変わると半端な行ができる)、BudouX で文節に分けて幅に任せる。
/// BudouX の分け方には次の手直しを加える。
/// - 短いカギ括弧・丸括弧の中では折り返さない (「は／じめる」「（の／こり」を防ぐ)
/// - 「「」で行を終えず、「」」「、」「！」などで行を始めない (禁則)
/// - アプリでよく出る語 (はじめる、のこり、やること) の途中では折り返さない (「は」を助詞と見なして切るため)
enum Phrases {
    private static let parser = Parser()
    private static let protectedWords: [[Character]] = ["はじめ", "のこり", "やること"].map { Array($0) }
    private static let pairs: [Character: Character] = ["「": "」", "『": "』", "（": "）", "(": ")"]
    /// これより長い括弧の中は、ふつうに文節で折り返す
    private static let maxGroup = 12
    private static let opening: Set<Character> = ["「", "『", "（", "(", "[", "【", "〈", "《", "“"]
    private static let noLineStart = Set<Character>("」』）)]】〉》”、。，．！？!?ー…")

    /// 文節に分ける (例: 「最初の一歩を登録する」→「最初の一歩を」「登録する」)
    static func split(_ text: String) -> [String] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }
        // 折り返してよい位置 (その文字の前で折り返す)
        var cuts = Set<Int>()
        var position = 0
        for chunk in parser.parse(sentence: text).dropLast() {
            position += chunk.count
            cuts.insert(position)
        }
        for word in protectedWords where word.count <= chars.count {
            for start in 0...(chars.count - word.count) where Array(chars[start..<start + word.count]) == word {
                cuts.subtract((start + 1)..<(start + word.count))
            }
        }
        for (start, character) in chars.enumerated() {
            guard let close = pairs[character],
                  let end = chars[(start + 1)...].firstIndex(of: close),
                  end - start <= maxGroup else { continue }
            cuts.subtract((start + 1)...end)
        }
        for cut in cuts.sorted() where opening.contains(chars[cut - 1]) {
            cuts.remove(cut)
            if cut - 1 > 0 { cuts.insert(cut - 1) }
        }
        cuts = cuts.filter { $0 > 0 && $0 < chars.count && !noLineStart.contains(chars[$0]) }

        var result: [String] = []
        var start = 0
        for cut in cuts.sorted() {
            result.append(String(chars[start..<cut]))
            start = cut
        }
        result.append(String(chars[start...]))
        return result
    }

    /// 文節の中では折り返さない文字列にする (文節の中の文字を Word Joiner でつなぎ、文節の間にゼロ幅スペースを入れる)
    static func wrapped(_ text: String) -> String {
        split(text).map(unbreakable).joined(separator: Parser.zeroWidthSpace)
    }

    /// どこでも折り返さない文字列にする
    static func unbreakable(_ text: String) -> String {
        text.map { String($0) }.joined(separator: Parser.wordJoiner)
    }

    /// 句読点 (、。！？) の後ろで行を分けた文字列。分ける所がなければ nil
    static func punctuationLines(_ text: String) -> String? {
        var lines: [String] = []
        var line = ""
        for character in text {
            line.append(character)
            if "、。！？".contains(character) {
                lines.append(line)
                line = ""
            }
        }
        if !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line) }
        guard lines.count > 1 else { return nil }
        return lines.map(unbreakable).joined(separator: "\n")
    }
}

/// 文節の切れ目だけで折り返す文。文や説明はこれで出す。
/// 前は 1 つの `Text` (文節の中を Word Joiner でつなぐ) だったが、iOS がつなぎを無視して
/// 「最初の一歩に／、ちゃんと」と読点の前で折り返した (2026-11-27 のユーザーの画面)。
/// 見出しと同じく、文節を並べる位置を自分で決める (PhraseFlow)。
struct PhraseText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        PhraseFlow(text: text)
    }
}

/// 見出しや褒め言葉。1 行に収まればそのまま、収まらなければ句読点の後ろで行を分け、
/// それでも収まらないときだけ文節で折り返す (「考える前に、もう／始めている」のような切れ方を防ぐ)
struct HeadlineText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    // ViewThatFits は、折り返せる Text を「折り返せば収まる」と見なして最初の案を選んでしまう。
    // 1 行の案と句読点で分けた案は、横に折り返せないよう fixedSize で固め、本当に幅に収まるときだけ選ばれるようにする
    // (固めないと、文節を無視した位置で iOS に無理やり折り返される。例:「あなたの「／はじめる」を」)
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(verbatim: Phrases.unbreakable(text))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let lines = Phrases.punctuationLines(text) {
                Text(verbatim: lines)
                    .fixedSize(horizontal: true, vertical: false)
            }
            PhraseFlow(text: text)
        }
    }
}

/// 文節ごとに別の Text にして並べ、文節の間だけで折り返す。
/// PhraseText (文節の中を Word Joiner でつなぐ) でも、iOS が「あなたの「／はじめる」を」と括弧の直後で折り返した
/// (2026-11-17 に ViewThatFits を直したあとも、2026-11-25 のユーザーの画面で同じ切れ方が残っていた)。
/// 1 つの Text の中の折り返しは iOS に任せるしかないので、文節を並べる位置を自分で決める (見出しと PhraseText)
private struct PhraseFlow: View {
    let text: String
    @Environment(\.multilineTextAlignment) private var alignment

    var body: some View {
        PhraseFlowLayout(alignment: alignment) {
            ForEach(Array(Phrases.split(text).enumerated()), id: \.offset) { _, phrase in
                Text(verbatim: Phrases.unbreakable(phrase))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }
}

/// 文節を左から詰め、幅を超える文節から次の行にする。行は multilineTextAlignment に合わせて寄せる。
/// 1 つの文節だけで幅を超えるときは、その文節の中で折り返す
private struct PhraseFlowLayout: Layout {
    var alignment: TextAlignment

    private struct Row {
        var range: Range<Int>
        var sizes: [CGSize]
        var width: CGFloat { sizes.reduce(0) { $0 + $1.width } }
        var height: CGFloat { sizes.map(\.height).max() ?? 0 }
    }

    private func rows(_ subviews: Subviews, width: CGFloat?) -> [Row] {
        var rows: [Row] = []
        var current = Row(range: 0..<0, sizes: [])
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if let width, !current.sizes.isEmpty, current.width + size.width > width + 0.5 {
                rows.append(current)
                current = Row(range: index..<index, sizes: [])
            }
            current.sizes.append(size)
            current.range = current.range.lowerBound..<(index + 1)
        }
        if !current.sizes.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height })
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x: CGFloat
            switch alignment {
            case .leading: x = bounds.minX
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX + (bounds.width - row.width) / 2
            }
            for (offset, index) in row.range.enumerated() {
                let size = row.sizes[offset]
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: size.width, height: size.height))
                x += size.width
            }
            y += row.height
        }
    }
}
