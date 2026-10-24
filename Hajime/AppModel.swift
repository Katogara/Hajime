import Foundation
import Observation

/// 通知本体をタップしたときに見せる「最初の一歩」の画面の中身
struct ReadyPrompt: Identifiable {
    let id = UUID()
    var taskID: UUID
    var kind: Prompt.Kind
    var promptDate: Date?
}

/// 大げさに褒める演出。始めたときと「やりました！」のときだけ出す (「やっぱりやめます」では出さない)
struct Cheer: Identifiable, Equatable {
    enum Kind {
        case started
        case continued
        /// レベル 100 に達した (卒業)
        case graduated
    }

    let id = UUID()
    var kind: Kind
    /// 経験値 +1 をもらった
    var gainedXP = false
    /// レベルが上がったときの新しいレベル
    var levelUp: Int?
}

/// やること・記録・タイマーを持ち、通知の予約をそれに合わせる。
@Observable
@MainActor
final class AppModel {
    private(set) var tasks: [StartTask] = []
    private(set) var records: [StartRecord] = []
    /// 動いているタイマー (あれば画面全体をタイマーにする)
    private(set) var session: TimerSession?
    /// 通知本体のタップで開いたときの一歩の画面
    var ready: ReadyPrompt?
    /// 表示中の褒める演出 (画面が閉じたら nil に戻す)
    var cheer: Cheer?
    /// これまでに貯めた経験値の合計
    private(set) var xp = 0
    /// 卒業の演出を見せた (2 回は見せない)
    private(set) var graduated = false
    /// レベルが上がった記録
    private(set) var levelUps: [LevelUpEvent] = []

    var level: LevelProgress { LevelTable.progress(forXP: xp) }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifier = Notifier()
    /// 予約し直しを順番に行う (前の予約の途中で次が混ざらないように)
    @ObservationIgnored private var scheduling: Task<Void, Never>?

    /// 記録は新しい順にこの件数まで残す
    private static let maxRecords = 1000

    private enum StoreKey {
        static let tasks = "tasks"
        static let records = "records"
        static let session = "session"
        static let xp = "xp"
        static let graduated = "graduated"
        static let levelUps = "levelUps"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tasks = load([StartTask].self, StoreKey.tasks) ?? []
        records = load([StartRecord].self, StoreKey.records) ?? []
        session = load(TimerSession.self, StoreKey.session)
        xp = defaults.integer(forKey: StoreKey.xp)
        graduated = defaults.bool(forKey: StoreKey.graduated)
        levelUps = load([LevelUpEvent].self, StoreKey.levelUps) ?? []
        removeExpiredTasks()
        notifier.onStart = { [weak self] response in self?.handle(response) }
        // 以前の版で「続きをやっています」のまま残っていたら閉じる
        if session?.continued == true { finish() }
    }

    func task(id: UUID) -> StartTask? {
        tasks.first { $0.id == id }
    }

    // MARK: - やること

    func save(_ task: StartTask) {
        var task = task
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.firstStep = task.firstStep.trimmingCharacters(in: .whitespacesAndNewlines)
        task.smallerStep = task.smallerStep.trimmingCharacters(in: .whitespacesAndNewlines)
        if task.isOneDay {
            // 今日だけのやることは、曜日を使わず、今日の決めた時刻だけ促す
            let now = Date()
            task.onlyOn = Calendar.current.startOfDay(for: now)
            task.weekdays = []
            task.oneDayTime = Calendar.current.date(bySettingHour: task.minuteOfDay / 60,
                                                    minute: task.minuteOfDay % 60, second: 0, of: now)
        }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        store(tasks, StoreKey.tasks)
        Task {
            await notifier.requestAuthorization()
            refreshSchedule()
        }
    }

    /// 今日だけ促す時刻を変える (nil でいつもの時刻に戻す)
    func setOneDayTime(_ date: Date?, for taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].oneDayTime = date
        if tasks[index].isOneDay, let date {
            // 今日だけのやることは、編集画面の時刻もそろえる
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            tasks[index].minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        store(tasks, StoreKey.tasks)
        refreshSchedule()
    }

    /// 日が変わった「今日だけ」のやることを消す (始めた記録は残る)
    private func removeExpiredTasks() {
        let now = Date()
        guard tasks.contains(where: { $0.isExpired(now: now) }) else { return }
        tasks.removeAll { $0.isExpired(now: now) }
        store(tasks, StoreKey.tasks)
    }

    /// このやることを今日もう始めた
    func startedToday(_ task: StartTask, now: Date = .now) -> Bool {
        records.contains { $0.taskID == task.id && Calendar.current.isDate($0.startedAt, inSameDayAs: now) }
    }

    func delete(_ task: StartTask) {
        tasks.removeAll { $0.id == task.id }
        store(tasks, StoreKey.tasks)
        refreshSchedule()
    }

