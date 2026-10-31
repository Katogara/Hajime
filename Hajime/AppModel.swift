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
    /// 始めたやること (褒め言葉に一歩や名前を差し込む)
    var taskID: UUID?
}

/// 「やっぱりやめます」のあとに、ワンのすけが画面の下で「わかった、またね」と言う
struct Farewell: Identifiable, Equatable {
    let id = UUID()
    var line: String
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
    /// つみあげで名前を「秘密❤️」にしているやること (解除するまで。やることを消しても残す)
    private(set) var secretTaskIDs: Set<UUID> = []
    /// ユーザーの分身のアバター (まだ選んでいなければ nil)
    private(set) var avatar: AvatarBody?
    /// 最初の「どっちのきみで始める？」を出した
    private(set) var avatarAsked = false
    /// アバターの髪型と髪の色 (体を選ぶまでは nil)
    private(set) var look: AvatarLook?
    /// 部位ごとに着ている服
    private(set) var wardrobe = Wardrobe()
    /// 開発中の確かめ用: 買わなくても、すべての服を着られる (課金を作るまで。公開する前に外す)
    private(set) var devWearAll = false

    /// 絵に着せるもの。着られない服 (買っていない) は着ていないものとして渡す
    var dressing: Dressing {
        Dressing(look: look, wardrobe: devWearAll ? wardrobe : Wardrobe())
    }
    /// ワンのすけからもらったおみやげ (もらった順)
    private(set) var souvenirs: [Souvenir] = []
    /// 今もらったおみやげ。褒める演出が終わってから見せ、見せたら nil に戻す
    var newSouvenir: Souvenir?
    /// 「やっぱりやめます」のあとの、ワンのすけのひとこと (少しすると消す)
    var farewell: Farewell?
    /// 久しぶりに開いた日 (その日のうちだけ「おかえり」を出す。閉じたら nil)
    private(set) var welcomeDay: Date?

    var showsWelcome: Bool { welcomeDay.map(Calendar.current.isDateInToday) ?? false }

    var level: LevelProgress { LevelTable.progress(forXP: xp) }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifier = Notifier()
    private var avatarStore: AvatarStore { AvatarStore(defaults: defaults) }
    /// アプリを開いた (起動か、バックグラウンドから戻った) ときに「おかえり」を判定する
    @ObservationIgnored private var needsWelcomeCheck = true
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
        static let secretTasks = "secretTasks"
        static let souvenirs = "souvenirs"
        static let lastActive = "lastActive"
        static let welcomeDay = "welcomeDay"
        static let avatarLook = "avatarLook"
        static let wardrobe = "wardrobe"
        static let devWearAll = "devWearAll"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tasks = load([StartTask].self, StoreKey.tasks) ?? []
        records = load([StartRecord].self, StoreKey.records) ?? []
        session = load(TimerSession.self, StoreKey.session)
        xp = defaults.integer(forKey: StoreKey.xp)
        graduated = defaults.bool(forKey: StoreKey.graduated)
        levelUps = load([LevelUpEvent].self, StoreKey.levelUps) ?? []
        secretTaskIDs = load(Set<UUID>.self, StoreKey.secretTasks) ?? []
        avatar = avatarStore.body
        avatarAsked = avatarStore.asked
        // 髪型を選べるようになる前から使っている人は、選んだ体の最初の見た目から始める
        look = avatar.map { body in
            load(AvatarLook.self, StoreKey.avatarLook).map { AvatarLook(body: body, hair: $0.hair, hairColor: $0.hairColor) }
                ?? .initial(for: body)
        }
        wardrobe = (load(Wardrobe.self, StoreKey.wardrobe) ?? Wardrobe()).valid(in: .shared)
        devWearAll = defaults.bool(forKey: StoreKey.devWearAll)
        souvenirs = load([Souvenir].self, StoreKey.souvenirs) ?? []
        welcomeDay = defaults.object(forKey: StoreKey.welcomeDay) as? Date
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

