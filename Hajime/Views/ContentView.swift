import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 褒める演出の強さ (設定で選ぶ)
    @AppStorage("cheerStyle") private var cheerStyleRaw = ""

    private var cheerStyle: CheerStyle { CheerStyle.resolve(cheerStyleRaw, reduceMotion: reduceMotion) }

    var body: some View {
        @Bindable var model = model
        ZStack {
            // タイマーが動いている間は、画面全体をタイマーにする (アプリを開き直しても戻る)
            if let session = model.session {
                TimerView(session: session)
            } else {
                TaskListView()
            }
            if let cheer = model.cheer {
                if cheerStyle == .small && cheer.kind != .graduated {
                    // 控えめ: 全画面にせず、画面の下の帯で褒める
                    Color.clear
                        .wanBand($model.cheer) { cheer in
                            CheerBand(cheer: cheer, step: words(for: cheer)?.step, title: words(for: cheer)?.title)
                        }
                        .zIndex(1)
                } else {
                    CheerView(cheer: cheer, style: cheerStyle, step: words(for: cheer)?.step,
                              title: words(for: cheer)?.title) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            if model.cheer == cheer { model.cheer = nil }
                        }
                    }
                    .id(cheer.id)
                    .transition(.opacity)
                    .zIndex(1)
                }
            } else if let souvenir = model.newSouvenir {
                // おみやげは褒める演出が終わってから見せる
                if cheerStyle == .small {
                    Color.clear
                        .wanBand($model.newSouvenir, seconds: 4) { souvenir in
                            SouvenirBand(souvenir: souvenir)
                        }
                        .zIndex(1)
                } else {
                    SouvenirView(souvenir: souvenir) {
                        withAnimation(.easeOut(duration: 0.3)) { model.newSouvenir = nil }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
        // 「やっぱりやめます」のあと、ワンのすけがふだんと同じ明るさで見送る
        .wanBand($model.farewell) { farewell in
            WanBand(pose: .nod, text: farewell.line)
        }
    }

    /// 褒め言葉に差し込む一歩と名前。やることが消えているときと、秘密❤️のときは差し込まない
    private func words(for cheer: Cheer) -> (step: String, title: String)? {
        guard let id = cheer.taskID, !model.secretTaskIDs.contains(id), let task = model.task(id: id) else {
            return nil
        }
        return (task.firstStep, task.title)
    }
}

private struct TaskListView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: StartTask?
    @State private var showingHistory = false
    @State private var showingIntro = false
    @State private var showingSettings = false
    /// 分身の姿を選ぶ画面
    @State private var choosingAvatar: AvatarChoiceMode?
    /// 「今日は何時から」を候補以外の時刻にするとき
    @State private var pickingTime: StartTask?
    /// 説明を一度見たら、次からは自動で出さない (タイトルのタップでいつでも見られる)
    @AppStorage("introSeen") private var introSeen = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if model.showsWelcome {
                        WelcomeBubble { withAnimation { model.dismissWelcome() } }
                            .transition(.opacity)
                    }
                    HStack(spacing: 10) {
                        AvatarFaceButton(avatar: model.avatar) { choosingAvatar = .again }
                        LevelBadge(progress: model.level)
                    }
                    if model.tasks.isEmpty {
                        emptyCard
                    }
                    // 日が変わった「今日だけ」のやることは出さない (次に開いたときに消える)
                    // 今日促す時刻の早い順 (同じ時刻なら登録順)
                    let tasks = model.tasks.enumerated().filter { !$0.element.isExpired(now: .now) }
                        .sorted { ($0.element.promptMinute(on: .now), $0.offset) < ($1.element.promptMinute(on: .now), $1.offset) }
                    // 今日はじめたものは、キラキラさせたまま下へ (色は元の並びで決め、動いても変えない)
                    let ordered = tasks.filter { !model.doneToday($0.element) } + tasks.filter { model.doneToday($0.element) }
                    ForEach(ordered, id: \.element.id) { index, task in
                        TaskCard(task: task, color: Pop.taskColor(index), done: model.doneToday(task),
                                 shareable: !model.secretTaskIDs.contains(task.id), avatar: model.avatar) {
                            editing = task
                        } onStart: {
                            model.start(taskID: task.id)
                        } onOneDay: { date in
                            model.setOneDayTime(date, for: task.id)
                        } onPickTime: {
                            pickingTime = task
                        } onUndo: {
                            model.undoDone(task)
                        }
                    }
                }
                // はじめた (経験値が増えた) ときと、取り消した (減った) ときに、カードが動く様子を見せる
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: model.xp)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .popBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // ツールバーの Label は文字が隠れてアイコンだけになることがあるので、アイコンと名前を自分で並べる
                    Button { showingHistory = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.stack.3d.up.fill")
                            Text("これまでのつみあげ")
                                .fixedSize()
                        }
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .foregroundStyle(Pop.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Pop.orange.opacity(0.15)))
                    }
                    .accessibilityLabel("これまでのつみあげ")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    RoundIconButton(systemImage: "gearshape.fill", label: "設定") { showingSettings = true }
                    RoundIconButton(systemImage: "plus", label: "追加", filled: true) { editing = .draft() }
                }
            }
            .sheet(item: $editing) { task in
                TaskEditView(task: task, isNew: model.task(id: task.id) == nil)
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $model.ready) { prompt in
                ReadyView(prompt: prompt)
            }
            .sheet(item: $pickingTime) { task in
                OneDayTimeSheet(task: task) { model.setOneDayTime($0, for: task.id) }
            }
            .fullScreenCover(isPresented: $showingIntro, onDismiss: {
                introSeen = true
                // 最初の説明を見終えたら、分身の姿を選ぶ (説明を見直したときは出さない)
                if !model.avatarAsked { choosingAvatar = .first }
            }) {
                IntroView()
            }
            .fullScreenCover(item: $choosingAvatar) { mode in
                AvatarChoiceView(first: mode == .first)
            }
            .onAppear {
                if !introSeen {
                    showingIntro = true
                } else if !model.avatarAsked {
                    // 姿を選べるようになる前から使っている人にも、一度だけ聞く
                    choosingAvatar = .first
                }
            }
        }
    }

    /// タイトルをタップすると、いつでも説明を見られる
    private var header: some View {
        Button { showingIntro = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("はじめる")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(Pop.orange)
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Pop.orange.opacity(0.45))
                }
                PhraseText("ちょっとだけ、やってみよ。")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Pop.ink.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("アプリの説明を表示します")
        .padding(.top, 4)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🌱")
                .font(.system(size: 48))
            HeadlineText("なかなか始められないこと、ありますか？")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(Pop.ink)
            PhraseText("決めた時刻に、最初の一歩だけを通知でお知らせします。「はじめる」を押したら、たっぷり褒めます。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Pop.ink.opacity(0.7))
            Button("やることを追加") { editing = .draft() }
                .buttonStyle(PopButtonStyle())
                .padding(.top, 4)
        }
        .popCard(tint: Pop.orange)
    }
}

