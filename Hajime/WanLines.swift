import Foundation

/// ワンのすけのせりふ。褒め言葉と説明は、ワンのすけが話している体裁にする。
/// 性格は「褒め上手で少しおっちょこちょい」(失敗するのはワンのすけ自身だけ)。口ぐせは「ワンダフル！」で、各区分 1 本まで。
/// 責めない・比べない・急かさない。性別で言葉を変えない。何をしたかを具体的に褒める。
/// 話し方 (2026-11-11、ワンのすけの言葉チーム): 一人称は「ぼく」、相手の呼び方はなるべく書かない。
/// です・ます調にせず「ね・よ」で話す。大げさにするのは、行動の描写・短い叫び・ワンのすけの体の反応 (しっぽ、耳、跳ねる)。
/// 言わないこと: 待ってる・さみしい・お腹すいた、見張る感じ (見てたよ、覚えておく)、勝ち負け、「来てくれてうれしい」のように機嫌が行動で変わる言い方
enum WanLines {
    /// 見出し (短い叫び) とひとこと。{step} は最初の一歩、{title} はやることに置き換える
    struct Line: Equatable {
        var title: String
        var sub: String

        init(_ title: String, _ sub: String) {
            self.title = title
            self.sub = sub
        }

        var usesTask: Bool { (title + sub).contains("{") }

        func filled(step: String, title name: String) -> Line {
            func fill(_ text: String) -> String {
                text.replacingOccurrences(of: "{step}", with: step).replacingOccurrences(of: "{title}", with: name)
            }
            return Line(fill(title), fill(sub))
        }
    }

    /// 始めたとき (一歩はこれからなので、やり終えたようには言わない)
    static let started: [Line] = [
        Line("はじめたね、天才！", "{step}から動き出したね。ぼく、うれしくてバンザイしちゃった"),
        Line("{step}、スタート！", "いちばん重い最初の一歩に、ちゃんと手をかけたね"),
        Line("{title}、始まった！", "ほんとうに始めたね。ぼく、拍手が止まらないよ"),
        Line("ワンダフル！", "{step}から始めるの、すごくいい選び方だね"),
        Line("動いたね！", "体が動き出したね。ぼく、思わず跳ねちゃった"),
        Line("{title}のスタート！", "ぼく、拍手しすぎて転びそう"),
        Line("始められた！", "{step}から入ったの、ばっちりだよ"),
        Line("もう始まってる！", "もう{title}の中にいるね。しっぽがぶんぶん"),
        Line("最高のスタート！", "{step}から始める作戦、大成功だね"),
        Line("すごい、動いた！", "いま始めたこと、ぼくまでうれしくなっちゃう"),
        Line("はじめの一歩！", "{title}の扉、いま開いたね"),
        Line("始めたね！", "びっくりして、ぼくの耳がぴんと立っちゃった"),
        Line("拍手！", "うれしくて、しっぽがちぎれそう"),
        Line("小さく始めた！", "小さく始めるの、すごくいいやり方だよ"),
        Line("いいスタート！", "始めるって決めて、ほんとうに始めた。そこがすごいよ"),
        Line("やったー、はじめた！", "ぼく、その場でぴょんぴょんしてるよ"),
    ]

    /// 「やりました！」(一歩をやった。終わらせることは求めない)
    static let continued: [Line] = [
        Line("一歩、やったね！", "{step}、ちゃんとやったね。ぼく、大はしゃぎだよ"),
        Line("やったね！", "始めて、一歩やった。きれいな流れだね"),
        Line("ワンダフル！", "いまの一歩、ちゃんと本物だよ"),
        Line("おつかれさま！", "ここまで動いた体と頭に、ぼくから拍手"),
        Line("一歩進んだね！", "{step}から、ここまで来たんだね"),
        Line("すごすぎる！", "うれしくて、ぼく、その場でぐるぐる回っちゃった"),
        Line("動き出した！", "今日の{title}、ちゃんと動き出したね"),
        Line("ばっちり！", "手を動かしたね。ぼく、しっぽふりふり"),
        Line("お見事！", "一歩やった自分に、ありがとうって言ってもいいくらいだよ"),
        Line("受け取ったよ！", "やった一歩、ぼくまでほくほくしちゃう"),
        Line("いい一歩だったね！", "{title}、いい流れができたね"),
        Line("やったー！", "感動して、鼻がぴくぴくしてる"),
    ]

