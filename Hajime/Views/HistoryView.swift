import SwiftUI

/// 「これまでのつみあげ」。日ごとに、経験値がたまった記録とレベルアップを並べる。やらなかった日は出さない。
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let stats = StartStats(records: model.records, now: .now)
        let days = DayLog.build(records: model.records, levelUps: model.levelUps)
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    LevelBadge(progress: model.level)
                    HStack(spacing: 12) {
                        StatCard(emoji: "🔥", value: "\(stats.count)回", label: "この7日間に始めた", color: Pop.orange)
                        StatCard(emoji: "⚡️", value: stats.medianDelay.map(StartStats.format) ?? "—",
                                 label: "通知から始めるまで", color: Pop.yellow)
                    }
                    PhraseText("通知から始めるまでの時間は、この7日間に通知から始めた分の中央値です。")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pop.ink.opacity(0.55))
                    if days.isEmpty {
                        PhraseText("まだありません。最初の1回、楽しみにしています 🌱")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Pop.ink.opacity(0.6))
                            .popCard()
                    }
                    ForEach(days) { day in
                        DaySection(log: day)
                    }
                }
                .padding(20)
            }
            .popBackground()
            .navigationTitle("これまでのつみあげ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

private struct StatCard: View {
    let emoji: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(emoji)
                .font(.system(size: 30))
            Text(value)
                .font(.system(.title, design: .rounded, weight: .black))
                .foregroundStyle(Pop.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            PhraseText(label)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Pop.ink.opacity(0.6))
        }
        .popCard(tint: color)
    }
}

/// 1 日分。レベルアップを先に、そのあと始めたことを時刻順に
private struct DaySection: View {
    let log: DayLog

    private var heading: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(log.day) { return "今日" }
        if calendar.isDateInYesterday(log.day) { return "きのう" }
        return log.day.formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(heading)
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .foregroundStyle(Pop.ink)
                Spacer()
                Text("\(log.records.count)回はじめた")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Pop.orange)
            }
            .padding(.top, 8)
            ForEach(Array(log.levelUps.enumerated()), id: \.offset) { _, event in
                RainbowLevelUp(event: event)
            }
            ForEach(log.records) { record in
                RecordRow(record: record)
            }
        }
    }
}

/// レベルアップの行。虹色の枠が回り、文字も虹色に流れる
private struct RainbowLevelUp: View {
    let event: LevelUpEvent

    private static let rainbow: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink, .red]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(t.truncatingRemainder(dividingBy: 4) / 4 * 360)
            let graduated = event.level >= LevelTable.maxLevel
            HStack(spacing: 12) {
                Text(graduated ? "🎓" : "🏆")
                    .font(.system(size: 34))
                    .rotationEffect(.degrees(sin(t * 3) * 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(graduated ? "卒業！" : "LEVEL UP!")
                        .font(.system(.title3, design: .rounded, weight: .black))
                        .foregroundStyle(LinearGradient(colors: Self.rainbow,
                                                        startPoint: UnitPoint(x: -1 + sin(t) , y: 0),
                                                        endPoint: UnitPoint(x: 1 + sin(t), y: 1)))
                    PhraseText("Lv.\(event.level)「\(LevelTable.title(for: event.level))」になった")
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .foregroundStyle(Pop.ink)
                }
                Spacer(minLength: 0)
                Text("✨")
                    .font(.system(size: 22))
                    .scaleEffect(0.7 + (sin(t * 4) + 1) / 2 * 0.6)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AngularGradient(colors: Self.rainbow, center: .center, angle: angle).opacity(0.18))
            )
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Pop.card))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AngularGradient(colors: Self.rainbow, center: .center, angle: angle),
                                  lineWidth: 4)
            )
            .shadow(color: .pink.opacity(0.3), radius: 8, y: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("レベル\(event.level)にレベルアップ")
    }
}

private struct RecordRow: View {
    let record: StartRecord

    private var detail: String {
        var parts: [String] = []
        if let delay = record.delay {
            parts.append("通知から\(StartStats.format(delay))")
        }
        // 取り組んだ時間は数えない (管理はしない)。やめたことも書かない (責めない)
        if record.outcome == .continued {
            parts.append("やりました")
        }
        return parts.joined(separator: "・")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(record.outcome == .continued ? "🎉" : "✅")
                .font(.system(size: 26))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    PhraseText(record.taskTitle)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(Pop.ink)
                    if record.oneDay == true {
                        PopChip(text: "🌟 今日だけ", color: Pop.pink)
                    }
                    Spacer()
                    Text(record.startedAt, format: .dateTime.hour().minute())
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pop.ink.opacity(0.5))
                }
                if !detail.isEmpty {
                    PhraseText(detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pop.ink.opacity(0.6))
                }
            }
        }
        .popCard()
    }
}
