import SwiftUI

/// やることの登録・編集。文字を入力するのはここ (初回の登録) だけ。
struct TaskEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var task: StartTask
    let isNew: Bool
    /// 一歩のコツ。初めて登録するときは登録シートの最初に出し、一歩の欄の「一歩のコツ」から何度でも見られる
    @AppStorage(TaskEditView.tipsSeenKey) private var tipsSeen = false
    @State private var showingTips: Bool
    /// 一歩の欄の「その前は？」
    @State private var askingBefore = false
    @FocusState private var smallerFocused: Bool

    static let tipsSeenKey = "stepTipsSeen"

    init(task: StartTask, isNew: Bool) {
        _task = State(initialValue: task)
        self.isNew = isNew
        _showingTips = State(initialValue: isNew && !UserDefaults.standard.bool(forKey: Self.tipsSeenKey))
    }

    private var canSave: Bool {
        !task.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !task.firstStep.trimmingCharacters(in: .whitespaces).isEmpty
            && (task.isOneDay || !task.weekdays.isEmpty)
    }

    /// いつもやること / 今日だけやること
    private var oneDay: Binding<Bool> {
        Binding {
            task.isOneDay
        } set: { isOn in
            task.onlyOn = isOn ? Calendar.current.startOfDay(for: .now) : nil
            if !isOn && task.weekdays.isEmpty { task.weekdays = Set(1...7) }
        }
    }

    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: task.minuteOfDay / 60, minute: task.minuteOfDay % 60,
                                  second: 0, of: .now) ?? .now
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            task.minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if showingTips {
                    StepTipsView { step in
                        if let step { task.firstStep = step }
                        closeTips()
                    }
                    .navigationTitle("一歩のコツ")
                } else {
                    form
                        .navigationTitle(isNew ? "やることを追加" : "編集")
                }
            }
            .popBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if showingTips {
                        Button("とばす", action: closeTips)
                    } else {
                        Button("保存") {
                            model.save(task)
                            dismiss()
                        }
                        .disabled(!canSave)
                    }
                }
            }
            .sheet(isPresented: $askingBefore) {
                StepBeforeSheet(step: task.firstStep) { step in
                    task.firstStep = step
                    askingBefore = false
                } onKeep: {
                    askingBefore = false
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker("種類", selection: oneDay) {
                    Text("いつもやること").tag(false)
                    Text("今日だけやること").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            } footer: {
                if task.isOneDay {
                    PhraseText("今日だけのやることは、始めたあともキラキラのカードで残り、明日になると消えます。")
                }
            }
            Section("やること") {
                TextField("例: お風呂", text: $task.title)
            }
            Section {
                TextField("例: 起き上がる", text: $task.firstStep)
                // 一歩がやることの名前と同じときだけ、責めずに一言添える (直せば消える)
                if task.stepIsWholeTask {
                    PhraseText("それだと、やること全部かも。その前の動きは？")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Pop.ink.opacity(0.55))
                }
                if !task.firstStep.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("その前は？") { askingBefore = true }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
            } header: {
                HStack {
                    Text("最初の一歩")
                    Spacer()
                    Button {
                        showingTips = true
                    } label: {
                        Label("一歩のコツ", systemImage: "questionmark.circle.fill")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .textCase(nil)
                    }
                }
            } footer: {
                PhraseText("通知を見たとき、からだが最初にする動きは？ この一歩だけで終わってOK。")
            }
            Section(task.isOneDay ? "今日、何時に促す？" : "促す時刻") {
                DatePicker("時刻", selection: time, displayedComponents: .hourAndMinute)
                if !task.isOneDay {
                    WeekdayPicker(weekdays: $task.weekdays)
                }
            }
            Section {
                // 登録し直すときに、まだ決めていなければ一言だけ誘う (始めなかった直後には出さない)
                if !isNew && task.smallerStep.trimmingCharacters(in: .whitespaces).isEmpty && !smallerFocused {
                    Button { smallerFocused = true } label: {
                        HStack(spacing: 8) {
                            WanImage(pose: .nod, facing: .right)
                                .frame(width: 32, height: 32)
                            PhraseText("もっと小さい一歩も決めておく？")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        }
                    }
                }
                TextField("例: スマホを置く", text: $task.smallerStep)
                    .focused($smallerFocused)
            } header: {
                Text("さらに小さい一歩（任意）")
            } footer: {
                PhraseText("通知から15分たっても始めていないとき、一度だけこの一歩で促します（\(StartTask.nudgeMinutes)分）。空なら最初の一歩で促します。")
            }
            if !isNew {
                Section {
                    Button("削除", role: .destructive) {
                        model.delete(task)
                        dismiss()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func closeTips() {
        tipsSeen = true
        withAnimation { showingTips = false }
    }
}

private struct WeekdayPicker: View {
    @Binding var weekdays: Set<Int>

    var body: some View {
        HStack {
            ForEach(1...7, id: \.self) { day in
                let isOn = weekdays.contains(day)
                Button {
                    if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(StartTask.weekdaySymbols[day - 1])
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .frame(width: 36, height: 36)
                        .background(isOn ? Pop.orange : Pop.orange.opacity(0.12), in: Circle())
                        .foregroundStyle(isOn ? Color.white : Pop.ink)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