    static let levelUp: [String] = [
        "一回一回の「はじめた」が、ここまで積み上がったよ",
        "ワンダフル！始めてきたことが、ちゃんと力になってるね",
        "お祝いの準備をしてたら、しっぽを踏んじゃった",
        "始める力が、ぐんぐん育ってるね",
        "ぼく、うれしくてくす玉を三つも割っちゃった",
        "ここから見える景色、ちょっと違うでしょ",
        "「はじめる」が、どんどん軽くなってきたかも",
        "ぼく、記念の踊りを考えてきたよ。見てて！",
    ]

    /// 「やっぱりやめます」への返事。ふだんと同じ明るさで
    static let farewell = [
        "わかった、またね。今日もいい日にね",
        "オッケー。開いてくれてありがとう、またね",
        "やめるのも、ちゃんとした選び方だよ。またね",
    ]

    /// 久しぶりに開いた日のあいさつ。日数も、待っていたことも言わない
    static let welcome: [Line] = [
        Line("おかえり！", "ちょうど昼寝から起きたところだよ"),
        Line("やあ、おかえり！", "ぼく、新しい芸を練習してたんだ"),
    ]

    /// おみやげを渡すとき
    static let souvenir = [
        "あ、これ、おみやげ。はじめた記念にどうぞ",
        "散歩でいいもの見つけたんだ。今日の一歩の記念に、持っててね",
        "はい、これ。あれ、逆さまだった。どうぞ！",
    ]

    // MARK: - 通知

    /// 決めた時刻の通知の本文。{step} は本文の先頭か 1 文目に置く
    static let firstPrompt = [
        "「{step}」から、はじめてみよ。ぼく、そばで応援してるよ",
        "「{step}」だけで十分だよ。いっしょにはじめよう",
        "時間だよ！まずは「{step}」からね",
        "「{step}」から、ちょっとだけやってみよ。ぼく、応援の準備ばっちりだよ",
    ]
    /// 再通知 (1 回だけ。これが最後なので、終わりと、やめてもいいことを見せる。1 回目には触れない)
    static let nudgePrompt = [
        "もう一回だけ声をかけるね。「{step}」だけでいいよ",
        "「{step}」からでも大丈夫。今日はやめても、もちろんいいよ",
        "お知らせはこれで最後だよ。気が向いたら「{step}」から、ね",
    ]
    /// 秘密❤️のやること (通知にもやることの名前と一歩を出さない)
    static let secretFirstPrompt = [
        "時間だよ！まずは一歩だけ、はじめてみよ",
        "決めた時刻だよ。最初の一歩から、いっしょにはじめよう",
    ]
    static let secretNudgePrompt = [
        "お知らせはこれで最後だよ。気が向いたら、一歩だけどうぞ",
    ]
    /// 秘密❤️のやることの通知のタイトル
    static let secretPromptTitle = "🐾 ワンのすけ"
    /// 一歩が長いとき (この字数を超えたら)、決まった部分が短い本文だけから選ぶ
    static let longStep = 15
    static let shortFixed = 21

    /// 時間がたって、代わりに「やりました！」を押したときの通知の本文 (タイトルは「N分たったよ」)
    static let timerEnd = [
        "「やりました！」、肉球でぽちっと押しといたよ",
        "「やりました！」は押しておいたから、続けてもやめても大丈夫",
    ]

    /// 促す通知のタイトルと本文。seed で文を選ぶ (同じ通知を予約し直しても文が変わらないように)
    static func notification(kind: Prompt.Kind, step: String, title: String, secret: Bool,
                             seed: Int) -> (title: String, body: String) {
        let pool: [String]
        if secret {
            pool = kind == .first ? secretFirstPrompt : secretNudgePrompt
        } else {
            let all = kind == .first ? firstPrompt : nudgePrompt
            let short = all.filter { $0.count - "{step}".count <= shortFixed }
            pool = step.count > longStep && !short.isEmpty ? short : all
        }
        let body = pool[abs(seed) % pool.count].replacingOccurrences(of: "{step}", with: step)
        return (secret ? secretPromptTitle : title, body)
    }

    /// 褒め言葉を 1 つ選び、やることの名前を差し込む。
    /// やることが消えているときと、秘密❤️にしているときは、名前を使わないせりふから選ぶ
    static func pick(from lines: [Line], step: String?, title: String?,
                     using random: inout some RandomNumberGenerator) -> Line {
        guard let step, let title, !step.isEmpty, !title.isEmpty else {
            return lines.filter { !$0.usesTask }.randomElement(using: &random) ?? lines[0]
        }
        return lines.randomElement(using: &random)!.filled(step: step, title: title)
    }
}

