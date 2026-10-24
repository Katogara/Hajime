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
                    TaskRow(task: task) { editing = task } onStart: { model.start(taskID: task.id) }
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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                Text(task.firstStep)
                    .font(.subheadline)
                Text(task.scheduleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
            // 通知を待たずに、自分で気づいたときも 1 タップで始められる
            Button("\(StartTask.firstMinutes)分", action: onStart)
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}