/// 分身の姿を選ぶ画面の出し方
private enum AvatarChoiceMode: Identifiable {
    /// 最初の「どっちのきみで始める？」(選ばずに閉じられる)
    case first
    /// 一覧の顔から開いて選び直す
    case again

    var id: Self { self }
}

/// ツールバーの丸いボタン
private struct RoundIconButton: View {
    let systemImage: String
    let label: String
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(filled ? Color.white : Pop.orange)
                .frame(width: 34, height: 34)
                .background(Circle().fill(filled ? Pop.orange : Pop.orange.opacity(0.15)))
        }
        .accessibilityLabel(label)
    }
}

private struct TaskCard: View {
    let task: StartTask
    let color: Color
    /// 今日だけのやることを、もう始めた (カードをキラキラさせて褒め続ける)
    var done = false
    /// 今日はじめたことをシェアできる (秘密❤️にしたやることは出さない)
    var shareable = false
    var avatar: AvatarBody?
    @Environment(\.dressing) private var dressing
    let onEdit: () -> Void
    let onStart: () -> Void
    /// 今日だけの時刻を決める (nil でいつもの時刻に戻す)
    let onOneDay: (Date?) -> Void
    let onPickTime: () -> Void
    /// まちがえて押した「やりました！」を取り消す
    let onUndo: () -> Void