    /// このやることを今日はじめた (経験値がたまった。「やっぱりやめます」は含めない)
    func doneToday(_ task: StartTask, now: Date = .now) -> Bool {
        records.contains {
            $0.taskID == task.id && $0.xpAwarded == true && Calendar.current.isDate($0.startedAt, inSameDayAs: now)
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

    // MARK: - 秘密❤️

    /// つみあげを人に見せるとき、このやることの記録をすべて「秘密❤️」と出す (解除するまでそのまま)
    func setSecret(_ secret: Bool, taskID: UUID) {
        if secret {
            secretTaskIDs.insert(taskID)
        } else {
            secretTaskIDs.remove(taskID)
        }
        store(secretTaskIDs, StoreKey.secretTasks)
    }

    // MARK: - アバター

    /// 分身の姿を選ぶ。あとから何度でも無料で選び直せる
    func chooseAvatar(_ body: AvatarBody) {
        avatarStore.choose(body)
        avatar = body
        avatarAsked = true
        // 体を選び直したら、その体の最初の髪型にする (髪の色と買った服はそのまま)
        if look?.body != body {
            var next = AvatarLook.initial(for: body)
            next.hairColor = look?.hairColor ?? next.hairColor
            setLook(next)
        }
    }

    /// 髪型と髪の色を変える (無料)
    func setLook(_ next: AvatarLook) {
        look = next
        store(next, StoreKey.avatarLook)
    }

    /// その部位にこのテーマの服を着る。nil なら脱いで初期の服 (ワンのすけは何も付けない) にする
    func wear(_ character: CostumeCharacter, _ part: CostumePart, theme: String?) {
        wardrobe[character][part] = theme
        store(wardrobe, StoreKey.wardrobe)
    }

    func setDevWearAll(_ on: Bool) {
        devWearAll = on
        defaults.set(on, forKey: StoreKey.devWearAll)
    }

    /// 最初の「どっちのきみで始める？」を選ばずに閉じた (選ぶまではワンのすけだけで褒める)
    func skipAvatarChoice() {
        avatarStore.markAsked()
        avatarAsked = true
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
        // おみやげの判定に使う (今回の記録を足す前に見る)
        let firstUse = records.map(\.startedAt).min() ?? now
        let startedEarlierToday = records.contains {
            $0.xpAwarded == true && Calendar.current.isDate($0.startedAt, inSameDayAs: now)
        }
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
        var cheer = earns ? gainXP() : Cheer(kind: .started)
        cheer.taskID = task.id
        self.cheer = cheer
        if earns {
            giveSouvenirIfLucky(now: now, firstUse: firstUse, startedEarlierToday: startedEarlierToday)
        }
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

    /// 「やっぱりやめます」。始めた記録は残すが、増えた経験値はそっと取り消す (責めも褒めもせず、ワンのすけが「またね」と言う)
    func quit() {
        guard let session else { return }
        if let record = records.first(where: { $0.id == session.recordID }), record.xpAwarded == true {
            revokeXP()
        }
        updateRecord(session.recordID) {
            $0.outcome = .quit
            $0.xpAwarded = nil
        }
        finish()
        // 責めも褒めもせず、ふだんと同じ明るさで見送る
        farewell = Farewell(line: WanLines.farewell.randomElement()!)
    }

    /// まちがえて「やりました！」を押したときの取り消し。「やっぱりやめます」を押したのと同じにする
    /// (経験値をそっと戻し、カードのキラキラが消えて元の位置に戻る)
    func undoDone(_ task: StartTask, now: Date = .now) {
        let indices = records.indices.filter {
            records[$0].taskID == task.id && records[$0].xpAwarded == true
                && Calendar.current.isDate(records[$0].startedAt, inSameDayAs: now)
        }
        guard !indices.isEmpty else { return }
        for index in indices {
            records[index].outcome = .quit
            records[index].xpAwarded = nil
            revokeXP()
        }
        store(records, StoreKey.records)
    }

    /// 経験値 -1。その +1 で上がったレベルも、つみあげからそっと消す
    private func revokeXP() {
        xp = max(0, xp - 1)
        defaults.set(xp, forKey: StoreKey.xp)
        let current = level.level
        if levelUps.contains(where: { $0.level > current }) {
            levelUps.removeAll { $0.level > current }
            store(levelUps, StoreKey.levelUps)
        }
    }

    /// 「やりました！」。一歩をやった時点でアプリの役目は終わりなので、褒めて一覧に戻る (続きの時間は数えない)
    /// - Parameter auto: 時間がたったので、代わりに押しておいた (本人は見ていないかもしれないので褒める演出は出さない)
    func continueSession(auto: Bool = false) {
        guard let session else { return }
        updateRecord(session.recordID) { $0.outcome = .continued }
        finish()
        if !auto { cheer = Cheer(kind: .continued, taskID: session.taskID) }
    }

    // MARK: - ワンのすけ

    /// その日の最初の「はじめた」で、ときどきおみやげを拾ってくる (予告しない。使った日にだけ)
    private func giveSouvenirIfLucky(now: Date, firstUse: Date, startedEarlierToday: Bool) {
        guard Souvenir.shouldGive(now: now, firstUse: firstUse, last: souvenirs.last?.date,
                                  startedEarlierToday: startedEarlierToday, roll: Double.random(in: 0..<1))
        else { return }
        var random = SystemRandomNumberGenerator()
        let souvenir = Souvenir(kind: Souvenir.pickKind(owned: souvenirs, using: &random), date: now)
        souvenirs.append(souvenir)
        store(souvenirs, StoreKey.souvenirs)
        newSouvenir = souvenir
    }

    /// アプリが前面に来た。起動したときと、バックグラウンドから戻ったときだけ「おかえり」を判定する
    /// (通知センターや共有シートから戻っただけのときは判定しない)
    func sceneBecameActive(now: Date = .now) {
        guard needsWelcomeCheck else { return }
        needsWelcomeCheck = false
        let lastActive = defaults.object(forKey: StoreKey.lastActive) as? Date
        if WelcomeBack.isReturning(lastActive: lastActive, now: now) {
            welcomeDay = now
            defaults.set(now, forKey: StoreKey.welcomeDay)
        }
        defaults.set(now, forKey: StoreKey.lastActive)
    }

    func sceneEnteredBackground(now: Date = .now) {
        needsWelcomeCheck = true
        defaults.set(now, forKey: StoreKey.lastActive)
    }

    /// 「おかえり」を閉じた (その日はもう出さない)
    func dismissWelcome() {
        welcomeDay = nil
        defaults.removeObject(forKey: StoreKey.welcomeDay)
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
    /// 予約中の促す通知 (開発中の確かめ用)。予約し直しが終わってから読む
    func pendingPrompts() async -> [(date: Date, kind: Prompt.Kind, title: String)] {
        await scheduling?.value
        let titles = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) })
        return await notifier.pendingPrompts().map { ($0.date, $0.kind, titles[$0.taskID] ?? "") }
    }

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
