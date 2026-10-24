import SwiftUI

/// 初回起動時と、一覧のタイトルをタップしたときに見せる 3 ページの説明 (目的・使い方・この先)。
struct IntroView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("スキップ") { dismiss() }
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Pop.ink.opacity(0.5))
                    .opacity(page < lastPage ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            TabView(selection: $page) {
                purpose.tag(0)
                usage.tag(1)
                future.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageDots(count: lastPage + 1, current: page)
                .padding(.bottom, 16)

            Button {
                if page < lastPage {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page < lastPage ? "次へ" : "始めてみる！")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(PopButtonStyle(depth: 6))
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .popBackground()
    }

    // MARK: - ページ

    private var purpose: some View {
        IntroPage(emoji: "😮‍💨", color: Pop.orange, title: "始める直前が、いちばんつらい") {
            PhraseText("やらなきゃと思うほど、なかなか始められない。でも始めてしまえば、意外とすんなり進む。")
            PhraseText("このアプリはあなたの「はじめる」を応援します！")
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(Pop.orange)
            PhraseText("手伝うのは「始めること」だけ。やることの管理はしませんし、終わらせなくていいアプリです。")
        }
    }

    private var usage: some View {
        IntroPage(emoji: "👆", color: Pop.yellow, title: "使い方") {
            IntroStep(number: 1, text: "やることと、すぐ終わる「最初の一歩」を登録する（例：筋トレなら「ウェアに着替える」）")
            IntroStep(number: 2, text: "決めた時刻に通知が届いたら、長押しして「始める」。まずはたっぷり褒めます")
            IntroStep(number: 3, text: "一歩をやったら「やりました！」。やらなかったら「やっぱりやめます」")
            PhraseText("続きに夢中で押し忘れても大丈夫。\(StartTask.firstMinutes)分たったら、代わりに「やりました！」を押しておきます。")
                .font(.system(.subheadline, design: .rounded))
            PhraseText("始められなかったら、\(Int(ReminderSchedule.nudgeDelay / 60))分後にもっと小さな一歩で、もう一度だけ知らせます。")
                .font(.system(.subheadline, design: .rounded))
            PhraseText("日によって始めたい時刻が違うときは、一覧の「今日は別の時間にする？」から時刻を選べます。")
                .font(.system(.subheadline, design: .rounded))
        }
    }

    private var future: some View {
        IntroPage(emoji: "🏃", color: Pop.green, title: "考える前に、もう始めている") {
            PhraseText("迷っている時間とストレスが減り、通知から始めるまでの時間が少しずつ短くなっていきます。")
            PhraseText("始めるたびに経験値 +1（同じやることは1日1回まで）。レベル\(LevelTable.maxLevel)になったら卒業です。そのころには、もうアプリがなくても始められるはず。")
            PhraseText("記録に残るのは、始めた回数と始めるまでの時間だけ。やらなかった日を責めることはありません。")
        }
    }
}

private struct IntroPage<Content: View>: View {
    let emoji: String
    let color: Color
    let title: String
    @ViewBuilder let content: Content
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(emoji)
                    .font(.system(size: 76))
                    .frame(width: 150, height: 150)
                    .background(Circle().fill(color.opacity(0.25)))
                    .scaleEffect(appeared ? 1 : 0.6)
                    .rotationEffect(.degrees(appeared ? 0 : -12))
                    .animation(.spring(response: 0.5, dampingFraction: 0.45), value: appeared)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                PhraseText(title)
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .foregroundStyle(Pop.ink)
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Pop.ink.opacity(0.75))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}

private struct IntroStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Pop.orange))
            PhraseText(text)
                .foregroundStyle(Pop.ink)
        }
    }
}

/// ページの位置。今のページだけ横に伸びたオレンジの丸
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Pop.orange : Pop.orange.opacity(0.25))
                    .frame(width: index == current ? 26 : 10, height: 10)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: current)
    }
}
