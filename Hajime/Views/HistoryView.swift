import SwiftUI

/// 始めた回数と、通知から始めるまでの時間の振り返り (F8)。やらなかった日は数えない。
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let stats = StartStats(records: model.records, now: .now)
        NavigationStack {
            List {
                Section {
                    LabeledContent("始めた回数", value: "\(stats.count)回")
                    LabeledContent("通知から始めるまで",
                                   value: stats.medianDelay.map(StartStats.format) ?? "—")
                } header: {
                    Text("この7日間")
                } footer: {
                    Text("通知から始めるまでの時間は、通知から始めた分の中央値です。")
                }
                Section("始めた記録") {
                    if model.records.isEmpty {
                        Text("まだありません")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.records.suffix(100).reversed())) { record in
                        RecordRow(record: record)
                    }
                }
            }
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
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(record.taskTitle)
                Spacer()
                Text(record.startedAt, format: .dateTime.month().day().hour().minute())
                    .foregroundStyle(.secondary)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
