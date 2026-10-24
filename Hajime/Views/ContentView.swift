import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            // タイマーが動いている間は、画面全体をタイマーにする (アプリを開き直しても戻る)
            if let session = model.session {
                TimerView(session: session)
            } else {
                TaskListView()
            }
            if let cheer = model.cheer {
                CheerView(cheer: cheer) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        if model.cheer == cheer { model.cheer = nil }
                    }
                }
                .id(cheer.id)
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}

private struct TaskListView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: StartTask?
    @State private var showingHistory = false
    @State private var showingIntro = false
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
                    LevelBadge(progress: model.level)
                    if model.tasks.isEmpty {
                        emptyCard
                    }
                    // 日が変わった「今日だけ」のやることは出さない (次に開いたときに消える)
                    let tasks = model.tasks.filter { !$0.isExpired(now: .now) }
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        TaskCard(task: task, color: Pop.taskColor(index),
                                 done: task.isOneDay && model.startedToday(task)) {
                            editing = task
                        } onStart: {
                            model.start(taskID: task.id)
                        } onOneDay: { date in
                            model.setOneDayTime(date, for: task.id)
                        } onPickTime: {
                            pickingTime = task
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .popBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingHistory = true } label: {
                        Label("つみあげ", systemImage: "square.stack.3d.up.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(.subheadline, design: .rounded, weight: .heavy))
                            .foregroundStyle(Pop.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Pop.orange.opacity(0.15)))
                    }
                    .accessibilityLabel("これまでのつみあげ")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    RoundIconButton(systemImage: "plus", label: "追加", filled: true) { editing = .draft() }
                }
            }
            .sheet(item: $editing) { task in
                TaskEditView(task: task, isNew: model.task(id: task.id) == nil)
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView()
            }
            .sheet(item: $model.ready) { prompt in
                ReadyView(prompt: prompt)
            }
            .sheet(item: $pickingTime) { task in
                OneDayTimeSheet(task: task) { model.setOneDayTime($0, for: task.id) }
            }
            .fullScreenCover(isPresented: $showingIntro, onDismiss: { introSeen = true }) {
                IntroView()
            }
            .onAppear {
                if !introSeen { showingIntro = true }
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
    let onEdit: () -> Void
    let onStart: () -> Void
    /// 今日だけの時刻を決める (nil でいつもの時刻に戻す)
    let onOneDay: (Date?) -> Void
    let onPickTime: () -> Void

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
                    DonePraise(onAgain: onStart)
                } else {
                    timeMenu(oneDay: oneDay, now: context.date)
                }
            }
            .popCard(tint: done ? Pop.yellow : color)
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

/// 今日だけのやることを始めたあと、カードに出し続ける褒め言葉
private struct DonePraise: View {
    let onAgain: () -> Void
    @State private var bounce = false

    var body: some View {
        HStack(spacing: 10) {
            Text("🎉")
                .font(.system(size: 30))
                .scaleEffect(bounce ? 1.15 : 0.9)
                .rotationEffect(.degrees(bounce ? 10 : -10))
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: bounce)
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
        .onAppear { bounce = true }
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
