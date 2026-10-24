import Foundation
import Observation

/// 通知本体をタップしたときに見せる「最初の一歩」の画面の中身
struct ReadyPrompt: Identifiable {
    let id = UUID()
    var taskID: UUID
    var kind: Prompt.Kind
    var promptDate: Date?
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
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tasks = load([StartTask].self, StoreKey.tasks) ?? []
        records = load([StartRecord].self, StoreKey.records) ?? []
        session = load(TimerSession.self, StoreKey.session)
        notifier.onStart = { [weak self] response in self?.handle(response) }
        notifier.onTimerChoice = { [weak self] outcome in
            switch outcome {
            case .continued: self?.continueSession()
            case .stopped: self?.finish()
            }
        }
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
        let record = StartRecord(taskID: task.id, taskTitle: task.title, promptedAt: promptDate, startedAt: now)
        records.append(record)
        if records.count > Self.maxRecords {
            records.removeFirst(records.count - Self.maxRecords)
        }
        let session = TimerSession(recordID: record.id, taskID: task.id, title: task.title, step: plan.step,
                                   minutes: plan.minutes, startedAt: now)
        self.session = session
        ready = nil
        store(records, StoreKey.records)
        store(session, StoreKey.session)
        notifier.scheduleTimerEnd(at: session.endsAt, minutes: session.minutes)
        Task { await notifier.clearDeliveredPrompts(taskID: task.id) }
        // その日の再通知を取り消す
        refreshSchedule()
    }

    /// 時間がたったあとも続ける。終わったら `finish()` を呼ぶ。
    func continueSession() {
        guard var session else { return }
        session.continued = true
        self.session = session
        store(session, StoreKey.session)
        updateRecord(session.recordID) { $0.outcome = .continued }
        notifier.cancelTimerEnd()
    }

    /// タイマーを閉じる。続けていなければ「やめた」として記録する。
    func finish() {
        guard let session else { return }
        let now = Date()
        updateRecord(session.recordID) {
            if $0.outcome == nil { $0.outcome = .stopped }
            $0.endedAt = now
        }
        self.session = nil
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
