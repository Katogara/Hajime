import CoreImage
import SwiftUI

// ワンのすけとアバターの絵。Art/ の SVG (CI がアセットカタログにする) を部品ごとに重ね、
// 重ねたシルエットに外形の線と白ふちを付けて 1 枚の画像にする (仕様書「線の太さの決め直し」)。
// 重ね方は Costumes.swift の FigureRig、着ている服と髪は画面の環境 \.dressing で受け取る。

/// 部品を 1024 のキャンバスの大きさで重ねたもの (外形はまだ付けない)
private struct FigureStack: View {
    let layers: [FigureLayer]
    let side: CGFloat

    var body: some View {
        ZStack {
            ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                piece(layer)
            }
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private func piece(_ layer: FigureLayer) -> some View {
        let unit = side / 1024
        let image = Image(layer.asset)
        Group {
            if let tint = layer.tint {
                image.resizable().renderingMode(.template)
                    .foregroundStyle(Color(red: Double((tint >> 16) & 0xFF) / 255,
                                           green: Double((tint >> 8) & 0xFF) / 255,
                                           blue: Double(tint & 0xFF) / 255))
            } else {
                image.resizable()
            }
        }
        .frame(width: side, height: side)
        .modifier(AnchorEffect(anchor: layer.anchor, unit: unit))
    }
}

/// ワンのすけの小物を、頭の真ん中を中心に拡大・回転してから、ずらす (tools/wan_anchors.py と同じ手順)
private struct AnchorEffect: ViewModifier {
    let anchor: WanAnchorKey?
    let unit: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if let a = anchor {
            let center = UnitPoint(x: a.cx / 1024, y: a.cy / 1024)
            content
                .scaleEffect(CGFloat(a.scale), anchor: center)
                .rotationEffect(.degrees(a.deg), anchor: center)
                .offset(x: CGFloat(a.dx) * unit, y: CGFloat(a.dy) * unit)
        } else {
            content
        }
    }
}

/// 重ねた絵に、外形の線 (キャンバスの 12/1024。シルエットの内と外に 6 ずつ) と白ふち (24/1024) を付けた画像を作る。
/// 同じ重ね方と大きさの画像は取っておき、着替えたときだけ作り直す (毎回作ると重い)
@MainActor
enum FigureRenderer {
    private static let cache = NSCache<NSString, UIImage>()
    private static let context = CIContext()
    static let line = CIColor(red: 0x5A / 255.0, green: 0x3A / 255.0, blue: 0x22 / 255.0)

    static func image(_ layers: [FigureLayer], side: CGFloat, scale: CGFloat, border: Bool = true) -> UIImage? {
        guard side > 0 else { return nil }
        // 同じ小物の絵でもポーズでずらし方が違うので、ずらし方も含めた並び全体をキーにする
        let key = "\(layers)-\(Int(side * scale))-\(border)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let renderer = ImageRenderer(content: FigureStack(layers: layers, side: side))
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return nil }
        let base = CIImage(cgImage: cg)
        let extent = base.extent
        let unit = extent.width / 1024
        func dilate(_ r: CGFloat) -> CIImage {
            base.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: r * unit]).cropped(to: extent)
        }
        func paint(_ color: CIColor, mask: CIImage) -> CIImage {
            CIImage(color: color).cropped(to: extent)
                .applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: CIImage.empty().cropped(to: extent),
                    kCIInputMaskImageKey: mask])
        }
        let eroded = base.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 6 * unit])
            .cropped(to: extent)
        let ring = base.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: eroded])
        var out = paint(line, mask: dilate(6))
        if border { out = out.composited(over: paint(.white, mask: dilate(6 + 24))) }
        out = paint(line, mask: ring).composited(over: base.composited(over: out))
        guard let made = context.createCGImage(out, from: extent) else { return nil }
        let image = UIImage(cgImage: made, scale: scale, orientation: .up)
        cache.setObject(image, forKey: key)
        return image
    }
}

/// 重ねた絵を、置かれた枠いっぱいの正方形で出す
private struct FigureView: View {
    let layers: [FigureLayer]
    /// 左右を反転する (向かせたい方向が絵と逆のとき)
    var flip = false
    var border = true
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if let image = FigureRenderer.image(layers, side: side, scale: displayScale, border: border) {
                    Image(uiImage: image).resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: side, height: side)
            .scaleEffect(x: flip ? -1 : 1, y: 1)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// ワンのすけ
struct WanImage: View {
    let pose: WanPose
    /// 向かせたい方向 (相手や吹き出しのほう)。nil なら絵のまま
    var facing: Facing?
    @Environment(\.dressing) private var dressing

    var body: some View {
        FigureView(layers: FigureRig.wan(pose: pose, wardrobe: dressing.wardrobe),
                   flip: facing.map(pose.facing.needsFlip) == true)
            .accessibilityLabel("ワンのすけ")
    }
}

/// ユーザーの分身のアバター。髪と服は \.dressing から (選んだ体と違う体を見せるときは、その体の最初の見た目)
struct AvatarImage: View {
    let figure: AvatarBody
    let pose: AvatarPose
    /// 向かせたい方向 (ワンのすけのほう)。nil なら絵のまま
    var facing: Facing?
    @Environment(\.dressing) private var dressing

    var body: some View {
        FigureView(layers: FigureRig.avatar(dressing.look(for: figure), pose: pose, wardrobe: dressing.wardrobe),
                   flip: facing.map(pose.facing.needsFlip) == true)
            .accessibilityLabel("あなたの分身")
    }
}

/// 褒める画面の主役。アバターが真ん中で大喜びし、ワンのすけが右下で一緒に喜ぶ。
/// 2 人が向き合って喜ぶよう、アバターは右 (ワンのすけのほう)、ワンのすけは左 (アバターのほう) を向かせる。
/// アバターをまだ選んでいなければ、ワンのすけだけで褒める
struct CheerStage: View {
    let avatar: AvatarBody?
    let wanPose: WanPose
    /// 出てくるときの動き
    let appeared: Bool
    /// アバターの絵の大きさ (正方形)。ワンのすけはその 0.6 倍 (背丈がアバターの腰のあたり)
    var size: CGFloat = 220

    private static let wanScale: CGFloat = 0.6
    /// 足元の高さ (絵の中で 920/1024)。ワンのすけの足元をアバターにそろえるのに使う
    private static let foot: CGFloat = 920.0 / 1024

    var body: some View {
        ZStack {
            if let avatar {
                AvatarImage(figure: avatar, pose: .joy, facing: .right)
                    .frame(width: size, height: size)
                    .hopping(height: 14, period: 0.9)
                    .offset(x: -size * 0.12)
                // 足元の高さをアバターにそろえ、少し右に寄せて並べる
                WanImage(pose: wanPose, facing: .left)
                    .frame(width: size * Self.wanScale, height: size * Self.wanScale)
                    .hopping(height: 10, period: 0.9, phase: 0.45)
                    .offset(x: size * 0.25, y: size * (Self.foot - 0.5) * (1 - Self.wanScale))
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
