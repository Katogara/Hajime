import SwiftUI

// ワンのすけとアバターの絵。今は Gemini の画像を切り抜いた仮素材 (Hajime/Placeholder の PNG) で、
// 製品ではベクターでなぞったものを Assets.xcassets に入れて差し替える。
// 画像の名前は Avatar.swift の WanPose と AvatarBody にまとめている。

/// 名前から絵を読む。仮素材はアセットカタログではなくバンドルの PNG なので UIImage で読む
private func characterImage(_ name: String) -> Image {
    Image(uiImage: UIImage(named: name) ?? UIImage())
}

/// ワンのすけ
struct WanImage: View {
    let pose: WanPose

    var body: some View {
        characterImage(pose.imageName)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("ワンのすけ")
    }
}

/// ユーザーの分身のアバター
struct AvatarImage: View {
    let figure: AvatarBody
    let pose: AvatarPose

    var body: some View {
        characterImage(figure.imageName(pose))
            .resizable()
            .scaledToFit()
            .accessibilityLabel("あなたの分身")
    }
}

/// 褒める画面の主役。アバターが真ん中で大喜びし、ワンのすけが右下で一緒に喜ぶ。
/// アバターをまだ選んでいなければ、ワンのすけだけで褒める
struct CheerStage: View {
    let avatar: AvatarBody?
    let wanPose: WanPose
    /// 出てくるときの動き
    let appeared: Bool
    /// アバターの絵の大きさ (正方形)。ワンのすけはその 0.7 倍
    var size: CGFloat = 220

    var body: some View {
        ZStack {
            if let avatar {
                AvatarImage(figure: avatar, pose: .joy)
                    .frame(width: size, height: size)
                    .hopping(height: 14, period: 0.9)
                    .offset(x: -size * 0.12)
                // 足元の高さをアバターにそろえ、少し右に寄せて並べる
                WanImage(pose: wanPose)
                    .frame(width: size * 0.7, height: size * 0.7)
                    .hopping(height: 10, period: 0.9, phase: 0.45)
                    .offset(x: size * 0.25, y: size * 0.12)
            } else {
                WanImage(pose: wanPose)
                    .frame(width: size, height: size)
                    .hopping(height: 14, period: 0.9)
            }
        }
        .frame(height: size)
        .scaleEffect(appeared ? 1 : 0.2)
        .rotationEffect(.degrees(appeared ? 0 : -20))
        .animation(.spring(response: 0.45, dampingFraction: 0.45), value: appeared)
        .accessibilityHidden(true)
    }
}

/// 時刻から計算して、ぴょんぴょん跳ねる (repeatForever は並び替えまで巻き込むので使わない)。
/// 「視差効果を減らす」がオンなら跳ねない
private struct Hopping: ViewModifier {
    let height: CGFloat
    let period: Double
    let phase: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSince(start) / period + phase
                content.offset(y: -height * abs(sin(time * .pi)))
            }
        }
    }
}

extension View {
    func hopping(height: CGFloat, period: Double, phase: Double = 0) -> some View {
        modifier(Hopping(height: height, period: period, phase: phase))
    }
}

/// 一覧のレベル表示の横に置く、自分の顔。タップで姿を選び直す (選ぶまではワンのすけの顔)
struct AvatarFaceButton: View {
    let avatar: AvatarBody?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let avatar {
                    AvatarImage(figure: avatar, pose: .smile)
                } else {
                    WanImage(pose: .wave)
                }
            }
            // 全身の絵を大きく置き、頭のあたりだけを丸く切り取る
            .frame(width: 150, height: 150)
            .offset(y: 30)
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .background(Circle().fill(Pop.card))
            .overlay(Circle().stroke(Pop.orange.opacity(0.3), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(avatar == nil ? "分身の姿を選ぶ" : "分身の姿を選び直す")
    }
}

/// 分身の姿を選ぶ画面。最初は「どっちのきみで始める？」、あとからは「どっちのきみにする？」。
/// 性別の言葉は出さず、絵をタップするだけで選べる。選び直しは何度でも無料
struct AvatarChoiceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// 最初に出すとき (選ばずに「あとで選ぶ」で閉じられる)
    let first: Bool
    @State private var chosen: AvatarBody?

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            WanImage(pose: chosen == nil ? .wave : .banzai)
                .frame(width: 150, height: 150)
                .hopping(height: chosen == nil ? 0 : 12, period: 0.9)
            HeadlineText(chosen != nil ? "いいね！いっしょに始めよう"
                         : first ? "どっちのきみで始める？" : "どっちのきみにする？")
                .font(.system(.title, design: .rounded, weight: .black))
                .multilineTextAlignment(.center)
                .foregroundStyle(Pop.ink)
            HStack(spacing: 16) {
                ForEach(AvatarBody.allCases, id: \.self) { figure in
                    Button { choose(figure) } label: {
                        AvatarImage(figure: figure, pose: chosen == figure ? .joy : .smile)
                            .frame(width: 130, height: 130)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 28).fill(Pop.card))
                            .overlay(RoundedRectangle(cornerRadius: 28)
                                .stroke(Pop.orange, lineWidth: isSelected(figure) ? 4 : 0))
                    }
                    .buttonStyle(.plain)
                    .disabled(chosen != nil)
                    .accessibilityLabel(figure.spokenName)
                    .accessibilityAddTraits(isSelected(figure) ? .isSelected : [])
                }
            }
            PhraseText("あとからいつでも変えられるよ")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Pop.ink.opacity(0.6))
            Spacer()
            if chosen == nil {
                Button(first ? "あとで選ぶ" : "閉じる") {
                    if first { model.skipAvatarChoice() }
                    dismiss()
                }
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Pop.ink.opacity(0.5))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .popBackground()
        .sensoryFeedback(.success, trigger: chosen)
    }

    private func isSelected(_ figure: AvatarBody) -> Bool {
        (chosen ?? (first ? nil : model.avatar)) == figure
    }

    private func choose(_ figure: AvatarBody) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { chosen = figure }
        model.chooseAvatar(figure)
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            dismiss()
        }
    }
}
