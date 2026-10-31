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
                        PhraseText("今日だけのやることは、始めたあともキラキラのカードで残り、明日になると消えます。")
                    }
                }
                Section("やること") {
                    TextField("例: お風呂", text: $task.title)
                }
                Section {
                    TextField("例: 浴室のドアを開ける", text: $task.firstStep)
                } header: {
                    Text("最初の一歩")
                } footer: {
                    PhraseText("からだを1回動かすだけで終わる行動にします。通知にはこの一歩だけが出ます。")
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
            .popBackground()
            .navigationTitle(isNew ? "やることを追加" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if isNew && askSmallerStep {
                            askingSmaller = true
                        } else {
                            model.save(task)
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $askingSmaller, onDismiss: {
                // シートを閉じてから保存して戻る (シートを出したまま親を閉じない)
                guard closeAfterAsking else { return }
                model.save(task)
                dismiss()
            }) {
                SmallerStepSheet(step: task.firstStep) { newStep in
                    if let newStep { task.firstStep = newStep }
                    closeAfterAsking = true
                    askingSmaller = false
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

/// 新しく登録した一歩を、ワンのすけが一度だけ「もっと小さくできる？」と聞くシート。
/// 一歩の中身は判定しない (どの一歩にも同じ型を出す)。今の一歩を認めてから聞き、「このままでOK」も同じ大きさで並べる
private struct SmallerStepSheet: View {
    let step: String
    /// 選んだ一歩 (nil ならそのまま)
    let onChoose: (String?) -> Void
    @AppStorage("askSmallerStep") private var askSmallerStep = true
    /// 「＿＿へ行く」「＿＿を手に持つ」を選んだときの型と、書き足す言葉
    @State private var template: Template?
    @State private var blank = ""
    @FocusState private var blankFocused: Bool

    enum Template: String {
        case go = "へ行く"
        case hold = "を手に持つ"

        var label: String { "＿＿\(rawValue)" }
        var prompt: String { self == .go ? "例: 洗面所" : "例: タオル" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    WanImage(pose: .nod, facing: .right)
                        .frame(width: 100, height: 100)
                    SpeechBubble(tail: .leading) {
                        PhraseText("いい一歩、ワンダフル！ もっと小さくすると、もっと始めやすくなるかも。最初に、からだをどう動かす？")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Pop.brown)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("いまの一歩: \(step)")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Pop.ink.opacity(0.6))

                choice("立ち上がる") { onChoose("立ち上がる") }
                ForEach([Template.go, .hold], id: \.self) { t in
                    if template == t {
                        HStack {
                            TextField(t.prompt, text: $blank)
                                .textFieldStyle(.roundedBorder)
                                .focused($blankFocused)
                                .submitLabel(.done)
                                .onSubmit(useBlank)
                            Text(t.rawValue)
                                .font(.system(.body, design: .rounded, weight: .bold))
                                .foregroundStyle(Pop.ink)
                            Button("決める", action: useBlank)
                                .buttonStyle(PopButtonStyle())
                                .disabled(blank.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        choice(t.label) {
                            template = t
                            blank = ""
                            blankFocused = true
                        }
                    }
                }
                choice("このままでOK", style: .plain) { onChoose(nil) }

                Toggle("次から聞かない", isOn: Binding(get: { !askSmallerStep }, set: { askSmallerStep = !$0 }))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Pop.ink.opacity(0.7))
            }
            .padding(20)
        }
        .popBackground()
    }

    private func choice(_ title: String, style: PopButtonStyle = PopButtonStyle(),
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(style)
    }

    private func useBlank() {
        let word = blank.trimmingCharacters(in: .whitespaces)
        guard let template, !word.isEmpty else { return }
        onChoose(word + template.rawValue)
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