    var body: some View {
        // 候補の時刻と「今日は」の表示が古くならないよう、1 分ごとに作り直す
        TimelineView(.everyMinute) { context in
            let oneDay = task.oneDayTime(on: context.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        PhraseText(task.title)
                            .font(.system(.title3, design: .rounded, weight: .heavy))
                            .foregroundStyle(Pop.ink)
                        PhraseText("👣 \(task.firstStep)")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(Pop.ink.opacity(0.75))
                        if task.isOneDay {
                            PopChip(text: "🌟 \(task.scheduleText)", color: Pop.pink)
                        } else if let oneDay {
                            HStack(spacing: 6) {
                                PopChip(text: "今日は \(StartTask.timeText(oneDay)) から", color: Pop.orange)
                                PhraseText("いつもは \(task.scheduleText)")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Pop.ink.opacity(0.5))
                            }
                        } else {
                            PopChip(text: "⏰ \(task.scheduleText)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onEdit)
                    // 通知を待たずに、自分で気づいたときも 1 タップで始められる
                    if !done {
                        Button(action: onStart) {
                            VStack(spacing: 2) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 18, weight: .black))
                                Text("はじめる")
                                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                            }
                        }
                        .buttonStyle(PopButtonStyle(depth: 4))
                        .accessibilityLabel("\(task.title)をはじめる")
                    }
                }
                if done {
                    DonePraise(shareCard: shareable ? ShareCard(step: task.firstStep, avatar: avatar, dressing: dressing) : nil,
                               onAgain: onStart, onUndo: onUndo)
                } else {
                    timeMenu(oneDay: oneDay, now: context.date)
                }
            }
            .popCard(tint: done ? Pop.yellow : color, shimmer: done)
            .overlay {
                if done { Sparkles().allowsHitTesting(false) }
            }
        }
    }

    /// 日によって始めたい時刻が違うとき、メニューを開いて時刻を選ぶだけ (2 タップ) で今日だけ変える
    private func timeMenu(oneDay: Date?, now: Date) -> some View {
        Menu {
            Section("今日だけ、何時から？") {
                ForEach(StartTask.oneDayChoices(now: now), id: \.self) { date in
                    Button(StartTask.timeText(date)) { onOneDay(date) }
                }
            }
            Button("時刻を指定…", systemImage: "clock", action: onPickTime)
            // 今日だけのやることには「いつもの時刻」がない
            if oneDay != nil && !task.isOneDay {
                Button("いつもの時刻に戻す", systemImage: "arrow.uturn.backward") { onOneDay(nil) }
            }
        } label: {
            Label(menuTitle(oneDay: oneDay), systemImage: "clock.arrow.circlepath")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Pop.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(Pop.orange.opacity(0.12)))
        }
    }

    private func menuTitle(oneDay: Date?) -> String {
        if task.isOneDay { return "別の時間にする？" }
        return oneDay == nil ? "今日は別の時間にする？" : "今日の時間を変える・戻す"
    }
}

