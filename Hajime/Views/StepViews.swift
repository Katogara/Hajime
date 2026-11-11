import SwiftUI

/// 一歩の型。押すと文が入る。一歩のコツと「その前は？」のシートで、同じ言葉と順番にする
struct StepTemplates: View {
    /// 型のない「自分で書く」も出す
    var allowsFree = false
    var freePrompt = "例: 起き上がる"
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
            ForEach(["起き上がる", "立ち上がる"], id: \.self) { step in
                StepChoiceButton(title: step) { onChoose(step) }
            }
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
/// 「お風呂」が小さな動きのカードに分かれ、いちばん上だけが最初の一歩として残る様子を、約30秒の動きで見せる。
/// 間違える役はワンのすけが引き受け、利用者には「✕」や不正解を出さない。カードを押さなくても先へ進む
struct StepTipsView: View {
    /// 閉じる。型を選んだときはその一歩 (nil なら自分で書く)
    let onClose: (String?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    @State private var scene: Scene = .task
    /// 並べ終えたカードの数
    @State private var shown = 0
    /// カードごとの揺らした回数 (増やすと揺れる)
    @State private var wiggles = Array(repeating: 0, count: StepTipsView.steps.count)
    /// 間違えた役のワンのすけが、びっくりのあと「てへ」になった
    @State private var oops = false
    /// 最初の一歩を選ぶ場面で押したカード (押さずに光ったときは nil)
    @State private var picked: Int?
    /// いちばん上のカードを光らせた
    @State private var lit = false
    /// ロック画面に通知が届いた
    @State private var noticed = false
    /// 届いた通知を押した
    @State private var tapped = false

    enum Scene: Int, CaseIterable {
        case task, split, mistake, pick, only, notice, keepGoing, choose
    }

    /// お風呂までの小さな動き。上から順にする
    static let steps = ["起き上がる", "着替えとタオルを用意する", "脱衣所へ行く", "コンタクトを外して洗う", "服を脱ぐ", "浴室に入る"]

    var body: some View {
        VStack(spacing: 0) {
            WanAsks(pose: pose, line: line)
                .padding(.horizontal, 24)
                .padding(.top, 8)
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            PageDots(count: Scene.allCases.count, current: scene.rawValue)
                .padding(.bottom, 12)
            Group {
                if scene == .choose {
                    StepChoiceButton(title: "自分で書く", style: .plain) { onClose(nil) }
                } else {
                    // 選ぶ場面では、押すか、少し待って光るまで出さない
                    StepChoiceButton(title: "次へ", action: advance)
                        .opacity(scene == .pick && !lit ? 0 : 1)
                        .disabled(scene == .pick && !lit)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .task(id: "\(scene.rawValue)-\(lit)") { try? await play() }
    }

    // MARK: 場面

    @ViewBuilder private var stage: some View {
        if scene == .task {
            Text("お風呂")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .matchedGeometryEffect(id: "title", in: namespace)
                .padding(.horizontal, 44)
                .padding(.vertical, 28)
                .background(RoundedRectangle(cornerRadius: 24).fill(Pop.orange))
                .transition(.opacity)
        } else if scene == .notice {
            lockScreen
                .transition(.opacity)
        } else if scene == .choose {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HeadlineText("迷ったら、この中から選んでみよう")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(Pop.ink)
                    PhraseText("押すと、最初の一歩に入ります。")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Pop.ink.opacity(0.75))
                    StepTemplates { onClose($0) }
                }
            }
            .transition(.opacity)
        } else {
            cards
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("お風呂")
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(Pop.orange)
                .matchedGeometryEffect(id: "title", in: namespace)
            ForEach(Self.steps.indices, id: \.self) { index in
                if index < shown {
                    card(index)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func card(_ index: Int) -> some View {
        let focus = lit && index == 0
        return HStack(spacing: 10) {
            Text(focus ? "👣" : "\(index + 1)")
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .frame(width: 26)
            Text(Self.steps[index])
                .font(.system(.body, design: .rounded, weight: .bold))
            Spacer(minLength: 0)
            // 合計の時間は見せず、最初の一歩の小ささだけを見せる
            if focus && scene.rawValue >= Scene.only.rawValue {
                Text("10秒")
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .foregroundStyle(Pop.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(focus ? Color.white : Pop.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(focus ? Pop.orange : Pop.card))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(focus ? Pop.orangeDeep : Pop.ink.opacity(scene == .pick && !lit ? 0.35 : 0.12), lineWidth: 2))
        .opacity(lit && index != 0 ? 0.3 : 1)
        .scaleEffect(focus && scene == .only && !reduceMotion ? 1.05 : 1)
        .keyframeAnimator(initialValue: 0.0, trigger: wiggles[index]) { content, angle in
            content.rotationEffect(.degrees(angle))
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-4, duration: 0.08)
                LinearKeyframe(4, duration: 0.16)
                LinearKeyframe(-3, duration: 0.14)
                LinearKeyframe(2, duration: 0.12)
                LinearKeyframe(0, duration: 0.1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { pick(index) }
        .accessibilityAddTraits(scene == .pick && !lit ? .isButton : [])
    }

    /// 通知はロック画面にこう届く、という見本 (文は Notifier の最初の通知と同じ)
    private var lockScreen: some View {
        VStack(spacing: 16) {
            Text("21:00")
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 20)
            if noticed {
                HStack(alignment: .top, spacing: 10) {
                    Text("👣")
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Pop.orange))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("お風呂")
                            .font(.system(.subheadline, weight: .bold))
                        Text("時間だよ！まずは「起き上がる」からね")
                            .font(.system(.subheadline))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.black)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.9)))
                .scaleEffect(tapped && !reduceMotion ? 0.97 : 1)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            if tapped {
                Text("経験値 +1")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(Pop.brown)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Pop.yellow))
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: 380)
        .background(RoundedRectangle(cornerRadius: 28)
            .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.2, blue: 0.36), Color(red: 0.5, green: 0.32, blue: 0.3)],
                                 startPoint: .top, endPoint: .bottom)))
        .accessibilityElement(children: .combine)
    }

    // MARK: ワンのすけ

    private var pose: WanPose {
        switch scene {
        case .task, .choose: return .wave
        case .split, .keepGoing: return .nod
        case .mistake: return oops ? .tehe : .wow
        case .pick:
            guard lit else { return .nod }
            switch picked {
            case 0: return .banzai
            case nil: return .nod
            default: return .tehe
            }
        case .only: return .banzai
        case .notice: return tapped ? .clap : .nod
        }
    }

    private var line: String {
        switch scene {
        case .task: return "お風呂を例に、始め方のコツを見せるね！"
        case .split: return "お風呂って、小さな動きが並んでできてるんだ"
        case .mistake: return "ぼく、最初の一歩を「浴室のドアを開ける」にしてた。それって、ずっとあとだった！"
        case .pick:
            guard lit else { return "通知が来たとき、からだが最初にする動きはどれ？ 押してみて" }
            switch picked {
            case 0: return "ワンダフル！ それが最初の一歩だよ"
            case nil: return "まずは、いちばん上。これが最初の一歩だよ"
            default: return "ぼくもつい、そっちから考えちゃう。その前は、これ！"
            }
        case .only: return "最初の一歩は、これだけでいいんだ"
        case .notice: return tapped ? "押して始めたら、経験値+1。ワンダフル！" : "通知には、この一歩だけが出るよ"
        case .keepGoing: return "動き出せば、次は体が勝手に進むことが多いよ。続けるかは、そのとき決めればOK"
        case .choose: return "きみのやることでも、からだの最初の動きを書いてね"
        }
    }

    // MARK: 進め方

    /// 場面ごとの動きを順に見せ、終わったら次の場面へ進む (「次へ」で先に進むと、ここは取り消される)
    private func play() async throws {
        switch scene {
        case .task:
            try await wait(3)
        case .split:
            while shown < Self.steps.count {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.7)) {
                    shown += 1
                }
                try await wait(0.3)
            }
            try await wait(2.2)
        case .mistake:
            wiggle(Self.steps.count - 1)
            try await wait(1.2)
            withAnimation { oops = true }
            wiggle(Self.steps.count - 1)
            try await wait(3.8)
        case .pick:
            guard lit else {
                // 押さなくても、少し待てばいちばん上を光らせる (止まって困らないように)
                try await wait(5)
                light(picked: nil)
                return
            }
            try await wait(2.5)
        case .only:
            try await wait(4)
        case .notice:
            try await wait(0.4)
            withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.5, dampingFraction: 0.75)) {
                noticed = true
            }
            try await wait(1.8)
            withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.35, dampingFraction: 0.55)) {
                tapped = true
            }
            try await wait(3.5)
        case .keepGoing:
            try await wait(5.5)
        case .choose:
            return
        }
        advance()
    }

    private func wait(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    private func advance() {
        guard let next = Scene(rawValue: scene.rawValue + 1) else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.5, dampingFraction: 0.85)) {
            // 並べている途中で進んだら、残りのカードもすぐ並べる
            if next.rawValue > Scene.split.rawValue { shown = Self.steps.count }
            if next == .only { lit = true }
            if next.rawValue > Scene.notice.rawValue {
                noticed = true
                tapped = true
            }
            scene = next
        }
    }

    private func pick(_ index: Int) {
        guard scene == .pick, !lit else { return }
        if index != 0 { wiggle(index) }
        light(picked: index)
    }

    private func light(picked: Int?) {
        self.picked = picked
        withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.4, dampingFraction: 0.6)) {
            lit = true
        }
    }

    private func wiggle(_ index: Int) {
        guard !reduceMotion else { return }
        wiggles[index] += 1
    }
}

/// 一歩の欄の「その前は？」から開く。今の一歩より手前の動きを型から選び、最初の一歩を置き換える
struct StepBeforeSheet: View {
    let step: String
    let onChoose: (String) -> Void
    let onKeep: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WanAsks(pose: .nod, line: "「\(step)」の前に、からだはどう動く？")
                StepTemplates(allowsFree: true, freePrompt: "例: 起き上がる", onChoose: onChoose)
                StepChoiceButton(title: "このままでOK", style: .plain, action: onKeep)
            }
            .padding(20)
        }
        .popBackground()
    }
}
