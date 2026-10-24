import SwiftUI

/// 「はじめる」を押したあとの画面。主役は時間ではなく「最初の一歩」。
/// 選ぶのは「最初の一歩やりました！続きをやります」か「やっぱりやめます」の 2 つだけ。
/// 時間 (5 分) は、続きに夢中になっているかもしれない人のために、1 つ目を代わりに押しておく補助。
struct TimerView: View {
    @Environment(AppModel.self) private var model
    let session: TimerSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            ScrollView {
                VStack(spacing: 18) {
                    LevelBadge(progress: model.level)
                    ConceptBanner()
                    Text(session.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Pop.ink.opacity(0.55))
                        .padding(.top, 4)
                    WaitingStep(step: session.step, beckoning: !session.continued)
                    if session.continued {
                        continuing(now: now)
                    } else {
                        choosing(now: now)
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity)
            .popBackground()
        }
        // 時間がたったら「続きをやります」を押しておく
        .task(id: session.recordID) {
            let wait = session.endsAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { model.autoContinueIfDue() }
        }
    }

    /// 一歩をやったか、やっぱりやめるか
    private func choosing(now: Date) -> some View {
        let remaining = max(0, session.endsAt.timeIntervalSince(now))
        return VStack(spacing: 14) {
            Button { model.continueSession() } label: {
                VStack(spacing: 2) {
                    Text("最初の一歩やりました！")
                        .font(.system(.title3, design: .rounded, weight: .black))
                    Text("続きをやります")
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(PopButtonStyle(color: Pop.green, shade: Pop.greenDeep, depth: 6))
            // 一歩もやらなかったとき。始めた記録は残し、経験値はそっと取り消す
            Button { model.quit() } label: {
                Text("やっぱりやめます").frame(maxWidth: .infinity)
            }
            .buttonStyle(PopButtonStyle.plain)
            Text("⏰ \(session.minutes)分たったら、1つ目のボタンを押しておきますね（のこり \(Self.clock(remaining))）")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(Pop.ink.opacity(0.55))
        }
        .padding(.top, 6)
    }

    private func continuing(now: Date) -> some View {
        VStack(spacing: 14) {
            if session.autoContinued == true {
                Text("\(session.minutes)分たったので、「続きをやります」にしておきました")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Pop.ink.opacity(0.55))
            }
            Text("🔥 続きをやっています  \(Self.clock(now.timeIntervalSince(session.startedAt)))")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Pop.orange)
            Button { model.finish() } label: {
                Text("おわる").frame(minWidth: 140)
            }
            .buttonStyle(PopButtonStyle())
        }
        .padding(.top, 6)
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

/// アプリの考え方。管理アプリではなく「はじめる」を応援するアプリだと、始めた画面ではっきり伝える
struct ConceptBanner: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("📣 このアプリはあなたの\n「はじめる」を応援します！")
                .font(.system(.title3, design: .rounded, weight: .black))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("やることの管理はしません。終わらせなくていい。\n始めたあなたを、ただ応援します。")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Pop.orange))
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Pop.orangeDeep).offset(y: 5))
        .padding(.bottom, 5)
    }
}
