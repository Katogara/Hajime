import Foundation

/// 着手を促す「やること」。登録は初回だけで、通常の運用ではここに入力しない。
struct StartTask: Codable, Identifiable, Equatable {
    /// 最初の通知で始めるときの長さ
    static let firstMinutes = 5
    /// 再通知 (さらに小さい一歩) で始めるときの長さ
    static let nudgeMinutes = 1

    var id = UUID()
    /// やること (例: 筋トレ)
    var title: String
    /// 失敗しようのない最初の一歩 (例: ウェアに着替える)
    var firstStep: String
    /// 始めないまま再通知するときの、さらに小さい一歩 (空なら最初の一歩を短い時間で促す)
    var smallerStep: String = ""
    /// 促す時刻 (0 時からの分)
    var minuteOfDay: Int
    /// 促す曜日 (Calendar の weekday: 1 = 日曜 … 7 = 土曜)
    var weekdays: Set<Int> = Set(1...7)
    /// その日だけの促す時刻。その日のいつもの時刻の代わりに使い、ほかの日には影響しない
    var oneDayTime: Date?
    /// 今日だけのやることなら、その日の 0 時。翌日には一覧から消える (曜日は空にし、時刻は `oneDayTime` に入れる)
    var onlyOn: Date?

    var isOneDay: Bool { onlyOn != nil }

    /// 今日だけのやることで、その日が過ぎた
    func isExpired(now: Date, calendar: Calendar = .current) -> Bool {
        onlyOn.map { $0 < calendar.startOfDay(for: now) } ?? false
    }

    static func draft() -> StartTask {
        StartTask(title: "", firstStep: "", minuteOfDay: 9 * 60)
    }

    /// 促しの種類ごとに、見せる一歩と時間を決める。通知とアプリの画面で同じものを使う。
    func plan(for kind: Prompt.Kind) -> (step: String, minutes: Int) {
        switch kind {
        case .first:
            return (step: firstStep, minutes: Self.firstMinutes)
        case .nudge:
            let smaller = smallerStep.trimmingCharacters(in: .whitespaces)
            return (step: smaller.isEmpty ? firstStep : smaller, minutes: Self.nudgeMinutes)
        }
    }

    /// `day` と同じ日に決めた、その日だけの促す時刻
    func oneDayTime(on day: Date, calendar: Calendar = .current) -> Date? {
        oneDayTime.flatMap { calendar.isDate($0, inSameDayAs: day) ? $0 : nil }
    }

    /// 一覧に出す「毎日 7:30」などの表示
    var scheduleText: String {
        if isOneDay {
            return oneDayTime.map { "今日だけ \(Self.timeText($0))" } ?? "今日だけ"
        }
        let time = Self.timeText(minuteOfDay)
        if weekdays.count == 7 { return "毎日 \(time)" }
        let days = weekdays.sorted().map { Self.weekdaySymbols[$0 - 1] }.joined(separator: "・")
        return "\(days) \(time)"
    }

    /// 「7:05」のような表示
    static func timeText(_ minuteOfDay: Int) -> String {
        String(format: "%d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    static func timeText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return timeText((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// 「今日は何時から」の候補。少なくとも 15 分先の 30 分刻みから 4 つ、そのあとは毎時 0 分で、今日の 23 時まで
    static func oneDayChoices(now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: today) else { return [] }
        let earliest = now.addingTimeInterval(15 * 60)
        var choices: [Date] = []
        var minute = 0
        while let date = calendar.date(byAdding: .minute, value: minute, to: today), date <= end {
            let halfHourly = choices.count < 4
            if date >= earliest, halfHourly || calendar.component(.minute, from: date) == 0 {
                choices.append(date)
            }
            minute += 30
        }
        return choices
    }

    static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]
}

/// 始めた記録。始めたこと自体を成功とし、やらなかった日は記録しない。
struct StartRecord: Codable, Identifiable, Equatable {
    enum Outcome: String, Codable {
        /// 時間がたっても続けた
        case continued
        /// 時間がたったところでやめた
        case stopped
        /// 時間の途中で「やめる」を押した (経験値はそっと取り消す)
        case quit
    }

    var id = UUID()
    var taskID: UUID
    var taskTitle: String
    /// 通知で促した時刻 (通知から始めたときだけ。再通知から始めても最初の通知の時刻)
    var promptedAt: Date?
    var startedAt: Date
    var outcome: Outcome?
    var endedAt: Date?
    /// この記録で経験値 +1 をもらった (以前の記録にはないので省略可)
    var xpAwarded: Bool?
    /// 今日だけのやることを始めた記録
    var oneDay: Bool?

    /// 促されてから始めるまでの時間
    var delay: TimeInterval? {
        promptedAt.map { max(0, startedAt.timeIntervalSince($0)) }
    }
}

/// 動いているタイマー。アプリが終了されても戻れるよう保存する。
struct TimerSession: Codable, Equatable {
    var recordID: UUID
    var taskID: UUID
    var title: String
    var step: String
    var minutes: Int
    var startedAt: Date
    /// 「やりました！」を押した (時間がたつと自動で押す)
    var continued = false
    /// 時間がたったので、アプリが代わりに押しておいた
    var autoContinued: Bool?

    var endsAt: Date { startedAt.addingTimeInterval(TimeInterval(minutes * 60)) }
}

/// この 7 日間の振り返り (F8)
struct StartStats: Equatable {
    var count: Int
    /// 通知から始めるまでの時間の中央値 (通知から始めた記録がなければ nil)
    var medianDelay: TimeInterval?

    init(records: [StartRecord], now: Date, days: Int = 7) {
        let since = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let recent = records.filter { $0.startedAt > since && $0.startedAt <= now }
        count = recent.count
        let delays = recent.compactMap(\.delay).sorted()
        if delays.isEmpty {
            medianDelay = nil
        } else if delays.count.isMultiple(of: 2) {
            medianDelay = (delays[delays.count / 2 - 1] + delays[delays.count / 2]) / 2
        } else {
            medianDelay = delays[delays.count / 2]
        }
    }

    /// 「3分」「1時間5分」のような表示
    static func format(_ delay: TimeInterval) -> String {
        let minutes = Int(delay / 60)
        if minutes < 1 { return "1分未満" }
        if minutes < 60 { return "\(minutes)分" }
        return minutes % 60 == 0 ? "\(minutes / 60)時間" : "\(minutes / 60)時間\(minutes % 60)分"
    }
}