/// 今日はじめたあと、カードに出し続ける褒め言葉。まちがえて「やりました！」を押したときは取り消せる
private struct DonePraise: View {
    /// シェア用のカード (秘密❤️のやることでは nil にして、ボタンを出さない)
    let shareCard: ShareCard?
    let onAgain: () -> Void
    let onUndo: () -> Void
    @State private var confirmingUndo = false
    @State private var sharing: SharedImage?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            praise
            HStack(spacing: 14) {
                // 押したときだけ画像を作る。押すかどうかは本人しだいなので、目立たせない
                if let shareCard {
                    Button {
                        if let image = shareCard.render() { sharing = SharedImage(image: image) }
                    } label: {
                        Label("シェア", systemImage: "square.and.arrow.up")
                    }
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Pop.ink.opacity(0.55))
                }
                // 目立たせず、押しまちがえないよう確認してから取り消す
                undoButton
            }
        }
        .sheet(item: $sharing) { shared in
            ShareSheet(image: shared.image)
                .presentationDetents([.medium, .large])
        }
    }

    private var undoButton: some View {
        Button("まちがえて押した？") { confirmingUndo = true }
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(Pop.ink.opacity(0.45))
            .confirmationDialog("「やりました！」を取り消しますか？", isPresented: $confirmingUndo,
                                titleVisibility: .visible) {
                Button("取り消す", role: .destructive, action: onUndo)
                Button("そのままにする", role: .cancel) {}
            } message: {
                Text("今日の経験値が元に戻り、カードも元の位置に戻ります。")
            }
    }

    private var praise: some View {
        HStack(spacing: 10) {
            // 揺れは時刻から計算する (repeatForever のアニメーションだと、カードの並び替えの動きまで巻き込んで
            // 画面の外とカードの間を行き来してしまうため)
            TimelineView(.animation) { context in
                let wave = sin(context.date.timeIntervalSinceReferenceDate * 5)
                // ワンのすけが拍手で褒め続ける
                WanImage(pose: .clap, facing: .right)
                    .frame(width: 52, height: 52)
                    .scaleEffect(1.02 + 0.06 * wave)
                    .rotationEffect(.degrees(6 * wave))
            }
            VStack(alignment: .leading, spacing: 2) {
                HeadlineText("できた！えらすぎる！")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(Pop.orange)
                PhraseText("今日のぶん、ちゃんと始められました")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Pop.ink.opacity(0.6))
            }
            Spacer(minLength: 0)
            Button("もう一回", action: onAgain)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .buttonStyle(PopButtonStyle.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pop.yellow.opacity(0.25)))
    }
}

/// カードの上でまたたくキラキラ
private struct Sparkles: View {
    private let spots: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: Double)] = [
        (0.08, 0.12, 18, 0), (0.92, 0.10, 22, 0.4), (0.70, 0.30, 14, 0.9),
        (0.18, 0.80, 16, 1.3), (0.88, 0.78, 20, 0.6), (0.50, 0.06, 12, 1.1),
    ]

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(spots.indices, id: \.self) { index in
                        let spot = spots[index]
                        // 0〜1 を行き来する。ずらしてばらばらにまたたかせる
                        let wave = (sin((t + spot.delay) * 3) + 1) / 2
                        Text("✨")
                            .font(.system(size: spot.size))
                            .scaleEffect(0.5 + wave * 0.7)
                            .opacity(0.25 + wave * 0.75)
                            .rotationEffect(.degrees(wave * 40))
                            .position(x: proxy.size.width * spot.x, y: proxy.size.height * spot.y)
                    }
                }
            }
        }
    }
}

/// 「今日は何時から」を候補以外の時刻にする
private struct OneDayTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: StartTask
    let onSave: (Date) -> Void
    @State private var time = Date()

    var body: some View {
        let now = Date()
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now
        NavigationStack {
            VStack(spacing: 16) {
                HeadlineText("今日の「\(task.title)」は何時から？")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Pop.ink)
                DatePicker("時刻", selection: $time, in: now...max(now, endOfDay), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                Button("この時刻にする") {
                    onSave(time)
                    dismiss()
                }
                .buttonStyle(PopButtonStyle())
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .popBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            time = task.oneDayTime(on: now) ?? now.addingTimeInterval(30 * 60)
        }
    }
}