/// 褒める演出の強さ。設定で選ぶ (最初は「大げさ」。「視差効果を減らす」がオンの人は「控えめ」)
enum CheerStyle: String, CaseIterable, Identifiable {
    /// 全画面で、光の輪と紙吹雪
    case big
    /// 全画面だが、飾りを減らして短く
    case normal
    /// 全画面にせず、画面の下にワンのすけの小さな帯を出す
    case small

    var id: Self { self }

    var label: String {
        switch self {
        case .big: return "大げさ"
        case .normal: return "ふつう"
        case .small: return "控えめ"
        }
    }

    /// 保存した値から読む。まだ選んでいない (知らない値も) ときは、視差効果の設定で決める
    static func resolve(_ stored: String, reduceMotion: Bool) -> CheerStyle {
        CheerStyle(rawValue: stored) ?? (reduceMotion ? .small : .big)
    }
}

/// ワンのすけのおみやげ。予告なく、ときどき拾ってくる「はじめた証」(ごほうびとは呼ばない)。
/// もらったものだけを見せ、まだもらっていないものの一覧は出さない。レア度はない
struct Souvenir: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: String
    var date: Date

    var item: Item? { Self.items.first { $0.kind == kind } }

    struct Item: Equatable {
        var kind: String
        var emoji: String
        var name: String
        var note: String
    }

    /// 食べ物はお腹をすかせる連想があるので入れない
    static let items: [Item] = [
        Item(kind: "shell", emoji: "🐚", name: "貝がら", note: "散歩で拾った。海は遠いのに"),
        Item(kind: "clover", emoji: "🍀", name: "四つ葉", note: "数え直したら三つ葉かも"),
        Item(kind: "stone", emoji: "🪨", name: "すべすべの石", note: "くわえてたら持って帰ってた"),
        Item(kind: "feather", emoji: "🪶", name: "羽根", note: "くしゃみで飛ばしかけた"),
        Item(kind: "leaf", emoji: "🍂", name: "落ち葉", note: "いちばんいい色を選んだよ"),
        Item(kind: "star", emoji: "⭐️", name: "星のかけら", note: "空から落ちてきた、気がする"),
        Item(kind: "balloon", emoji: "🎈", name: "風船", note: "飛ばされかけて、走って取った"),
        Item(kind: "bell", emoji: "🔔", name: "鈴", note: "首に付けたら、うるさかった"),
        Item(kind: "compass", emoji: "🧭", name: "方位磁石", note: "ぼくが持ってても迷う"),
        Item(kind: "petal", emoji: "🌸", name: "花びら", note: "鼻にくっついてきた"),
    ]

    /// 初めて始めた日から、最初のおみやげまでの日数
    static let firstAfterDays = 7
    /// 前のおみやげから、次までの日数
    static let intervalDays = 20
    /// 条件を満たした日に、実際に拾ってくる確率 (いつ来るか分からないようにする)
    static let chance = 1.0 / 3

    /// 今日の最初の「はじめた」でおみやげを渡すか。
    /// - Parameters:
    ///   - firstUse: 初めて始めた日時 (記録がなければ渡さない)
    ///   - last: 前のおみやげの日時
    ///   - startedEarlierToday: 今日すでに経験値がたまっていた (その日の最初の 1 回だけにする)
    ///   - roll: 0 以上 1 未満の乱数
    static func shouldGive(now: Date, firstUse: Date?, last: Date?, startedEarlierToday: Bool, roll: Double,
                           calendar: Calendar = .current) -> Bool {
        guard let firstUse, !startedEarlierToday else { return false }
        func days(since date: Date) -> Int {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                    to: calendar.startOfDay(for: now)).day ?? 0
        }
        if let last {
            // 時計を戻されても同じ日に 2 回は渡さない
            guard days(since: last) >= intervalDays else { return false }
        } else {
            guard days(since: firstUse) >= firstAfterDays else { return false }
        }
        return roll < chance
    }

    /// まだ持っていない品から選ぶ (全部持っていれば、どれでも)
    static func pickKind(owned: [Souvenir], using random: inout some RandomNumberGenerator) -> String {
        let ownedKinds = Set(owned.map(\.kind))
        let fresh = items.filter { !ownedKinds.contains($0.kind) }
        return (fresh.isEmpty ? items : fresh).randomElement(using: &random)!.kind
    }
}

/// 久しぶりに開いた日に「おかえり」と言うか (日数は言わない)
enum WelcomeBack {
    /// 前に開いた日から、この日数以上あいていたら
    static let days = 3

    static func isReturning(lastActive: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastActive else { return false }
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastActive),
                                          to: calendar.startOfDay(for: now)).day ?? 0
        return gap >= days
    }
}
