import UIKit
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

    func testSecretTaskHidesTitle() {
        let secret = UUID()
        let shown = StartRecord(taskID: UUID(), taskTitle: "筋トレ", startedAt: .now)
        let hidden = StartRecord(taskID: secret, taskTitle: "転職活動", startedAt: .now)
        XCTAssertEqual(shown.displayTitle(secretTaskIDs: [secret]), "筋トレ")
        XCTAssertEqual(hidden.displayTitle(secretTaskIDs: [secret]), "秘密❤️")
        // 解除すれば名前が戻る
        XCTAssertEqual(hidden.displayTitle(secretTaskIDs: []), "転職活動")
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

    func testMinuteOfDayUsesOneDayTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8))!
        var task = StartTask(title: "筋トレ", firstStep: "着替える", minuteOfDay: 7 * 60)
        XCTAssertEqual(task.promptMinute(on: today, calendar: calendar), 7 * 60)
        task.oneDayTime = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: today)
        XCTAssertEqual(task.promptMinute(on: today, calendar: calendar), 20 * 60 + 30)
        // 翌日はいつもの時刻
        XCTAssertEqual(task.promptMinute(on: today.addingTimeInterval(86_400), calendar: calendar), 7 * 60)
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

final class WanTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func day(_ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    /// 毎回同じ並びになる乱数 (テスト用)
    private struct FixedRandom: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    func testSouvenirWaitsAfterFirstUse() {
        // 使い始めて 7 日たつまでは渡さない
        XCTAssertFalse(Souvenir.shouldGive(now: day(7), firstUse: day(1), last: nil, startedEarlierToday: false,
                                           roll: 0, calendar: calendar))
        XCTAssertTrue(Souvenir.shouldGive(now: day(8), firstUse: day(1), last: nil, startedEarlierToday: false,
                                          roll: 0, calendar: calendar))
    }

    func testSouvenirInterval() {
        XCTAssertFalse(Souvenir.shouldGive(now: day(20), firstUse: day(1), last: day(1),
                                           startedEarlierToday: false, roll: 0, calendar: calendar))
        XCTAssertTrue(Souvenir.shouldGive(now: day(21), firstUse: day(1), last: day(1),
                                          startedEarlierToday: false, roll: 0, calendar: calendar))
        // 時計を戻されても渡さない
        XCTAssertFalse(Souvenir.shouldGive(now: day(1), firstUse: day(1), last: day(21),
                                           startedEarlierToday: false, roll: 0, calendar: calendar))
    }

    func testSouvenirOnlyFirstStartOfDayAndByChance() {
        XCTAssertFalse(Souvenir.shouldGive(now: day(21), firstUse: day(1), last: nil, startedEarlierToday: true,
                                           roll: 0, calendar: calendar))
        XCTAssertFalse(Souvenir.shouldGive(now: day(21), firstUse: day(1), last: nil, startedEarlierToday: false,
                                           roll: 0.5, calendar: calendar))
        XCTAssertFalse(Souvenir.shouldGive(now: day(21), firstUse: nil, last: nil, startedEarlierToday: false,
                                           roll: 0, calendar: calendar))
    }

    func testSouvenirPrefersNewKinds() {
        var random = FixedRandom(state: 1)
        let owned = Souvenir.items.dropLast().map { Souvenir(kind: $0.kind, date: day(1)) }
        XCTAssertEqual(Souvenir.pickKind(owned: owned, using: &random), Souvenir.items.last!.kind)
        // 全部持っていれば、どれでもよい
        let all = Souvenir.items.map { Souvenir(kind: $0.kind, date: day(1)) }
        XCTAssertNotNil(Souvenir.items.first { $0.kind == Souvenir.pickKind(owned: all, using: &random) })
    }

    func testWelcomeBackAfterThreeDays() {
        XCTAssertFalse(WelcomeBack.isReturning(lastActive: nil, now: day(10), calendar: calendar))
        XCTAssertFalse(WelcomeBack.isReturning(lastActive: day(8, 23), now: day(10, 1), calendar: calendar))
        XCTAssertTrue(WelcomeBack.isReturning(lastActive: day(7, 23), now: day(10, 1), calendar: calendar))
    }

    func testLinesFillStepAndTitle() {
        let line = WanLines.Line("{title}、始まった！", "{step}から")
        XCTAssertEqual(line.filled(step: "ウェアに着替える", title: "筋トレ"),
                       WanLines.Line("筋トレ、始まった！", "ウェアに着替えるから"))
    }

    func testLinesWithoutTaskSkipPlaceholders() {
        var random = FixedRandom(state: 7)
        for _ in 0..<50 {
            let line = WanLines.pick(from: WanLines.started, step: nil, title: nil, using: &random)
            XCTAssertFalse((line.title + line.sub).contains("{"))
        }
        for _ in 0..<50 {
            let line = WanLines.pick(from: WanLines.continued, step: "着替える", title: "筋トレ", using: &random)
            XCTAssertFalse((line.title + line.sub).contains("{"))
        }
    }

    func testFacingFlipsOnlyOppositeSides() {
        XCTAssertTrue(Facing.left.needsFlip(toFace: .right))
        XCTAssertTrue(Facing.right.needsFlip(toFace: .left))
        XCTAssertFalse(Facing.left.needsFlip(toFace: .left))
        XCTAssertFalse(Facing.front.needsFlip(toFace: .left))
        XCTAssertFalse(Facing.right.needsFlip(toFace: .front))
        // 褒める画面ではワンのすけはアバター (左) のほうを向く
        XCTAssertFalse(WanPose.banzai.facing.needsFlip(toFace: .left))
    }

    func testCheerStyleDefault() {
        XCTAssertEqual(CheerStyle.resolve("", reduceMotion: false), .big)
        XCTAssertEqual(CheerStyle.resolve("", reduceMotion: true), .small)
        XCTAssertEqual(CheerStyle.resolve("normal", reduceMotion: true), .normal)
        XCTAssertEqual(CheerStyle.resolve("loud", reduceMotion: false), .big)
    }
}

final class AvatarTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "AvatarTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testNotChosenYet() {
        let store = AvatarStore(defaults: defaults)
        XCTAssertNil(store.body)
        XCTAssertFalse(store.asked)
    }

    func testChooseAndChooseAgain() {
        AvatarStore(defaults: defaults).choose(.female)
        XCTAssertEqual(AvatarStore(defaults: defaults).body, .female)
        XCTAssertTrue(AvatarStore(defaults: defaults).asked)
        // 選び直しは上書きする
        AvatarStore(defaults: defaults).choose(.male)
        XCTAssertEqual(AvatarStore(defaults: defaults).body, .male)
    }

    func testSkipKeepsNoAvatar() {
        let store = AvatarStore(defaults: defaults)
        store.markAsked()
        XCTAssertTrue(store.asked)
        XCTAssertNil(store.body)
    }

    func testUnknownValueIsNotChosen() {
        defaults.set("robot", forKey: "avatarBody")
        XCTAssertNil(AvatarStore(defaults: defaults).body)
    }

    func testAllImagesExist() {
        let bundle = Bundle(for: AppModel.self)
        for pose in WanPose.allCases {
            XCTAssertNotNil(UIImage(named: pose.imageName, in: bundle, compatibleWith: nil), pose.imageName)
        }
        for figure in AvatarBody.allCases {
            for pose in AvatarPose.allCases {
                let name = figure.imageName(pose)
                XCTAssertNotNil(UIImage(named: name, in: bundle, compatibleWith: nil), name)
            }
        }
    }
}
