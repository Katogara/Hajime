import SwiftUI
import UIKit

/// アプリ全体の見た目。オレンジを主役に、丸い文字・ぷっくりしたボタン・あたたかい背景でポップにする。
enum Pop {
    static let orange = Color(light: 0xFF7A1A, dark: 0xFF8A33)
    /// ボタンの下に敷く濃いオレンジ (押すと沈んで見える)
    static let orangeDeep = Color(light: 0xD95A00, dark: 0xB84A00)
    static let yellow = Color(light: 0xFFC83D, dark: 0xF2B526)
    static let green = Color(light: 0x2EC27E, dark: 0x3FD08C)
    static let greenDeep = Color(light: 0x1E9460, dark: 0x23885A)
    static let pink = Color(light: 0xFF6F91, dark: 0xFF7F9D)
    /// 画面の背景 (クリーム色)
    static let background = Color(light: 0xFFF4E6, dark: 0x1F1610)
    /// カードの地
    static let card = Color(light: 0xFFFFFF, dark: 0x33251B)
    /// 文字と影の色 (こげ茶)
    static let ink = Color(light: 0x3A2414, dark: 0xFFF1E0)

    /// やることごとに色を変えて、一覧をにぎやかにする
    static let taskColors: [Color] = [orange, green, pink, yellow]

    static func taskColor(_ index: Int) -> Color {
        taskColors[index % taskColors.count]
    }
}

extension Color {
    /// ライト・ダークで切り替わる色 (0xRRGGBB)
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// ぷっくりしたボタン。下に濃い色の段があり、押すと沈んで少しつぶれる。
struct PopButtonStyle: ButtonStyle {
    var color: Color = Pop.orange
    var shade: Color = Pop.orangeDeep
    var foreground: Color = .white
    var depth: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .foregroundStyle(foreground)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Capsule().fill(color))
            .background(Capsule().fill(shade).offset(y: pressed ? 0 : depth))
            .offset(y: pressed ? depth : 0)
            .scaleEffect(pressed ? 0.97 : 1)
            .padding(.bottom, depth)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: pressed)
            .sensoryFeedback(.impact(weight: .medium), trigger: pressed) { _, new in new }
    }
}

/// 白い (やや目立たない) ぷっくりボタン
extension PopButtonStyle {
    static var plain: PopButtonStyle {
        PopButtonStyle(color: Pop.card, shade: Pop.ink.opacity(0.18), foreground: Pop.ink)
    }
}

/// 角の丸いカード。下にうっすら段をつけて、シールのように見せる。
struct PopCard: ViewModifier {
    var tint: Color = Pop.ink

    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Pop.card))
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(tint.opacity(0.35)).offset(y: 6))
            .padding(.bottom, 6)
    }
}

extension View {
    func popCard(tint: Color = Pop.ink) -> some View {
        modifier(PopCard(tint: tint))
    }

    /// 画面全体の背景をクリーム色にする
    func popBackground() -> some View {
        background(Pop.background.ignoresSafeArea())
    }
}

/// 時刻などを入れる小さな丸いラベル
struct PopChip: View {
    let text: String
    var color: Color = Pop.yellow

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(Pop.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.35)))
    }
}
