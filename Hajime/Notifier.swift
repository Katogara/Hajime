import UserNotifications

/// 通知に入れる情報のキー
private enum InfoKey {
    static let taskID = "taskID"
    static let kind = "kind"
    static let promptDate = "promptDate"
}

private enum NotificationID {
    static let promptCategory = "startPrompt"
    static let startAction = "startNow"
    static let timerCategory = "timerEnd"
    static let promptPrefix = "prompt-"
    static let timerEnd = "timerEnd"
    static func prompt(_ prompt: Prompt) -> String {
        "\(promptPrefix)\(prompt.taskID.uuidString)-\(prompt.kind.rawValue)-\(Int(prompt.date.timeIntervalSince1970))"
    }
}

/// 通知から届いた「始める」の操作
struct PromptResponse {
    var taskID: UUID
    var kind: Prompt.Kind
    var promptDate: Date
    /// 通知の「始める」ボタンで、すぐタイマーを始める (通知本体のタップなら一歩を見せてから)
    var startNow: Bool
}

/// 着手を促す通知と、タイマー終了の通知
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// 促す通知の「始める」が押されたとき・通知がタップされたとき
    var onStart: (@MainActor (PromptResponse) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        // 促した瞬間に迷わせないよう、促す通知のボタンは「始める」の 1 つだけにする
        let start = UNNotificationAction(identifier: NotificationID.startAction, title: "始める", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: NotificationID.promptCategory, actions: [start], intentIdentifiers: []),
            // 時間がたったら自動で「やりました！」にするので、ボタンは置かない
            UNNotificationCategory(identifier: NotificationID.timerCategory, actions: [], intentIdentifiers: []),
        ])
        center.delegate = self
    }

    /// 通知の許可を求める (2回目以降はダイアログを出さず現在の状態を返す)。許可されていれば true。
    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// 促す通知を予約し直す。予約は iOS が持つので、アプリを終了していても届く。
    func schedulePrompts(_ prompts: [Prompt], tasks: [StartTask], calendar: Calendar = .current) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier)
            .filter { $0.hasPrefix(NotificationID.promptPrefix) })
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        for prompt in prompts {
            guard let task = byID[prompt.taskID] else { continue }
            let plan = task.plan(for: prompt.kind)
            let content = UNMutableNotificationContent()
            content.title = task.title
            switch prompt.kind {
            case .first:
                content.body = Phrases.wrapped("「\(plan.step)」から。はじめるだけでいい。")
            case .nudge:
                content.body = Phrases.wrapped("「\(plan.step)」だけでいい。はじめるだけでいい。")
            }
            content.sound = .default
            content.categoryIdentifier = NotificationID.promptCategory
            content.userInfo = [
                InfoKey.taskID: task.id.uuidString,
                InfoKey.kind: prompt.kind.rawValue,
                InfoKey.promptDate: prompt.promptDate.timeIntervalSince1970,
            ]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: prompt.date)
            try? await center.add(UNNotificationRequest(
                identifier: NotificationID.prompt(prompt), content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }

    /// 始めたあと、通知センターに残っているそのやることの通知を消す
    func clearDeliveredPrompts(taskID: UUID) async {
        let delivered = await center.deliveredNotifications()
        let ids = delivered.filter { ($0.request.content.userInfo[InfoKey.taskID] as? String) == taskID.uuidString }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// 時間がたったときの通知。続きに夢中になっているかもしれないので、代わりに「やりました！」を押しておいたと知らせる。
    func scheduleTimerEnd(at date: Date, minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(minutes)分たちました"
        content.body = Phrases.wrapped("代わりに「やりました！」を押しておきました。終わったら、アプリで「おわる」を押してください。")
        content.sound = .default
        content.categoryIdentifier = NotificationID.timerCategory
        center.add(UNNotificationRequest(
            identifier: NotificationID.timerEnd, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)))
    }

    func cancelTimerEnd() {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.timerEnd])
        center.removeDeliveredNotifications(withIdentifiers: [NotificationID.timerEnd])
    }

    nonisolated private static func parse(_ userInfo: [AnyHashable: Any]) -> (UUID, Prompt.Kind, Date)? {
        guard let id = (userInfo[InfoKey.taskID] as? String).flatMap(UUID.init(uuidString:)),
              let kind = (userInfo[InfoKey.kind] as? String).flatMap(Prompt.Kind.init(rawValue:)),
              let date = userInfo[InfoKey.promptDate] as? TimeInterval else { return nil }
        return (id, kind, Date(timeIntervalSince1970: date))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let action = response.actionIdentifier
        switch content.categoryIdentifier {
        case NotificationID.promptCategory:
            if action == NotificationID.startAction || action == UNNotificationDefaultActionIdentifier,
               let parsed = Self.parse(content.userInfo) {
                let response = PromptResponse(taskID: parsed.0, kind: parsed.1, promptDate: parsed.2,
                                              startNow: action == NotificationID.startAction)
                Task { @MainActor in self.onStart?(response) }
            }
        default:
            break
        }
        completionHandler()
    }

    /// アプリを開いているときも促す通知は表示する。タイマー終了は画面で分かるので出さない
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.content.categoryIdentifier == NotificationID.promptCategory {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([])
        }
    }
}
