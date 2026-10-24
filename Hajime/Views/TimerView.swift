import SwiftUI

/// 始めてからの画面。完了ではなく「始めたこと」を成功とし、時間がたったら続けるかやめるかを選ぶだけ。
struct TimerView: View {
    @Environment(AppModel.self) private var model
    let session: TimerSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(spacing: 24) {
                Spacer()
                Text(session.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Pop.orange)
                Text(session.step)
                    .font(.system(.title, design: .rounded, weight: .black))
                    .foregroundStyle(Pop.ink)
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
            .frame(maxWidth: .infinity)
            .popBackground()
        }
    }

    private func counting(now: Date) -> some View {
        let total = TimeInterval(session.minutes * 60)
        let remaining = max(0, session.endsAt.timeIntervalSince(now))
        return VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Pop.card)
                Circle()
                    .stroke(Pop.orange.opacity(0.15), lineWidth: 20)
                Circle()
                    .trim(from: 0, to: 1 - remaining / total)
                    .stroke(Pop.orange, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                VStack(spacing: 2) {
                    Text(Self.clock(remaining))
                        .font(.system(size: 60, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Pop.ink)
                    Text("のこり")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Pop.ink.opacity(0.5))
                }
            }
            .frame(width: 250, height: 250)
            Text("終わらせなくていい。始めるだけ。")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Pop.ink.opacity(0.65))
            // 途中でやめても「始めた」記録は残る
            Button("やめる") { model.finish() }
                .buttonStyle(PopButtonStyle.plain)
        }
    }

    /// 時間がたったところ。「ここまで」を選ぶ人もいるので、ここでは褒めない
    private var finished: some View {
        VStack(spacing: 18) {
            Text("⏰")
                .font(.system(size: 56))
            Text("\(session.minutes)分たちました")
                .font(.system(size: 32, weight: .black, design: .rounded))
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
        VStack(spacing: 18) {
            Text("🔥 続けています")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(Pop.orange)
            Text(Self.clock(now.timeIntervalSince(session.startedAt)))
                .font(.system(size: 60, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Pop.ink)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .popCard(tint: Pop.orange)
                .fixedSize()
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

