import SwiftUI

/// 始めてからの画面。主役は時間ではなく「最初の一歩」。時間は下に小さく出す。
/// 完了ではなく「始めたこと」を成功とし、時間がたったら続けるかやめるかを選ぶだけ。
struct TimerView: View {
    @Environment(AppModel.self) private var model
    let session: TimerSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let counting = !session.continued && now < session.endsAt
            VStack(spacing: 20) {
                LevelBadge(progress: model.level)
                Spacer(minLength: 0)
                Text(session.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Pop.ink.opacity(0.55))
                WaitingStep(step: session.step, beckoning: counting)
                Spacer(minLength: 0)
                if session.continued {
                    continuing(now: now)
                } else if counting {
                    countingFooter(now: now)
                } else {
                    finished
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .popBackground()
        }
    }

    /// 時間は脇役。細いバーと小さな数字だけ
    private func countingFooter(now: Date) -> some View {
        let total = TimeInterval(session.minutes * 60)
        let remaining = max(0, session.endsAt.timeIntervalSince(now))
        return VStack(spacing: 14) {
            HStack(spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Pop.orange.opacity(0.15))
                        Capsule().fill(Pop.orange)
                            .frame(width: max(8, proxy.size.width * (1 - remaining / total)))
                            .animation(.linear(duration: 1), value: remaining)
                    }
                }
                .frame(height: 8)
                Text("のこり \(Self.clock(remaining))")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Pop.ink.opacity(0.55))
            }
            Text("終わらせなくていい。始めるだけ。")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Pop.ink.opacity(0.65))
            // 途中でやめても「始めた」記録は残る (経験値はそっと取り消す)
            Button("やめる") { model.quit() }
                .buttonStyle(PopButtonStyle.plain)
        }
    }

    /// 時間がたったところ。「ここまで」を選ぶ人もいるので、ここでは褒めない
    private var finished: some View {
        VStack(spacing: 14) {
            Text("⏰ \(session.minutes)分たちました")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(Pop.ink)
            Text("続けても、ここでやめても大丈夫。")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Pop.ink.opacity(0.65))
            HStack(spacing: 14) {
                Button { model.finish() } label: {
                    Text("ここまで").frame(maxWidth: .infinity)
                }
                .buttonStyle(PopButtonStyle.plain)
                Button { model.continueSession() } label: {
                    Text("続ける").frame(maxWidth: .infinity)
                }
                .buttonStyle(PopButtonStyle(color: Pop.green, shade: Pop.greenDeep))
            }
        }
    }

    private func continuing(now: Date) -> some View {
        VStack(spacing: 14) {
            Text("🔥 続けています  \(Self.clock(now.timeIntervalSince(session.startedAt)))")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Pop.orange)
            Button { model.finish() } label: {
                Text("おわる").frame(minWidth: 120)
            }
            .buttonStyle(PopButtonStyle())
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
