import SwiftUI

/// 一歩の型。押すと文が入る。保存時のシート・一歩のコツ・一歩を分けるシートで、同じ言葉と順番にする
struct StepTemplates: View {
    /// 型のない「自分で書く」も出す
    var allowsFree = false
    var freePrompt = "例: 浴室のドアを開ける"
    let onChoose: (String) -> Void
    /// 「＿＿へ行く」などを選んだときの型と、書き足す言葉
    @State private var template: Template?
    @State private var blank = ""
    @FocusState private var blankFocused: Bool

    enum Template: String {
        case go = "へ行く"
        case hold = "を手に持つ"
        case free = ""

        var label: String { self == .free ? "自分で書く" : "＿＿\(rawValue)" }
    }

    private var templates: [Template] { allowsFree ? [.go, .hold, .free] : [.go, .hold] }

    var body: some View {
        VStack(spacing: 12) {
            StepChoiceButton(title: "立ち上がる") { onChoose("立ち上がる") }
            ForEach(templates, id: \.self) { t in
                if template == t {
                    HStack {
                        TextField(prompt(t), text: $blank)
                            .textFieldStyle(.roundedBorder)
                            .focused($blankFocused)
                            .submitLabel(.done)
                            .onSubmit(useBlank)
                        if !t.rawValue.isEmpty {
                            Text(t.rawValue)
                                .font(.system(.body, design: .rounded, weight: .bold))
                                .foregroundStyle(Pop.ink)
                        }
                        Button("決める", action: useBlank)
                            .buttonStyle(PopButtonStyle())
                            .disabled(blank.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    StepChoiceButton(title: t.label) {
                        template = t
                        blank = ""
                        blankFocused = true
                    }
                }
            }
        }
    }

    private func prompt(_ t: Template) -> String {
        switch t {
        case .go: return "例: 洗面所"
        case .hold: return "例: タオル"
        case .free: return freePrompt
        }
    }

    private func useBlank() {
        let word = blank.trimmingCharacters(in: .whitespaces)
        guard let template, !word.isEmpty else { return }
        onChoose(word + template.rawValue)
    }
}

/// 型や「このままでOK」を並べる、横いっぱいのボタン
struct StepChoiceButton: View {
    let title: String
    var style = PopButtonStyle()
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(style)
    }
}

/// ワンのすけが吹き出しで話す、シートの頭の部分
struct WanAsks: View {
    let pose: WanPose
    let line: String

    var body: some View {
        HStack(spacing: 12) {
            WanImage(pose: pose, facing: .right)
                .frame(width: 100, height: 100)
            SpeechBubble(tail: .leading) {
                PhraseText(line)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Pop.brown)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 一歩のコツ。初めて登録するときに登録シートの最初に出し、一歩の欄の「一歩のコツ」から何度でも見られる。
/// 決まりとしてではなく、ワンのすけのコツとして伝える。悪い例に「✕」は付けない (書いた人を否定しないため)
struct StepTipsView: View {
    /// 閉じる。型を選んだときはその一歩 (nil なら自分で書く)
    let onClose: (String?) -> Void
    @State private var page = 0
    @State private var answer: QuizChoice?

    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                start.tag(0)
                quiz.tag(1)
                choose.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageDots(count: lastPage + 1, current: page)
                .padding(.bottom, 12)

            if page < lastPage {
                StepChoiceButton(title: "次へ") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { page += 1 }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            } else {
                StepChoiceButton(title: "自分で書く", style: .plain) { onClose(nil) }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
    }

    private var start: some View {
        TipsPage(pose: .wave, line: "ぼくのコツ、教えるね！", title: "始めるところだけ決めよう") {
            PhraseText("やることを全部しなくて大丈夫。決めた時刻に、最初の一歩だけを通知でお知らせします。")
            PhraseText("一歩は、からだを1回動かすだけで終わる行動にします。")
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(Pop.ink)
            VStack(alignment: .leading, spacing: 8) {
                example("お風呂", "浴室のドアを開ける")
                example("筋トレ", "ウェアを手に持つ")
            }
        }
    }

    private var quiz: some View {
        TipsPage(pose: answer == .door ? .clap : .nod, line: answer?.reply ?? "ぼくからクイズ！ どれがいちばん始めやすいかな？",
                 title: "お風呂の最初の一歩は、どれ？") {
            VStack(spacing: 12) {
                ForEach(QuizChoice.allCases, id: \.self) { choice in
                    StepChoiceButton(title: choice.rawValue,
                                     style: answer == choice ? PopButtonStyle() : .plain) {
                        withAnimation { answer = choice }
                    }
                }
            }
            if answer != nil {
                PhraseText("いくつかの動作に分けられたら、まだ大きいかも。")
                    .font(.system(.subheadline, design: .rounded))
            }
        }
    }

    private var choose: some View {
        TipsPage(pose: .clap, line: "一歩で終わっても「やりました！」だよ。続けたくなったら、そのまま続けてOK",
                 title: "迷ったら、この中から選んでみよう") {
            PhraseText("押すと、最初の一歩に入ります。")
                .font(.system(.subheadline, design: .rounded))
            StepTemplates { onClose($0) }
        }
    }

    private func example(_ title: String, _ step: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            Image(systemName: "arrow.right")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Pop.orange)
            Text("👣 \(step)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Pop.ink)
        }
    }

    /// クイズの候補。どれを選んでも褒め、不正解とは言わない
    private enum QuizChoice: String, CaseIterable {
        case bath = "お風呂に入る"
        case contact = "コンタクトを取る"
        case door = "浴室のドアを開ける"

        var reply: String {
            switch self {
            case .bath: return "それもいいね！ でも、服を脱いで、体を洗って…と、いくつかの動作に分けられそう。もっと手前はどれかな？"
            case .contact: return "それもいいね！ でも、洗面所へ行って、手を洗って…と、いくつかの動作に分けられそう。もっと手前はどれかな？"
            case .door: return "ワンダフル！ からだを1回動かすだけで終わるね。これなら、やる気が出ない日でもできるよ"
            }
        }
    }
}

/// 一歩のコツの 1 ページ
private struct TipsPage<Content: View>: View {
    let pose: WanPose
    let line: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WanAsks(pose: pose, line: line)
                    .padding(.top, 8)
                HeadlineText(title)
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .foregroundStyle(Pop.ink)
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Pop.ink.opacity(0.75))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}

/// 一歩をもっと手前の一歩に分ける。編集画面の「この一歩を分ける」と、使ったあとの提案から開く。
/// 分ける前の一歩は「次」として残す (通知には分けた一歩だけを出す)。分けられるのは 1 回だけ
struct StepSplitSheet: View {
    let step: String
    /// 始めなかったあとの提案として開いた (ワンのすけが自分の見積もりのせいにして聞く)
    var offer = false
    let onChoose: (String) -> Void
    /// この一歩を、別の時刻にできる新しいやることにする
    let onOtherTask: () -> Void
    let onKeep: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WanAsks(pose: offer ? .tehe : .nod,
                        line: offer ? "ぼくの見積もりが大きすぎたかも！ もっと手前から始めてみる？"
                                    : "「\(step)」の、もっと手前は？ 最初に、からだをどう動かす？")
                Text("いまの一歩: \(step)")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Pop.ink.opacity(0.6))
                StepTemplates(allowsFree: true, freePrompt: "例: 洗面所へ行く", onChoose: onChoose)
                StepChoiceButton(title: offer ? "このままでOK" : "やめておく", style: .plain, action: onKeep)
                Button("「\(step)」を別のやることにする", action: onOtherTask)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Pop.ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .popBackground()
    }
}
