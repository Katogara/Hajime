import SwiftUI

/// 今のレベルと、次のレベルまでの経験値 (分子 / 分母)。どの画面でも上の方に出す。
struct LevelBadge: View {
    let progress: LevelProgress

    var body: some View {
        HStack(spacing: 10) {
            Text(progress.graduated ? "🎓" : "Lv.\(progress.level)")
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Pop.orange))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(progress.graduated ? "Lv.\(progress.level) 卒業" : progress.title)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Pop.ink.opacity(0.7))
                    Spacer()
                    if !progress.graduated {
                        Text("\(progress.current) / \(progress.needed) EXP")
                            .font(.system(.caption, design: .rounded, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(Pop.ink)
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Pop.orange.opacity(0.15))
                        Capsule().fill(Pop.yellow)
                            .frame(width: max(8, proxy.size.width * progress.fraction))
                    }
                }
                .frame(height: 8)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Pop.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.graduated ? "レベル100、卒業"
                            : "レベル\(progress.level)、経験値 \(progress.current) / \(progress.needed)")
    }
}
