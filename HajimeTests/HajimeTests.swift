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

    func testCapsPendingNotifications() {
        let tasks = (0..<6).map { task(at: 8 + $0) }
        let prompts = ReminderSchedule.prompts(for: tasks, startedDays: [], now: date(19, 0), calendar: calendar)
        XCTAssertEqual(prompts.count, ReminderSchedule.maxPending)
        XCTAssertEqual(prompts.map(\.date), prompts.map(\.date).sorted())
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
