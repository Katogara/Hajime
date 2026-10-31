import SwiftUI

/// 設定。分身の姿と、褒める演出の強さを選ぶ (一覧の右上の歯車から開く)
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("cheerStyle") private var cheerStyleRaw = ""
    @State private var choosingAvatar = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { choosingAvatar = true } label: {
                        HStack(spacing: 14) {
                            Group {
                                if let avatar = model.avatar {
                                    AvatarImage(figure: avatar, pose: .smile)
                                } else {
                                    WanImage(pose: .wave)
                                }
                            }
                            .frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.avatar == nil ? "姿を選ぶ" : "姿を選び直す")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundStyle(Pop.ink)
                                PhraseText("何度でも、無料で変えられます")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Pop.ink.opacity(0.6))
                            }
                        }
                    }
                    NavigationLink {
                        ClosetView()
                    } label: {
                        Text("きせかえ")
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(Pop.ink)
                    }
                } header: {
                    Text("分身の姿")
                }

                Section {
                    Picker("演出の強さ", selection: Binding(
                        get: { CheerStyle.resolve(cheerStyleRaw, reduceMotion: reduceMotion) },
                        set: { cheerStyleRaw = $0.rawValue })) {
                        ForEach(CheerStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("褒める演出")
                } footer: {
                    PhraseText("控えめにすると、全画面ではなく、画面の下でワンのすけが褒めます。どれも画面をタップすると閉じます。")
                }

                Section {
                    Toggle("すべての服を着られるようにする", isOn: Binding(
                        get: { model.devWearAll }, set: { model.setDevWearAll($0) }))
                    NavigationLink("予約中の通知") { PendingPromptsView() }
                } header: {
                    Text("開発中の確かめ用")
                } footer: {
                    PhraseText("服を買えるようになるまでと、通知を確かめるためのものです。公開する前に外します。")
                }
            }
            .scrollContentBackground(.hidden)
            .popBackground()
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $choosingAvatar) {
                AvatarChoiceView(first: false)
            }
        }
    }
}

/// 予約中の促す通知の一覧 (開発中の確かめ用)。iOS が持っている予約を、そのまま早い順に出す
private struct PendingPromptsView: View {
    @Environment(AppModel.self) private var model
    @State private var prompts: [(date: Date, kind: Prompt.Kind, title: String)] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && prompts.isEmpty {
                Text("予約中の通知はありません")
            }
            ForEach(Array(prompts.enumerated()), id: \.offset) { _, prompt in
                HStack {
                    Text(prompt.date.formatted(.dateTime.month().day().weekday().hour().minute()))
                        .monospacedDigit()
                    Text(prompt.kind == .first ? "最初" : "再通知")
                        .foregroundStyle(prompt.kind == .first ? Pop.ink : Pop.orange)
                    Spacer()
                    Text(prompt.title)
                        .lineLimit(1)
                        .foregroundStyle(Pop.ink.opacity(0.6))
                }
                .font(.system(.subheadline, design: .rounded))
            }
        }
        .navigationTitle("予約中の通知")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        prompts = await model.pendingPrompts()
        loaded = true
    }
}
