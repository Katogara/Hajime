import Foundation

/// ユーザーの分身のアバターの体。最初に選び、あとから設定でいつでも無料で選び直せる。
/// 選んだものは見た目にだけ使い、褒め言葉や通知の文は変えない。買った衣装は選び直しても残す。
enum AvatarBody: String, CaseIterable, Codable {
    case male
    case female

    /// 読み上げ用の名前。画面には性別の言葉を出さないので、髪型で呼ぶ
    var spokenName: String {
        switch self {
        case .male: return "短い髪の姿"
        case .female: return "ボブの髪の姿"
        }
    }

    func imageName(_ pose: AvatarPose) -> String {
        "avatar_\(rawValue)_\(pose.rawValue)"
    }
}

/// アバターの表情
enum AvatarPose: String, CaseIterable {
    case normal
    case smile
    /// 両手を上げて跳ぶ大喜び。褒める画面の主役
    case joy
}

/// ワンのすけの表情とポーズ。機嫌はユーザーの行動に左右されないので、悲しむ・待つ表情はない
enum WanPose: String, CaseIterable {
    /// にっこり片手を振る (基本)
    case wave
    /// ばんざいジャンプ (始めたとき)
    case banzai
    /// 拍手 (「やりました！」のとき)
    case clap
    /// キラキラ目でびっくり (レベルアップ)
    case wow
    /// しっぽにつまずいて「てへ」(アプリ側の失敗を引き受けるとき)
    case tehe
    /// 穏やかにうなずく (「やめます」への返事。仮素材は目が線なのでまだ使わない)
    case nod
    /// おみやげを差し出す
    case gift
    /// まばたき
    case blink

    var imageName: String { "wan_\(rawValue)" }
}

/// アバターの選択を UserDefaults に保存する。まだ選んでいなければ nil (ワンのすけだけで褒める)
struct AvatarStore {
    private let defaults: UserDefaults

    private enum Key {
        static let body = "avatarBody"
        /// 最初の「どっちのきみで始める？」を一度出した (選ばずに閉じても、もう自動では出さない)
        static let asked = "avatarAsked"
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 知らない値 (今後の版で増えたものなど) は nil として扱う
    var body: AvatarBody? {
        defaults.string(forKey: Key.body).flatMap(AvatarBody.init(rawValue:))
    }

    var asked: Bool {
        defaults.bool(forKey: Key.asked)
    }

    func choose(_ body: AvatarBody) {
        defaults.set(body.rawValue, forKey: Key.body)
        defaults.set(true, forKey: Key.asked)
    }

    func markAsked() {
        defaults.set(true, forKey: Key.asked)
    }
}
