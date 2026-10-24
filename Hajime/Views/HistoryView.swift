import SwiftUI

/// 始めた回数と、通知から始めるまでの時間の振り返り (F8)。やらなかった日は数えない。
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let stats = StartStats(records: model.records, now: .now)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("この7日間")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(Pop.ink)
                    HStack(spacing: 12) {
                        StatCard(emoji: "🔥", value: "\(stats.count)回", label: "始めた回数", color: Pop.orange)
                        StatCard(emoji: "⚡️", value: stats.medianDelay.map(StartStats.format) ?? "—",
                                 label: "通知から始めるまで", color: Pop.yellow)
                    }
                    Text("通知から始めるまでの時間は、通知から始めた分の中央値です。")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pop.ink.opacity(0.55))
                    Text("始めた記録")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(Pop.ink)
                        .padding(.top, 8)
                    if model.records.isEmpty {
                        Text("まだありません。最初の1回、楽しみにしています 🌱")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Pop.ink.opacity(0.6))
                            .popCard()
                    }
                    ForEach(Array(model.records.suffix(100).reversed())) { record in
                        RecordRow(record: record)
                    }
                }
                .padding(20)
            }
            .popBackground()
            .navigationTitle("記録")
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
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Pop.ink.opacity(0.6))
        }
        .popCard(tint: color)
    }
}

private struct RecordRow: View {
    let record: StartRecord

    private var detail: String {
        var parts: [String] = []
        if let delay = record.delay {
            parts.append("通知から\(StartStats.format(delay))")
        }
        switch record.outcome {
        case .continued?: parts.append("続けた")
        case .stopped?: parts.append("ここまで")
        case nil: break
        }
        if let ended = record.endedAt {
            parts.append("\(StartStats.format(ended.timeIntervalSince(record.startedAt)))取り組んだ")
        }
        return parts.joined(separator: "・")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(record.outcome == .continued ? "🔥" : "✅")
                .font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(record.taskTitle)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(Pop.ink)
                    Spacer()
                    Text(record.startedAt, format: .dateTime.month().day().hour().minute())
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pop.ink.opacity(0.5))
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Pop.ink.opacity(0.6))
                }
            }
        }
        .popCard()
    }
}
