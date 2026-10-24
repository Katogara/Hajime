import XCTest
@testable import Hajime

final class ReminderScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        // 2026-10-19 は月曜日
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func task(at hour: Int, _ minute: Int = 0, weekdays: Set<Int> = Set(1...7)) -> StartTask {
        StartTask(title: "筋トレ", firstStep: "ウェアに着替える", minuteOfDay: hour * 60 + minute, weekdays: weekdays)
    }

    func testDailyTaskGetsFirstAndNudgeForSevenDays() {
        let task = task(at: 18)
        let prompts = ReminderSchedule.prompts(for: [task], startedDays: [], now: date(19, 9), calendar: calendar)
        XCTAssertEqual(prompts.count, 14)
        XCTAssertEqual(prompts[0], Prompt(taskID: task.id, kind: .first, date: date(19, 18), promptDate: date(19, 18)))
        XCTAssertEqual(prompts[1], Prompt(taskID: task.id, kind: .nudge, date: date(19, 18, 15), promptDate: date(19, 18)))
        XCTAssertEqual(prompts.last?.date, date(25, 18, 15))
    }

    func testPastFirstPromptKeepsPendingNudge() {
        let task = task(at: 18)
        let prompts = ReminderSchedule.prompts(for: [task], startedDays: [], now: date(19, 18, 5), calendar: calendar)
        XCTAssertEqual(prompts.first, Prompt(taskID: task.id, kind: .nudge, date: date(19, 18, 15), promptDate: date(19, 18)))
        XCTAssertEqual(prompts.count, 13)
    }

    func testStartedDaySkipsRemainingPrompts() {
        let task = task(at: 18)
        let record = StartRecord(taskID: task.id, taskTitle: task.title, promptedAt: date(19, 18), startedAt: date(19, 18, 3))
        let started = ReminderSchedule.startedDays([record], calendar: calendar)
        let prompts = ReminderSchedule.prompts(for: [task], startedDays: started, now: date(19, 18, 5), calendar: calendar)
        XCTAssertEqual(prompts.first?.date, date(20, 18))
        XCTAssertEqual(prompts.count, 12)
    }

    func testOnlySelectedWeekdays() {
        // 月 (2) と金 (6) だけ
        let task = task(at: 7, 30, weekdays: [2, 6])
        let prompts = ReminderSchedule.prompts(for: [task], startedDays: [], now: date(19, 0), calendar: calendar)
        XCTAssertEqual(prompts.filter { $0.kind == .first }.map(\.date), [date(19, 7, 30), date(23, 7, 30)])
    }

    func testOneDayTimeReplacesOnlyThatDay() {
        var task = task(at: 7)
        task.oneDayTime = date(19, 20, 30)
        let prompts = ReminderSchedule.prompts(for: [task], startedDays: [], now: date(19, 6), calendar: calendar)
        XCTAssertEqual(prompts[0], Prompt(taskID: task.id, kind: .first, date: date(19, 20, 30), promptDate: date(19, 20, 30)))
        XCTAssertEqual(prompts[1], Prompt(taskID: task.id, kind: .nudge, date: date(19, 20, 45), promptDate: date(19, 20, 30)))
        // 翌日からはいつもの時刻
        XCTAssertEqual(prompts[2].date, date(20, 7))
        XCTAssertEqual(prompts.count, 14)
    }

    func testOneDayTimeWorksOnUnscheduledWeekday() {
        // 金曜 (6) だけのやることを、月曜の今日だけ促す
        var task = task(at: 7, weekdays: [6])
        task.oneDayTime = date(19, 21)
        let prompts = ReminderSchedule.prompts(for: [task], startedDays: [], now: date(19, 9), calendar: calendar)
        XCTAssertEqual(prompts.filter { $0.kind == .first }.map(\.date), [date(19, 21), date(23, 7)])
    }

    func testPastDayOneDayTimeIsIgnored() {
        var task = task(at: 7)
        task.oneDayTime = date(18, 21)
        let prompts = ReminderSchedule.prompts(for: [task], startedDays: [], now: date(19, 6), calendar: calendar)
        XCTAssertEqual(prompts.first?.date, date(19, 7))
        XCTAssertEqual(task.oneDayTime(on: date(19, 6), calendar: calendar), nil)
    }

    func testOneDayChoices() {
        let choices = StartTask.oneDayChoices(now: date(19, 14, 50), calendar: calendar)
        // 15 分以上先の 30 分刻みから 4 つ、そのあとは毎時 0 分で 23 時まで
        XCTAssertEqual(choices, [date(19, 15, 30), date(19, 16), date(19, 16, 30), date(19, 17),
                                 date(19, 18), date(19, 19), date(19, 20), date(19, 21), date(19, 22), date(19, 23)])
        XCTAssertEqual(StartTask.oneDayChoices(now: date(19, 22, 50), calendar: calendar), [])
    }

    func testCapsPendingNotifications() {
        let tasks = (0..<6).map { task(at: 8 + $0) }
        let prompts = ReminderSchedule.prompts(for: tasks, startedDays: [], now: date(19, 0), calendar: calendar)
        XCTAssertEqual(prompts.count, ReminderSchedule.maxPending)
        XCTAssertEqual(prompts.map(\.date), prompts.map(\.date).sorted())
    }
}

