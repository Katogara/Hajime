import SwiftUI

/// やることの登録・編集。文字を入力するのはここ (初回の登録) だけ。
struct TaskEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var task: StartTask
    let isNew: Bool

    init(task: StartTask, isNew: Bool) {
        _task = State(initialValue: task)
        self.isNew = isNew
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
                        Text("今日だけのやることは、始めたあともキラキラのカードで残り、明日になると消えます。")
                    }
                }
                Section("やること") {
                    TextField("例: 筋トレ", text: $task.title)
                }
                Section {
                    TextField("例: ウェアに着替える", text: $task.firstStep)
                } header: {
                    Text("最初の一歩")
                } footer: {
                    Text("失敗しようのない、すぐ終わる行動にします。通知にはこの一歩だけが出ます。")
                }
                Section(task.isOneDay ? "今日、何時に促す？" : "促す時刻") {
                    DatePicker("時刻", selection: time, displayedComponents: .hourAndMinute)
                    if !task.isOneDay {
                        WeekdayPicker(weekdays: $task.weekdays)
                    }
                }
                Section {
                    TextField("例: 靴下を履く", text: $task.smallerStep)
                } header: {
                    Text("さらに小さい一歩（任意）")
                } footer: {
                    Text("通知から15分たっても始めていないとき、一度だけこの一歩で促します（\(StartTask.nudgeMinutes)分）。空なら最初の一歩で促します。")
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
            .popBackground()
            .navigationTitle(isNew ? "やることを追加" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        model.save(task)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
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
