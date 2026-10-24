import SwiftUI

/// 始めてからの画面。完了ではなく「始めたこと」を成功とし、時間がたったら続けるかやめるかを選ぶだけ。
struct TimerView: View {
    @Environment(AppModel.self) private var model
    let session: TimerSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(spacing: 28) {
                Spacer()
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(session.step)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                if session.continued {
                    continuing(now: now)
                } else if now < session.endsAt {
                    counting(now: now)
                } else {
                    finished
                }
                Spacer()
            }
            .padding(24)
        }
    }

    private func counting(now: Date) -> some View {
        let total = TimeInterval(session.minutes * 60)
        let remaining = max(0, session.endsAt.timeIntervalSince(now))
        return VStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: 1 - remaining / total)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                Text(Self.clock(remaining))
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 240, height: 240)
            Text("終わらせなくていい。始めるだけ。")
                .foregroundStyle(.secondary)
            // 途中でやめても「始めた」記録は残る
            Button("やめる") { model.finish() }
                .buttonStyle(.bordered)
        }
    }

    private var finished: some View {
        VStack(spacing: 20) {
            Text("始められました")
                .font(.title2.bold())
            Text("続けても、ここでやめても大丈夫。")
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button { model.finish() } label: {
                    Text("ここまで").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                Button { model.continueSession() } label: {
                    Text("続ける").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func continuing(now: Date) -> some View {
        VStack(spacing: 20) {
            Text("続けています")
                .foregroundStyle(.secondary)
            Text(Self.clock(now.timeIntervalSince(session.startedAt)))
                .font(.system(size: 56, weight: .light, design: .rounded))
                .monospacedDigit()
            Button { model.finish() } label: {
                Text("おわる").frame(minWidth: 120, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// 「4:59」「1:02:03」のような表示
    nonisolated static func clock(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded(.up))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