final class ExperienceTests: XCTestCase {
    func testLevelTable() {
        XCTAssertEqual(LevelTable.progress(forXP: 0), LevelProgress(level: 1, current: 0, needed: 1))
        // 最初の 1 回でもう Lv.2
        XCTAssertEqual(LevelTable.progress(forXP: 1), LevelProgress(level: 2, current: 0, needed: 1))
        XCTAssertEqual(LevelTable.progress(forXP: 3), LevelProgress(level: 3, current: 1, needed: 2))
        // Lv.10 までに 25
        XCTAssertEqual(LevelTable.progress(forXP: 25), LevelProgress(level: 10, current: 0, needed: 4))
        XCTAssertEqual(LevelTable.totalToGraduate, 905)
        XCTAssertEqual(LevelTable.progress(forXP: 904).level, 99)
        XCTAssertTrue(LevelTable.progress(forXP: 905).graduated)
        XCTAssertTrue(LevelTable.progress(forXP: 5000).graduated)
    }

    func testOncePerTaskPerDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8))!
        let evening = morning.addingTimeInterval(10 * 3600)
        let nextDay = morning.addingTimeInterval(24 * 3600)
        let task = UUID()
        var earned = StartRecord(taskID: task, taskTitle: "筋トレ", startedAt: morning)
        earned.xpAwarded = true
        XCTAssertFalse(Experience.canEarn(records: [earned], taskID: task, now: evening, calendar: calendar))
        XCTAssertTrue(Experience.canEarn(records: [earned], taskID: UUID(), now: evening, calendar: calendar))
        XCTAssertTrue(Experience.canEarn(records: [earned], taskID: task, now: nextDay, calendar: calendar))
        // やめて取り消した分は、その日にもう一度もらえる
        var quit = earned
        quit.xpAwarded = nil
        XCTAssertTrue(Experience.canEarn(records: [quit], taskID: task, now: evening, calendar: calendar))
    }
}

final class PhrasesTests: XCTestCase {
    func testKeepsQuotesAndAppWordsTogether() {
        XCTAssertEqual(Phrases.split("📣 このアプリはあなたの「はじめる」を応援します！"),
                       ["📣 この", "アプリは", "あなたの", "「はじめる」を", "応援します！"])
        XCTAssertEqual(Phrases.split("はじめた！天才！"), ["はじめた！", "天才！"])
        XCTAssertEqual(Phrases.split("おきますね（のこり 4:32）").last, "（のこり 4:32）")
    }

    func testLineStartAndEndRules() {
        let samples = [
            "一歩をやったら「やりました！」。やらなかったら「やっぱりやめます」",
            "やることと、すぐ終わる「最初の一歩」を登録する（例：筋トレなら「ウェアに着替える」）",
            "手伝うのは「始めること」だけ。やることの管理はしませんし、終わらせなくていいアプリです。",
        ]
        for text in samples {
            let chunks = Phrases.split(text)
            XCTAssertEqual(chunks.joined(), text)
            for chunk in chunks {
                XCTAssertFalse(chunk.hasSuffix("「"), chunk)
                XCTAssertFalse(["」", "、", "。", "！", "）"].contains { chunk.hasPrefix($0) }, chunk)
            }
        }
    }

    func testPunctuationLines() {
        XCTAssertEqual(Phrases.punctuationLines("考える前に、もう始めている")?.components(separatedBy: "\n").count, 2)
        XCTAssertNil(Phrases.punctuationLines("使い方"))
        XCTAssertNil(Phrases.punctuationLines("応援します！"))
    }
}

