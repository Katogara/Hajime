import SwiftUI

/// やることの登録・編集。文字を入力するのはここ (初回の登録) だけ。
struct TaskEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var task: StartTask
    let isNew: Bool
    /// 新しく登録したとき、保存の前に一度だけ「もっと小さくできる？」と聞く (「次から聞かない」で止められる)
    @AppStorage("askSmallerStep") private var askSmallerStep = true
    @State private var askingSmaller = false
    @State private var closeAfterAsking = false
    /// 一歩のコツ。初めて登録するときは登録シートの最初に出し、一歩の欄の「一歩のコツ」から何度でも見られる
    @AppStorage(TaskEditView.tipsSeenKey) private var tipsSeen = false
    @State private var showingTips: Bool
    /// この登録で一歩のコツを見た (保存時のシートの前置きを省く)
    @State private var sawTips = false
    /// 一歩のコツの型で一歩を入れた (同じ型を保存時にもう一度見せない)
    @State private var usedTipsTemplate = false
    @State private var splitting = false
    /// 一歩を、別の時刻にできる新しいやることにするときの下書き
    @State private var otherTask: StartTask?
    /// 分けるシートを閉じてから、新しいやることの登録を開く
    @State private var pendingOtherTask: StartTask?

    static let tipsSeenKey = "stepTipsSeen"

    init(task: StartTask, isNew: Bool) {
        _task = State(initialValue: task)
        self.isNew = isNew
        _showingTips = State(initialValue: isNew && !UserDefaults.standard.bool(forKey: Self.tipsSeenKey))
    }

    private var canSave: Bool {
        !task.title.trimmingCharacters(in: .whitespaces).isEmpty
            // 分けた一歩を消したときは、分ける前の一歩に戻して保存する
            && (!task.firstStep.trimmingCharacters(in: .whitespaces).isEmpty || task.isSplit)
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
                        if let step {
                            task.firstStep = step
                            usedTipsTemplate = true
                        }
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
                        Button("保存", action: save)
                            .disabled(!canSave)
                    }
                }
            }
            .sheet(isPresented: $askingSmaller, onDismiss: {
                // シートを閉じてから保存して戻る (シートを出したまま親を閉じない)
                guard closeAfterAsking else { return }
                model.save(task)
                dismiss()
            }) {
                SmallerStepSheet(step: task.firstStep, short: sawTips) { newStep in
                    if let newStep { task.firstStep = newStep }
                    closeAfterAsking = true
                    askingSmaller = false
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $splitting, onDismiss: {
                otherTask = pendingOtherTask
                pendingOtherTask = nil
            }) {
                StepSplitSheet(step: task.firstStep) { step in
                    task.split(into: step)
                    splitting = false
                } onOtherTask: {
                    pendingOtherTask = task.draftFromStep()
                    splitting = false
                } onKeep: {
                    splitting = false
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $otherTask) { draft in
                TaskEditView(task: draft, isNew: true)
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
                TextField("例: 浴室のドアを開ける", text: $task.firstStep)
                if let next = task.nextStep, task.isSplit {
                    HStack {
                        PhraseText("次：\(next)")
                            .foregroundStyle(Pop.ink.opacity(0.7))
                        Spacer()
                        Button("分けるのをやめる") { task.unsplit() }
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                    }
                } else if !isNew && !task.firstStep.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("この一歩を分ける") { splitting = true }
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
                if task.isSplit {
                    PhraseText("通知には最初の一歩だけが出ます。分ける前の一歩は「次」として残り、「やりました！」のあとに出ます。")
                } else {
                    PhraseText("からだを1回動かすだけで終わる行動にします。通知にはこの一歩だけが出ます。")
                }
            }
            Section(task.isOneDay ? "今日、何時に促す？" : "促す時刻") {
                DatePicker("時刻", selection: time, displayedComponents: .hourAndMinute)
                if !task.isOneDay {
                    WeekdayPicker(weekdays: $task.weekdays)
                }
            }
            Section {
                TextField("例: 立ち上がる", text: $task.smallerStep)
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
        sawTips = true
        withAnimation { showingTips = false }
    }

    private func save() {
        if isNew && askSmallerStep && !usedTipsTemplate {
            askingSmaller = true
        } else {
            model.save(task)
            dismiss()
        }
    }
}

/// 新しく登録した一歩を、ワンのすけが一度だけ「もっと小さくできる？」と聞くシート。
/// 一歩の中身は判定しない (どの一歩にも同じ型を出す)。今の一歩を認めてから聞き、「このままでOK」も同じ大きさで並べる
private struct SmallerStepSheet: View {
    let step: String
    /// 一歩のコツを見た直後なので、前置きを省いて聞く
    var short = false
    /// 選んだ一歩 (nil ならそのまま)
    let onChoose: (String?) -> Void
    @AppStorage("askSmallerStep") private var askSmallerStep = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WanAsks(pose: .nod, line: short ? "最初に、からだをどう動かす？"
                    : "いい一歩、ワンダフル！ もっと小さくすると、もっと始めやすくなるかも。最初に、からだをどう動かす？")
                Text("いまの一歩: \(step)")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Pop.ink.opacity(0.6))

                StepTemplates { onChoose($0) }
                StepChoiceButton(title: "このままでOK", style: .plain) { onChoose(nil) }

                Toggle("次から聞かない", isOn: Binding(get: { !askSmallerStep }, set: { askSmallerStep = !$0 }))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Pop.ink.opacity(0.7))
            }
            .padding(20)
        }
        .popBackground()
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
