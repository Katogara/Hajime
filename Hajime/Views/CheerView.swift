import SwiftUI

/// 始めたとき・続けたときに全画面で出す、大げさに褒める演出。紙吹雪が飛び、少しすると消える (タップでも消える)。
struct CheerView: View {
    let cheer: Cheer
    let onDone: () -> Void

    @State private var burst = false
    @State private var phrase: (title: String, sub: String)

    /// 表示しておく時間
    static let duration: Duration = .seconds(2.8)

    init(cheer: Cheer, onDone: @escaping () -> Void) {
        self.cheer = cheer
        self.onDone = onDone
        _phrase = State(initialValue: Self.phrases(for: cheer.kind).randomElement()!)
    }

    static func phrases(for kind: Cheer.Kind) -> [(title: String, sub: String)] {
        switch kind {
        case .started:
            return [
                ("はじめた！\n天才！", "いちばん難しいところを、もう越えました"),
                ("すごい！\n始められた！", "これができる人は、ほんとうに強い"),
                ("えらすぎる！", "腰が重いのに動いた。最高です"),
                ("最高の\nスタート！", "始めた時点で、今日はもう勝ち"),
            ]
        case .continued:
            return [
                ("続ける！？\nすごすぎる！", "その勢い、本物です"),
                ("止まらない！\n最高！", "完全にノってます"),
                ("まだやるの！？\nかっこいい！", "始めた自分に感謝しよう"),
            ]
        }
    }

    private var emoji: String { cheer.kind == .started ? "🎉" : "🔥" }
    private var background: Color { cheer.kind == .started ? Pop.orange : Pop.green }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            // 中心から広がる光の輪
            ForEach(0..<3) { ring in
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 18)
                    .scaleEffect(burst ? 2.6 + Double(ring) * 0.6 : 0.2)
                    .opacity(burst ? 0 : 1)
                    .animation(.easeOut(duration: 1.2).delay(Double(ring) * 0.15), value: burst)
                    .frame(width: 200, height: 200)
            }
            Confetti(burst: burst)
            VStack(spacing: 18) {
                Text(emoji)
                    .font(.system(size: 110))
                    .scaleEffect(burst ? 1 : 0.2)
                    .rotationEffect(.degrees(burst ? 0 : -30))
                    .animation(.spring(response: 0.45, dampingFraction: 0.4), value: burst)
                Text(phrase.title)
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 0, y: 4)
                    .scaleEffect(burst ? 1 : 0.5)
                    .opacity(burst ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.1), value: burst)
                Text(phrase.sub)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .opacity(burst ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.4), value: burst)
            }
            .padding(24)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .sensoryFeedback(.success, trigger: burst)
        .onAppear { burst = true }
        .task {
            try? await Task.sleep(for: Self.duration)
            onDone()
        }
    }
}

/// 中心から四方へ飛び散って落ちる紙吹雪
private struct Confetti: View {
    let burst: Bool

    private struct Piece {
        var angle: Double
        var distance: CGFloat
        var spin: Double
        var size: CGFloat
        var color: Color
        var emoji: String?
        var delay: Double
    }

    @State private var pieces: [Piece] = (0..<56).map { index in
        let colors: [Color] = [.white, Pop.yellow, Pop.pink, Pop.green, Pop.orangeDeep]
        let emojis = ["✨", "⭐️", "💥", "🎊"]
        return Piece(angle: Double.random(in: 0..<(2 * .pi)),
                     distance: CGFloat.random(in: 140...420),
                     spin: Double.random(in: -540...540),
                     size: CGFloat.random(in: 8...16),
                     color: colors[index % colors.count],
                     emoji: index % 7 == 0 ? emojis.randomElement() : nil,
                     delay: Double.random(in: 0...0.15))
    }

    var body: some View {
        ZStack {
            ForEach(pieces.indices, id: \.self) { index in
                let piece = pieces[index]
                Group {
                    if let emoji = piece.emoji {
                        Text(emoji).font(.system(size: piece.size * 2.2))
                    } else {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(piece.color)
                            .frame(width: piece.size, height: piece.size * 1.6)
                    }
                }
                .rotationEffect(.degrees(burst ? piece.spin : 0))
                // 飛び散ったあと、少し下へ落ちる
                .offset(x: burst ? cos(piece.angle) * piece.distance : 0,
                        y: burst ? sin(piece.angle) * piece.distance + 120 : 0)
                .opacity(burst ? 0.9 : 0)
                .animation(.timingCurve(0.1, 0.8, 0.3, 1, duration: 1.6).delay(piece.delay), value: burst)
            }
        }
        .allowsHitTesting(false)
    }
}
