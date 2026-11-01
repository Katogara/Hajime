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
        .accessibilityLabel(progress.accessibilityText)
    }
}

/// 一覧のレベル表示。右に 2 人を立たせるので、縦に詰める (大きな Lv、経験値のバー、次のレベルまで)
struct LevelColumn: View {
    let progress: LevelProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(progress.graduated ? "🎓 Lv.\(progress.level)" : "Lv.\(progress.level)")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .foregroundStyle(Pop.orange)
                    .fixedSize()
                Text(progress.graduated ? "卒業" : progress.title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Pop.ink.opacity(0.7))
                    .lineLimit(2)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Pop.orange.opacity(0.15))
                    Capsule().fill(Pop.yellow)
                        .frame(width: max(8, proxy.size.width * progress.fraction))
                }
            }
            .frame(height: 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
            if !progress.graduated {
                Text("\(progress.current) / \(progress.needed) EXP ・ あと\(progress.needed - progress.current)で次へ")
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Pop.ink)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Pop.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.accessibilityText)
    }
}

private extension LevelProgress {
    var accessibilityText: String {
        graduated ? "レベル100、卒業" : "レベル\(level)、経験値 \(current) / \(needed)"
    }
}
