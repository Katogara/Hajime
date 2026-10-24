import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // タイマーが動いている間は、画面全体をタイマーにする (アプリを開き直しても戻る)
        if let session = model.session {
            TimerView(session: session)
        } else {
            TaskListView()
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
            List {
                if model.tasks.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("始められないことを登録しましょう")
                                .font(.headline)
                            Text("決めた時刻に、最初の一歩だけを通知で促します。通知の「始める」を押せば、5分のタイマーが動き出します。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Button("やることを追加") { editing = .draft() }
                    }
                }
                ForEach(model.tasks) { task in
                    TaskRow(task: task) {
                        editing = task
                    } onStart: {
                        model.start(taskID: task.id)
                    } onOneDay: { date in
                        model.setOneDayTime(date, for: task.id)
                    } onPickTime: {
                        pickingTime = task
                    }
                }
                .onDelete { model.delete(at: $0) }
            }
            .navigationTitle("はじめる")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button { showingIntro = true } label: {
                        HStack(spacing: 4) {
                            Text("はじめる")
                                .font(.headline)
                            Image(systemName: "questionmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .accessibilityHint("アプリの説明を表示します")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingHistory = true } label: {
                        Label("記録", systemImage: "chart.bar")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = .draft() } label: {
                        Label("追加", systemImage: "plus")
                    }
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
}

private struct TaskRow: View {
    let task: StartTask
    let onEdit: () -> Void
    let onStart: () -> Void
    /// 今日だけの時刻を決める (nil でいつもの時刻に戻す)
    let onOneDay: (Date?) -> Void
    let onPickTime: () -> Void

    var body: some View {
        // 候補の時刻と「今日は」の表示が古くならないよう、1 分ごとに作り直す
        TimelineView(.everyMinute) { context in
            let oneDay = task.oneDayTime(on: context.date)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                    Text(task.firstStep)
                        .font(.subheadline)
                    if let oneDay {
                        Text("今日は \(StartTask.timeText(oneDay)) から")
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)
                        + Text("（いつもは \(task.scheduleText)）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(task.scheduleText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onEdit)
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
                    Image(systemName: "clock.arrow.circlepath")
                        .accessibilityLabel("今日の時刻を変える")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                // 通知を待たずに、自分で気づいたときも 1 タップで始められる
                Button("\(StartTask.firstMinutes)分", action: onStart)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
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
            DatePicker("時刻", selection: $time, in: now...max(now, endOfDay), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .navigationTitle("今日の\(task.title)は何時から")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("決定") {
                            onSave(time)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium])
        .onAppear {
            time = task.oneDayTime(on: now) ?? now.addingTimeInterval(30 * 60)
        }
    }
}
