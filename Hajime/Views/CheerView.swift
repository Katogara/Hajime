import SwiftUI

/// 始めたとき・続けたときに全画面で出す、大げさに褒める演出。紙吹雪が飛び、少しすると消える (タップでも消える)。
struct CheerView: View {
    let cheer: Cheer
    let onDone: () -> Void

    @State private var burst = false
    @State private var showingLevelUp = false
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
        case .graduated:
            return [("卒業おめでとう！", "もうあなたは、1人で何でもできます")]
        }
    }

    private var emoji: String { cheer.kind == .started ? "🎉" : "🔥" }
    private var background: Color { cheer.kind == .started ? Pop.orange : Pop.green }

    var body: some View {
        if cheer.kind == .graduated {
            GraduationView(onDone: onDone)
        } else {
            cheerBody
        }
    }

    private var cheerBody: some View {
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
                if cheer.gainedXP {
                    Text("+1 EXP")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(Pop.ink)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Pop.yellow))
                        .scaleEffect(burst ? 1 : 0.1)
                        .animation(.spring(response: 0.4, dampingFraction: 0.45).delay(0.6), value: burst)
                }
            }
            .padding(24)
            // レベルが上がったときは、続けてレベルアップを別の画面でしっかり褒める
            if let level = cheer.levelUp, showingLevelUp {
                LevelUpStage(level: level)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: advance)
        .sensoryFeedback(.success, trigger: burst)
        .onAppear { burst = true }
        .task {
            try? await Task.sleep(for: Self.duration)
            guard cheer.levelUp != nil else { return onDone() }
            advance()
            try? await Task.sleep(for: LevelUpStage.duration)
            onDone()
        }
    }

    /// 次へ進む。レベルアップがあればそれを見せ、なければ閉じる
    private func advance() {
        if cheer.levelUp != nil && !showingLevelUp {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { showingLevelUp = true }
        } else {
            onDone()
        }
    }
}

/// レベルアップの画面。始めたことに続けて、積み上げてきたことを大げさに褒める
private struct LevelUpStage: View {
    let level: Int
    @State private var appeared = false
    @State private var phrase = [
        "積み上げてきた証拠！\nほんとうにすごい！",
        "一歩ずつが、\nちゃんと力になってる！",
        "成長が止まらない！\nかっこいい！",
        "昨日の自分より、\n確実に強い！",
    ].randomElement()!

    static let duration: Duration = .seconds(3.6)

    var body: some View {
        ZStack {
            Pop.pink.ignoresSafeArea()
            ForEach(0..<4) { ring in
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 16)
                    .frame(width: 180, height: 180)
                    .scaleEffect(appeared ? 3 + Double(ring) * 0.5 : 0.2)
                    .opacity(appeared ? 0 : 1)
                    .animation(.easeOut(duration: 1.3).delay(Double(ring) * 0.12), value: appeared)
            }
            ConfettiBurst()
            VStack(spacing: 14) {
                Text("🌟")
                    .font(.system(size: 90))
                    .scaleEffect(appeared ? 1 : 0.1)
                    .rotationEffect(.degrees(appeared ? 0 : 180))
                    .animation(.spring(response: 0.5, dampingFraction: 0.4), value: appeared)
                Text("LEVEL UP!")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Pop.yellow)
                    .shadow(color: .black.opacity(0.2), radius: 0, y: 4)
                    .scaleEffect(appeared ? 1 : 2.4)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.5).delay(0.1), value: appeared)
                Text("Lv.\(level)")
                    .font(.system(size: 88, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 0, y: 6)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .animation(.spring(response: 0.5, dampingFraction: 0.35).delay(0.25), value: appeared)
                Text("「\(LevelTable.title(for: level))」になりました！")
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.5), value: appeared)
                Text(phrase)
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.7), value: appeared)
            }
            .padding(24)
        }
        .sensoryFeedback(.levelChange, trigger: appeared)
        .onAppear { appeared = true }
    }
}

/// レベル 100 の卒業式。紙吹雪が何度も上がり、送り出す。自動では閉じず、ボタンで出発する。
private struct GraduationView: View {
    let onDone: () -> Void
    @State private var appeared = false
    /// 紙吹雪を打ち上げ直すたびに増やす
    @State private var round = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [Pop.orange, Pop.pink, Pop.yellow], startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()
            ForEach(0..<6) { index in
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 14)
                    .frame(width: 160, height: 160)
                    .scaleEffect(appeared ? 3.5 : 0.3)
                    .opacity(appeared ? 0 : 1)
                    .animation(.easeOut(duration: 2).repeatForever(autoreverses: false)
                        .delay(Double(index) * 0.33), value: appeared)
            }
            // 1 回ごとに作り直して、紙吹雪を打ち上げ続ける
            ConfettiBurst()
                .id(round)
            ScrollView {
                VStack(spacing: 18) {
                    Text("🎓")
                        .font(.system(size: 130))
                        .scaleEffect(appeared ? 1 : 0.1)
                        .rotationEffect(.degrees(appeared ? 0 : 360))
                        .animation(.spring(response: 0.8, dampingFraction: 0.45), value: appeared)
                    Text("Lv.\(LevelTable.maxLevel)")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.15), radius: 0, y: 5)
                    Text("卒業おめでとう！")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.15), radius: 0, y: 4)
                    Text("もうあなたは、\n1人で何でもできます。")
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text("考える前に始められる力は、もうあなたのものです。\nこのアプリがなくても、きっと大丈夫。")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.9))
                    Button("いってきます！", action: onDone)
                        .buttonStyle(PopButtonStyle(color: .white, shade: Pop.orangeDeep, foreground: Pop.orange,
                                                    depth: 6))
                        .padding(.top, 12)
                }
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.6), value: appeared)
                .padding(28)
                .padding(.top, 40)
            }
        }
        .sensoryFeedback(.success, trigger: round)
        .onAppear { appeared = true }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.8))
                round += 1
            }
        }
    }
}

/// 表示されたらすぐ 1 回打ち上がる紙吹雪
private struct ConfettiBurst: View {
    @State private var burst = false

    var body: some View {
        Confetti(burst: burst)
            .onAppear { burst = true }
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
