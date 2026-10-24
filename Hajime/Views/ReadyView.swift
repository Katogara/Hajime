import SwiftUI

/// 通知本体をタップして開いたときの画面。最初の一歩だけを見せ、「はじめる！」1 つで始める。
struct ReadyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: ReadyPrompt
    @State private var bounce = false

    var body: some View {
        if let task = model.task(id: prompt.taskID) {
            let plan = task.plan(for: prompt.kind)
            VStack(spacing: 20) {
                LevelBadge(progress: model.level)
                Spacer()
                Text("👟")
                    .font(.system(size: 72))
                    .scaleEffect(bounce ? 1.08 : 0.94)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: bounce)
                    .onAppear { bounce = true }
                Text(task.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Pop.orange)
                VStack(spacing: 8) {
                    Text("まずは")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Pop.ink.opacity(0.6))
                    Text(plan.step)
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .foregroundStyle(Pop.ink)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .popCard(tint: Pop.orange)
                Text("\(plan.minutes)分でやめていい。終わらせなくていい。")
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