final class DayLogTests: XCTestCase {
    func testGroupsByDayNewestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func at(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }
        let task = UUID()
        func earned(_ title: String, _ date: Date, xp: Bool = true) -> StartRecord {
            var record = StartRecord(taskID: task, taskTitle: title, startedAt: date)
            record.xpAwarded = xp ? true : nil
            return record
        }
        let records = [
            earned("筋トレ", at(19, 20)),
            earned("掃除", at(19, 8)),
            // 同じ日に 2 回目に始めた分 (経験値なし) は出さない
            earned("掃除", at(19, 21), xp: false),
            earned("筋トレ", at(21, 7)),
        ]
        let levelUps = [LevelUpEvent(level: 2, date: at(19, 8)), LevelUpEvent(level: 3, date: at(22, 9))]
        let days = DayLog.build(records: records, levelUps: levelUps, calendar: calendar)
        XCTAssertEqual(days.map(\.day), [calendar.startOfDay(for: at(22, 0)), calendar.startOfDay(for: at(21, 0)),
                                         calendar.startOfDay(for: at(19, 0))])
        XCTAssertEqual(days[0].records, [])
        XCTAssertEqual(days[0].levelUps.map(\.level), [3])
        // 同じ日の中は古い順
        XCTAssertEqual(days[2].records.map(\.taskTitle), ["掃除", "筋トレ"])
    }

    func testOneDayTaskExpiresNextDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        var task = StartTask(title: "歯医者の予約", firstStep: "電話を手に取る", minuteOfDay: 600, weekdays: [])
        task.onlyOn = today
        XCTAssertFalse(task.isExpired(now: today.addingTimeInterval(23 * 3600), calendar: calendar))
        XCTAssertTrue(task.isExpired(now: today.addingTimeInterval(24 * 3600), calendar: calendar))
        XCTAssertFalse(StartTask.draft().isExpired(now: today, calendar: calendar))
    }
}

final class StartTaskTests: XCTestCase {
    func testPlanUsesSmallerStepForNudge() {
        var task = StartTask(title: "仕事", firstStep: "資料を開く", minuteOfDay: 540)
        XCTAssertEqual(task.plan(for: .first).step, "資料を開く")
        XCTAssertEqual(task.plan(for: .first).minutes, StartTask.firstMinutes)
        XCTAssertEqual(task.plan(for: .nudge).step, "資料を開く")
        XCTAssertEqual(task.plan(for: .nudge).minutes, StartTask.nudgeMinutes)
        task.smallerStep = "PCを開く"
        XCTAssertEqual(task.plan(for: .nudge).step, "PCを開く")
    }

    func testScheduleText() {
        var task = StartTask(title: "筋トレ", firstStep: "着替える", minuteOfDay: 7 * 60 + 5)
        XCTAssertEqual(task.scheduleText, "毎日 7:05")
        task.weekdays = [6, 2, 4]
        XCTAssertEqual(task.scheduleText, "月・水・金 7:05")
    }
}

final class StartStatsTests: XCTestCase {
    func testCountsLastSevenDaysAndMedianDelay() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let id = UUID()
        func record(daysAgo: Double, delayMinutes: Double?) -> StartRecord {
            let started = now.addingTimeInterval(-daysAgo * 86_400)
            return StartRecord(taskID: id, taskTitle: "t",
                               promptedAt: delayMinutes.map { started.addingTimeInterval(-$0 * 60) }, startedAt: started)
        }
        let records = [
            record(daysAgo: 8, delayMinutes: 100),
            record(daysAgo: 3, delayMinutes: 2),
            record(daysAgo: 2, delayMinutes: 10),
            record(daysAgo: 1, delayMinutes: nil),
            record(daysAgo: 0.5, delayMinutes: 4),
        ]
        let stats = StartStats(records: records, now: now)
        XCTAssertEqual(stats.count, 4)
        XCTAssertEqual(stats.medianDelay, 4 * 60)
    }

    func testFormat() {
        XCTAssertEqual(StartStats.format(30), "1分未満")
        XCTAssertEqual(StartStats.format(5 * 60), "5分")
        XCTAssertEqual(StartStats.format(65 * 60), "1時間5分")
        XCTAssertEqual(StartStats.format(120 * 60), "2時間")
    }

    func testClock() {
        XCTAssertEqual(TimerView.clock(300), "5:00")
        XCTAssertEqual(TimerView.clock(299.2), "5:00")
        XCTAssertEqual(TimerView.clock(59), "0:59")
        XCTAssertEqual(TimerView.clock(3723), "1:02:03")
    }
}