    func delete(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets)
        store(tasks, StoreKey.tasks)
        refreshSchedule()
    }

    // MARK: - 始める

    private func handle(_ response: PromptResponse) {
        guard task(id: response.taskID) != nil else { return }
        if response.startNow {
            start(taskID: response.taskID, kind: response.kind, promptDate: response.promptDate)
        } else if session == nil {
            ready = ReadyPrompt(taskID: response.taskID, kind: response.kind, promptDate: response.promptDate)
        }
    }

    /// タイマーを始めた時点で「始めた」と記録する。途中でやめても記録は残す。
    /// - Parameter promptDate: 通知から始めたときの、その日の最初の通知の時刻
    func start(taskID: UUID, kind: Prompt.Kind = .first, promptDate: Date? = nil) {
        guard session == nil, let task = task(id: taskID) else { return }
        let plan = task.plan(for: kind)
        let now = Date()
        // 経験値は同じやることで 1 日 1 回まで
        let earns = Experience.canEarn(records: records, taskID: task.id, now: now)
        var record = StartRecord(taskID: task.id, taskTitle: task.title, promptedAt: promptDate, startedAt: now)
        record.xpAwarded = earns ? true : nil
        record.oneDay = task.isOneDay ? true : nil
        records.append(record)
        if records.count > Self.maxRecords {
            records.removeFirst(records.count - Self.maxRecords)
        }
        let session = TimerSession(recordID: record.id, taskID: task.id, title: task.title, step: plan.step,
                                   minutes: plan.minutes, startedAt: now)
        self.session = session
        ready = nil
        cheer = earns ? gainXP() : Cheer(kind: .started)
        store(records, StoreKey.records)
        store(session, StoreKey.session)
        notifier.scheduleTimerEnd(at: session.endsAt, minutes: session.minutes)
        Task { await notifier.clearDeliveredPrompts(taskID: task.id) }
        // その日の再通知を取り消す
        refreshSchedule()
    }

    /// 経験値 +1。レベルが上がれば演出に載せ、レベル 100 に初めて達したら卒業の演出にする
    private func gainXP() -> Cheer {
        let before = level.level
        xp += 1
        defaults.set(xp, forKey: StoreKey.xp)
        let after = level.level
        if after > before {
            levelUps.append(LevelUpEvent(level: after, date: .now))
            store(levelUps, StoreKey.levelUps)
        }
        if after >= LevelTable.maxLevel && !graduated {
            graduated = true
            defaults.set(true, forKey: StoreKey.graduated)
            return Cheer(kind: .graduated, gainedXP: true, levelUp: after)
        }
        return Cheer(kind: .started, gainedXP: true, levelUp: after > before ? after : nil)
    }

    /// 「やっぱりやめます」。始めた記録は残すが、増えた経験値はそっと取り消す (何も表示しない)
    func quit() {
        guard let session else { return }
        if let record = records.first(where: { $0.id == session.recordID }), record.xpAwarded == true {
            xp = max(0, xp - 1)
            defaults.set(xp, forKey: StoreKey.xp)
            // その +1 で上がったレベルも、つみあげからそっと消す
            let current = level.level
            if levelUps.contains(where: { $0.level > current }) {
                levelUps.removeAll { $0.level > current }
                store(levelUps, StoreKey.levelUps)
            }
        }
        updateRecord(session.recordID) {
            $0.outcome = .quit
            $0.xpAwarded = nil
        }
        finish()
    }

    /// 「やりました！」。一歩をやった時点でアプリの役目は終わりなので、褒めて一覧に戻る (続きの時間は数えない)
    /// - Parameter auto: 時間がたったので、代わりに押しておいた (本人は見ていないかもしれないので褒める演出は出さない)
    func continueSession(auto: Bool = false) {
        guard let session else { return }
        updateRecord(session.recordID) { $0.outcome = .continued }
        finish()
        if !auto { cheer = Cheer(kind: .continued) }
    }

    /// 時間がたっていれば「やりました！」を押しておく (アプリを閉じていたあいだの分も、開いたときに)
    func autoContinueIfDue(now: Date = .now) {
        guard let session, now >= session.endsAt else { return }
        continueSession(auto: true)
    }

    /// 「はじめる」のあとの画面を閉じて一覧に戻る。褒めも責めもしない
    private func finish() {
        guard let session else { return }
        let now = Date()
        updateRecord(session.recordID) {
            if $0.outcome == nil { $0.outcome = .stopped }
            $0.endedAt = now
        }
        self.session = nil
        // 閉じるときは褒めも責めもしない
        cheer = nil
        store(TimerSession?.none, StoreKey.session)
        notifier.cancelTimerEnd()
    }

    private func updateRecord(_ id: UUID, _ change: (inout StartRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
        store(records, StoreKey.records)
    }

    // MARK: - 通知の予約

    /// 促す通知を予約し直す (7 日分なので、アプリを開くたびに先へ延ばす)
    func refreshSchedule() {
        removeExpiredTasks()
        autoContinueIfDue()
        let prompts = ReminderSchedule.prompts(for: tasks, startedDays: ReminderSchedule.startedDays(records), now: .now)
        let tasks = tasks
        let previous = scheduling
        scheduling = Task {
            await previous?.value
            await notifier.schedulePrompts(prompts, tasks: tasks)
        }
    }

    // MARK: - 保存

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func store<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
