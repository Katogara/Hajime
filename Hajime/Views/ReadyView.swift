import SwiftUI

/// 通知本体をタップして開いたときの画面。最初の一歩だけを見せ、「スタート」1 つで始める。
struct ReadyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: ReadyPrompt

    var body: some View {
        if let task = model.task(id: prompt.taskID) {
            let plan = task.plan(for: prompt.kind)
            VStack(spacing: 24) {
                Spacer()
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(plan.step)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("\(plan.minutes)分でやめていい。終わらせなくていい。")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.start(taskID: task.id, kind: prompt.kind, promptDate: prompt.promptDate)
                } label: {
                    Text("スタート")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                Button("あとで") { dismiss() }
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
