import SwiftUI
import UIKit

/// ワンのすけの吹き出しの形。しっぽは上の辺 (右寄り) か、左の辺から出す
struct BubbleShape: Shape {
    enum Tail {
        /// 上の辺から上へ。位置は幅に対する割合
        case top(CGFloat)
        /// 左の辺から左へ (縦の真ん中)
        case leading
    }

    var tail: Tail
    var radius: CGFloat = 22
    var tailSize: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        var tailPath = Path()
        switch tail {
        // しっぽは本体の辺にぴったり接する三角形にする (重ねると、塗りの向きによって穴があく)
        case .top(let fraction):
            let x = rect.minX + rect.width * fraction
            tailPath.move(to: CGPoint(x: x - tailSize, y: rect.minY))
            tailPath.addLine(to: CGPoint(x: x + tailSize * 0.4, y: rect.minY - tailSize))
            tailPath.addLine(to: CGPoint(x: x + tailSize * 0.6, y: rect.minY))
        case .leading:
            let y = rect.midY
            tailPath.move(to: CGPoint(x: rect.minX, y: y - tailSize * 0.7))
            tailPath.addLine(to: CGPoint(x: rect.minX - tailSize, y: y + tailSize * 0.2))
            tailPath.addLine(to: CGPoint(x: rect.minX, y: y + tailSize * 0.7))
        }
        tailPath.closeSubpath()
        path.addPath(tailPath)
        return path
    }
}

/// ワンのすけのせりふを入れる吹き出し (白地にこげ茶の線。ダークモードでも変えない)
struct SpeechBubble<Content: View>: View {
    var tail: BubbleShape.Tail = .top(0.78)
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            // 太い線を引いてから白で塗る。外側の半分 (3pt) だけが線として残り、本体としっぽの境目は塗りで消える
            .background {
                BubbleShape(tail: tail).stroke(Pop.brown, lineWidth: 6)
                BubbleShape(tail: tail).fill(Color.white)
            }
    }
}

/// 画面の下に出る、ワンのすけの小さな帯。演出が「控えめ」のときの褒め言葉、「やっぱりやめます」のあとの
/// 「またね」に使う。タップか、少しすると消える
struct WanBand: View {
    let pose: WanPose
    var title: String?
    let text: String
    var emoji: String?

    var body: some View {
        HStack(spacing: 14) {
            WanImage(pose: pose)
                .frame(width: 76, height: 76)
                .hopping(height: 4, period: 1.2)
            SpeechBubble(tail: .leading) {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        HeadlineText(title)
                            .font(.system(.headline, design: .rounded, weight: .black))
                            .foregroundStyle(Pop.orangeDeep)
                    }
                    HStack(spacing: 8) {
                        if let emoji {
                            Text(emoji).font(.system(size: 30))
                        }
                        PhraseText(text)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Pop.brown)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Pop.cream)
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4))
        .padding(.horizontal, 12)
        // 一覧のいちばん下のボタンを隠しすぎないよう、少し浮かせる
        .padding(.bottom, 24)
        .accessibilityElement(children: .combine)
    }
}

/// 演出が「控えめ」のときの褒め言葉の帯 (せりふは出たときに 1 回だけ選ぶ)
struct CheerBand: View {
    let cheer: Cheer
    @State private var line: WanLines.Line

    init(cheer: Cheer, step: String?, title: String?) {
        self.cheer = cheer
        _line = State(initialValue: CheerView.line(for: cheer.kind, step: step, title: title))
    }

    var body: some View {
        WanBand(pose: cheer.kind == .continued ? .clap : .banzai, title: line.title,
                text: cheer.levelUp.map { "Lv.\($0) になったよ。\(line.sub)" } ?? line.sub)
    }
}

/// 演出が「控えめ」のときのおみやげの帯
struct SouvenirBand: View {
    let souvenir: Souvenir
    @State private var line = WanLines.souvenir.randomElement()!

    var body: some View {
        WanBand(pose: .wave, title: souvenir.item?.name, text: line, emoji: souvenir.item?.emoji)
    }
}

/// 帯を画面の下に出し、決めた時間がたつかタップで消す。同じ id のあいだだけ待つ
struct WanBandOverlay<Item: Identifiable & Equatable, Band: View>: ViewModifier {
    @Binding var item: Item?
    var seconds: Double = 3
    @ViewBuilder let band: (Item) -> Band

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let item {
                band(item)
                    .onTapGesture { dismiss(item) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: item.id) {
                        try? await Task.sleep(for: .seconds(seconds))
                        dismiss(item)
                    }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: item)
    }

    private func dismiss(_ shown: Item) {
        if item == shown { item = nil }
    }
}

