import SwiftUI

/// 最初の一歩を、画面の主役として大きく見せる。
/// `beckoning` のあいだは、文字が一文字ずつ順にぴょこっと跳ねて「まってるよ」と呼びかける。
struct WaitingStep: View {
    let step: String
    var beckoning = true

    /// 跳ねる波が一巡する間隔 (秒)
    private let cycle = 2.4
    /// 1 文字が跳ねている時間
    private let hop = 0.36
    /// 隣の文字が跳ね始めるまでのずれ
    private let stagger = 0.07

    private var fontSize: CGFloat { step.count > 14 ? 32 : 44 }

    var body: some View {
        VStack(spacing: 14) {
            Text(beckoning ? "👀 まってるよ" : "👣 まずはこれ")
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(Pop.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Pop.orange.opacity(0.14)))
            TimelineView(.animation(paused: !beckoning)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                FlowLayout {
                    ForEach(Array(step.enumerated()), id: \.offset) { index, character in
                        Text(String(character))
                            .font(.system(size: fontSize, weight: .black, design: .rounded))
                            .foregroundStyle(Pop.ink)
                            .offset(y: beckoning ? lift(index: index, time: t) : 0)
                    }
                }
                // ゆっくり息をしているように、わずかに大きさを変える
                .scaleEffect(beckoning ? 1 + 0.025 * sin(t * 2.2) : 1)
                .rotationEffect(.degrees(beckoning ? 1.5 * sin(t * 1.3) : 0))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Pop.card))
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Pop.orange.opacity(0.35)).offset(y: 7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最初の一歩: \(step)")
    }

    /// その文字の今の浮き上がり (上向きが負)
    private func lift(index: Int, time: TimeInterval) -> CGFloat {
        let phase = time.truncatingRemainder(dividingBy: cycle) - Double(index) * stagger
        guard phase > 0, phase < hop else { return 0 }
        return -CGFloat(sin(phase / hop * .pi)) * fontSize * 0.32
    }
}

/// 子を左から並べ、幅が足りなくなったら折り返す。各行は中央にそろえる。
struct FlowLayout: Layout {
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - line.width) / 2
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                                      proposal: .unspecified)
                x += size.width
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !line.indices.isEmpty, line.width + size.width > width {
                lines.append(line)
                line = Line()
            }
            line.indices.append(index)
            line.width += size.width
            line.height = max(line.height, size.height)
        }
        if !line.indices.isEmpty { lines.append(line) }
        return lines
    }
}
