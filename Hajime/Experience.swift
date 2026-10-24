import Foundation

/// 経験値とレベルの表。仮の値で、試しながら調整する前提。
/// 始めるたびに経験値 +1 (同じやることは 1 日 1 回まで)。レベル 100 で卒業。
enum LevelTable {
    static let maxLevel = 100

    /// レベル `level` から次のレベルに上がるのに要る経験値 (level = 1...99)。
    /// 最初はすぐ上がって楽しく、だんだんゆっくりにする。1 日 2 回始めて 1 年 3 か月ほどで卒業 (合計 905)。
    static func need(toLeave level: Int) -> Int {
        switch level {
        case ..<10:
            // Lv.1〜9: 1, 1, 2, 2, 3, 3, 4, 4, 5 (最初の 1 回でもう Lv.2)
            return 1 + (level - 1) / 2
        case ..<30:
            // Lv.10〜29: 5 レベルごとに 4, 5, 6, 7
            return 4 + (level - 10) / 5
        default:
            // Lv.30〜99: 10 レベルごとに 8, 9, … 14
            return 8 + (level - 30) / 10
        }
    }

    /// 卒業までに要る経験値の合計
    static let totalToGraduate = (1..<maxLevel).map(need(toLeave:)).reduce(0, +)

    static func progress(forXP xp: Int) -> LevelProgress {
        var level = 1
        var rest = max(0, xp)
        while level < maxLevel, rest >= need(toLeave: level) {
            rest -= need(toLeave: level)
            level += 1
        }
        if level == maxLevel {
            return LevelProgress(level: level, current: 0, needed: 0)
        }
        return LevelProgress(level: level, current: rest, needed: need(toLeave: level))
    }

    /// レベルごとの呼び名
    static func title(for level: Int) -> String {
        switch level {
        case ..<5: return "はじめの一歩"
        case ..<10: return "動き出した人"
        case ..<20: return "腰が軽い人"
        case ..<30: return "始めるのが得意"
        case ..<50: return "始める達人"
        case ..<70: return "迷わない人"
        case ..<90: return "ほぼ無敵"
        case ..<maxLevel: return "卒業まであと少し"
        default: return "卒業"
        }
    }
}

/// 今のレベルと、次のレベルまでの経験値 (分子 / 分母)
struct LevelProgress: Equatable {
    var level: Int
    /// 今のレベルになってから貯めた経験値
    var current: Int
    /// 次のレベルに上がるのに要る経験値 (卒業後は 0)
    var needed: Int

    var graduated: Bool { level >= LevelTable.maxLevel }
    var title: String { LevelTable.title(for: level) }
    var fraction: Double { needed == 0 ? 1 : Double(current) / Double(needed) }
}

/// レベルが上がった記録 (「これまでのつみあげ」に出す)
struct LevelUpEvent: Codable, Equatable {
    var level: Int
    var date: Date
}

/// 「これまでのつみあげ」の 1 日分
struct DayLog: Identifiable, Equatable {
    /// その日の 0 時
    var day: Date
    /// その日に始めた記録 (古い順)
    var records: [StartRecord]
    /// その日に上がったレベル (古い順)
    var levelUps: [LevelUpEvent]

    var id: Date { day }

    /// 記録とレベルアップを日ごとにまとめる (新しい日が先)
    static func build(records: [StartRecord], levelUps: [LevelUpEvent], calendar: Calendar = .current) -> [DayLog] {
        var days: [Date: DayLog] = [:]
        for record in records.sorted(by: { $0.startedAt < $1.startedAt }) {
            let day = calendar.startOfDay(for: record.startedAt)
            days[day, default: DayLog(day: day, records: [], levelUps: [])].records.append(record)
        }
        for event in levelUps.sorted(by: { $0.date < $1.date }) {
            let day = calendar.startOfDay(for: event.date)
            days[day, default: DayLog(day: day, records: [], levelUps: [])].levelUps.append(event)
        }
        return days.values.sorted { $0.day > $1.day }
    }
}

enum Experience {
    /// このやることで、今日まだ経験値をもらっていなければ true (同じやることは 1 日 1 回まで)
    static func canEarn(records: [StartRecord], taskID: UUID, now: Date, calendar: Calendar = .current) -> Bool {
        !records.contains {
            $0.taskID == taskID && $0.xpAwarded == true && calendar.isDate($0.startedAt, inSameDayAs: now)
        }
    }
}
