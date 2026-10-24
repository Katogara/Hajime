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
                    ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, task in
                        TaskCard(task: task, color: Pop.taskColor(index)) {
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
                    RoundIconButton(systemImage: "chart.bar.fill", label: "記録") { showingHistory = true }
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
                Text("ちょっとだけ、やってみよ。")
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
            Text("なかなか始められないこと、\nありますか？")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(Pop.ink)
            Text("決めた時刻に、最初の一歩だけを通知でお知らせします。「始める」を押せば、\(StartTask.firstMinutes)分のタイマーがスタート。")
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
                        Text(task.title)
                            .font(.system(.title3, design: .rounded, weight: .heavy))
                            .foregroundStyle(Pop.ink)
                        Text("👣 \(task.firstStep)")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(Pop.ink.opacity(0.75))
                        if let oneDay {
                            HStack(spacing: 6) {
                                PopChip(text: "今日は \(StartTask.timeText(oneDay)) から", color: Pop.orange)
                                Text("いつもは \(task.scheduleText)")
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
                // 日によって始めたい時刻が違うとき、メニューを開いて時刻を選ぶだけ (2 タップ) で今日だけ変える
                Menu {
                    Section("今日だけ、何時から？") {
                        ForEach(StartTask.oneDayChoices(now: context.date), id: \.self) { date in
                            Button(StartTask.timeText(date)) { onOneDay(date) }
                        }
                    }
                    Button("時刻を指定…", systemImage: "clock", action: onPickTime)
                    if oneDay != nil {
                        Button("いつもの時刻に戻す", systemImage: "arrow.uturn.backward") { onOneDay(nil) }
                    }
                } label: {
                    Label(oneDay == nil ? "今日は別の時間にする？" : "今日の時間を変える・戻す",
                          systemImage: "clock.arrow.circlepath")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(Pop.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Pop.orange.opacity(0.12)))
                }
            }
            .popCard(tint: color)
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
                Text("今日の「\(task.title)」は\n何時から？")
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
