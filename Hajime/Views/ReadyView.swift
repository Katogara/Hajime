import SwiftUI

/// 通知本体をタップして開いたときの画面。最初の一歩だけを見せ、「はじめる！」1 つで始める。
struct ReadyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: ReadyPrompt

    var body: some View {
        if let task = model.task(id: prompt.taskID) {
            let plan = task.plan(for: prompt.kind)
            VStack(spacing: 20) {
                LevelBadge(progress: model.level)
                Spacer()
                // 揺れは時刻から計算する (repeatForever は位置の変化まで巻き込んで揺れるため)
                TimelineView(.animation) { context in
                    Text("👟")
                        .font(.system(size: 72))
                        .scaleEffect(1.01 + 0.07 * sin(context.date.timeIntervalSinceReferenceDate * 4))
                }
                PhraseText(task.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Pop.orange)
                VStack(spacing: 8) {
                    Text("まずは")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Pop.ink.opacity(0.6))
                    PhraseText(plan.step)
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .foregroundStyle(Pop.ink)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .popCard(tint: Pop.orange)
                PhraseText("まずは一歩だけ。終わらせなくていい。")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Pop.ink.opacity(0.65))
                Spacer()
                Button {
                    model.start(taskID: task.id, kind: prompt.kind, promptDate: prompt.promptDate)
                } label: {
                    Text("はじめる！")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(PopButtonStyle(depth: 6))
                Button("あとで") { dismiss() }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Pop.ink.opacity(0.5))
            }
            .padding(24)
            .popBackground()
        }
    }
}
