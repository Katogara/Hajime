import Foundation

/// 通知で促す 1 回分
struct Prompt: Equatable {
    enum Kind: String {
        /// 決めた時刻の通知
        case first
        /// 始めないまま時間がたったときの、さらに小さい一歩での再通知 (1 日 1 回まで)
        case nudge
    }

    var taskID: UUID
    var kind: Kind
    var date: Date
    /// その日の最初の通知の時刻 (始めるまでの時間を測る基準)
    var promptDate: Date
}

/// 促す通知をいつ出すかを決める。
/// 日ごとに具体的な日時で予約するので、始めた日の残り (再通知) だけを取り消せる。
enum ReminderSchedule {
    /// 最初の通知から再通知までの時間
    static let nudgeDelay: TimeInterval = 15 * 60
    /// 何日先まで予約するか (アプリを開くたびに先へ延ばす)
    static let days = 7
    /// iOS が保持するローカル通知の予約は 64 件まで。タイマー終了の通知の分を残す
    static let maxPending = 60

    struct DayKey: Hashable {
        var taskID: UUID
        /// その日の 0 時
        var day: Date
    }

    /// 始めた記録から、その日の促しが要らない (やること, 日) の組を作る
    static func startedDays(_ records: [StartRecord], calendar: Calendar = .current) -> Set<DayKey> {
        Set(records.map { DayKey(taskID: $0.taskID, day: calendar.startOfDay(for: $0.startedAt)) })
    }

    static func prompts(for tasks: [StartTask], startedDays: Set<DayKey>, now: Date,
                        calendar: Calendar = .current) -> [Prompt] {
        let today = calendar.startOfDay(for: now)
        var result: [Prompt] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            for task in tasks {
                if startedDays.contains(DayKey(taskID: task.id, day: day)) { continue }
                let first: Date
                if let oneDay = task.oneDayTime(on: day, calendar: calendar) {
                    // その日だけの時刻は、いつもは促さない曜日でも使う
                    first = oneDay
                } else if task.weekdays.contains(weekday),
                          let regular = calendar.date(bySettingHour: task.minuteOfDay / 60,
                                                      minute: task.minuteOfDay % 60, second: 0, of: day) {
                    first = regular
                } else {
                    continue
                }
                let nudge = first.addingTimeInterval(nudgeDelay)
                if first > now {
                    result.append(Prompt(taskID: task.id, kind: .first, date: first, promptDate: first))
                }
                if nudge > now {
                    result.append(Prompt(taskID: task.id, kind: .nudge, date: nudge, promptDate: first))
                }
            }
        }
        result.sort { $0.date < $1.date }
        return Array(result.prefix(maxPending))
    }
}
