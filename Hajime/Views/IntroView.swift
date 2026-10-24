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
                    .opacity(page < lastPage ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            TabView(selection: $page) {
                purpose.tag(0)
                usage.tag(1)
                future.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < lastPage {
                    withAnimation { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page < lastPage ? "次へ" : "始めてみる")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - ページ

    private var purpose: some View {
        IntroPage(symbol: "sunrise.fill", title: "始める直前が、\nいちばんつらい") {
            Text("やらなきゃと思うほど、なかなか始められない。でも始めてしまえば、意外とすんなり進む。")
            Text("このアプリが手伝うのは「始めること」だけです。終わらせることも、管理することもしません。")
        }
    }

    private var usage: some View {
        IntroPage(symbol: "hand.tap.fill", title: "使い方") {
            IntroStep(number: 1, text: "やることと、すぐ終わる「最初の一歩」を登録する\n（例：筋トレ →「ウェアに着替える」）")
            IntroStep(number: 2, text: "決めた時刻に通知が届いたら、長押しして「始める」。\(StartTask.firstMinutes)分のタイマーが動き出す")
            IntroStep(number: 3, text: "\(StartTask.firstMinutes)分たったら「続ける」か「ここまで」。どちらでも「始めた」ことになる")
            Text("始められなかったら、\(Int(ReminderSchedule.nudgeDelay / 60))分後にもっと小さな一歩で、もう一度だけ知らせます。")
                .font(.subheadline)
            Text("日によって始めたい時刻が違うときは、一覧の時計のボタンから「今日は何時から」を選べます。")
                .font(.subheadline)
        }
    }

    private var future: some View {
        IntroPage(symbol: "figure.walk", title: "考える前に、\nもう始めている") {
            Text("迷っている時間とストレスが減り、通知から始めるまでの時間が少しずつ短くなっていきます。")
            Text("記録に残るのは、始めた回数と始めるまでの時間だけ。やらなかった日を責めることはありません。")
        }
    }
}

private struct IntroPage<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                Text(title)
                    .font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 56)
        }
    }
}

private struct IntroStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .foregroundStyle(.primary)
        }
    }
}