extension View {
    func wanBand<Item: Identifiable & Equatable, Band: View>(_ item: Binding<Item?>, seconds: Double = 3,
                                                               @ViewBuilder band: @escaping (Item) -> Band)
        -> some View {
        modifier(WanBandOverlay(item: item, seconds: seconds, band: band))
    }
}

/// ワンのすけがおみやげを拾ってきた。箱がぽんと開いて品が出る。タップで閉じる
struct SouvenirView: View {
    let souvenir: Souvenir
    let onDone: () -> Void
    @State private var opened = false
    @State private var line = WanLines.souvenir.randomElement()!

    var body: some View {
        ZStack {
            Pop.cream.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Text("🎁")
                        .font(.system(size: 90))
                        .scaleEffect(opened ? 0.2 : 1)
                        .opacity(opened ? 0 : 1)
                    Text(souvenir.item?.emoji ?? "🎁")
                        .font(.system(size: 110))
                        .scaleEffect(opened ? 1 : 0.2)
                        .rotationEffect(.degrees(opened ? 0 : -40))
                        .opacity(opened ? 1 : 0)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.45).delay(0.5), value: opened)
                .frame(height: 140)
                if let item = souvenir.item {
                    HeadlineText(item.name)
                        .font(.system(.title, design: .rounded, weight: .black))
                        .foregroundStyle(Pop.orangeDeep)
                        .opacity(opened ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.9), value: opened)
                }
                HStack(alignment: .center, spacing: 10) {
                    WanImage(pose: .wave)
                        .frame(width: 120, height: 120)
                        .hopping(height: 8, period: 1)
                    SpeechBubble(tail: .leading) {
                        VStack(alignment: .leading, spacing: 6) {
                            PhraseText(line)
                                .font(.system(.headline, design: .rounded, weight: .heavy))
                                .foregroundStyle(Pop.brown)
                            if let item = souvenir.item {
                                PhraseText(item.note)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Pop.brown.opacity(0.7))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                PhraseText("もらったおみやげは「これまでのつみあげ」で見られます")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Pop.brown.opacity(0.6))
            }
            .padding(24)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .sensoryFeedback(.success, trigger: opened)
        .onAppear { opened = true }
    }
}

/// 久しぶりに開いた日に、一覧の上に出す「おかえり」。閉じたらその日は出さない
struct WelcomeBubble: View {
    let onClose: () -> Void
    @State private var line = WanLines.welcome.randomElement()!

    var body: some View {
        HStack(spacing: 10) {
            WanImage(pose: .wave)
                .frame(width: 80, height: 80)
            SpeechBubble(tail: .leading) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HeadlineText(line.title)
                            .font(.system(.headline, design: .rounded, weight: .black))
                            .foregroundStyle(Pop.orangeDeep)
                        PhraseText(line.sub)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Pop.brown)
                    }
                    Spacer(minLength: 4)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Pop.brown.opacity(0.5))
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel("閉じる")
                }
            }
        }
    }
}

// MARK: - シェア

/// シェア用の正方形のカード。「今日、これをはじめた」の一瞬を、アバターとワンのすけの絵にする (回数は載せない)
struct ShareCard: View {
    let step: String
    let avatar: AvatarBody?
    /// 画像にするときの一辺 (pt)。scale 3 で 1080px
    static let side: CGFloat = 360

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: -24) {
                if let avatar {
                    AvatarImage(figure: avatar, pose: .joy)
                        .frame(width: 170, height: 170)
                }
                WanImage(pose: .banzai)
                    .frame(width: avatar == nil ? 170 : 120, height: avatar == nil ? 170 : 120)
            }
            HeadlineText("\(step)から、はじめました")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Pop.brown)
                .padding(.horizontal, 24)
            Spacer(minLength: 0)
            Text("はじめる")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(Pop.orangeDeep)
                .padding(.bottom, 16)
        }
        .frame(width: Self.side, height: Self.side)
        .background(Pop.cream)
        .environment(\.colorScheme, .light)
    }

    /// 画像にする (押したときだけ作る)
    @MainActor
    func render() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// 作った画像を渡す共有シート (写真への保存、LINE、AirDrop など)
struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 共有する画像 (sheet(item:) で出すため)
struct SharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
