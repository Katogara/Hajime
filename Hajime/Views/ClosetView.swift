import SwiftUI

/// きせかえ (設定から開く)。上の台座の 2 人に試着がすぐ反映され、「もとにもどす」で戻せる。
/// 髪型と髪の色は無料で、選ぶとすぐ保存する。服は課金を作るまで、開発中の確かめ用の設定がオンのときだけ着られる。
/// 試着は画面の中だけで、保存しない (仕様書「本格導入の前の検討」)。NEW の印や「人気」の並びは付けない
struct ClosetView: View {
    @Environment(AppModel.self) private var model
    @State private var character: CostumeCharacter = .avatar
    @State private var trying = Wardrobe()
    @State private var joy = false
    @State private var started = false

    private let catalog = CostumeCatalog.shared

    var body: some View {
        VStack(spacing: 0) {
            stage
            Picker("きせかえる", selection: $character) {
                Text("じぶん").tag(CostumeCharacter.avatar)
                Text("ワンのすけ").tag(CostumeCharacter.wan)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if character == .avatar, let look = model.look {
                        hairSection(look)
                    }
                    ForEach(parts, id: \.self) { part in
                        partSection(part)
                    }
                    if !model.devWearAll {
                        PhraseText("服を買えるようになるまでは、試着だけできます。")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Pop.ink.opacity(0.6))
                    }
                }
                .padding(16)
            }
        }
        .popBackground()
        .navigationTitle("きせかえ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if model.devWearAll && trying != model.wardrobe {
                    Button("着る") { wearTrying() }
                }
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            trying = model.devWearAll ? model.wardrobe : Wardrobe()
        }
        .sensoryFeedback(.selection, trigger: trying)
    }

    /// 上の台座。アバター (選んでいれば) とワンのすけに、試着中の服を着せて並べる
    private var stage: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: -10) {
                if let avatar = model.avatar {
                    AvatarImage(figure: avatar, pose: joy ? .joy : .smile, facing: .right)
                        .frame(width: 170, height: 170)
                }
                WanImage(pose: joy ? .banzai : .wave, facing: model.avatar == nil ? nil : .left)
                    .frame(width: model.avatar == nil ? 170 : 110, height: model.avatar == nil ? 170 : 110)
            }
            .environment(\.dressing, Dressing(look: model.look, wardrobe: trying))
            HStack(spacing: 18) {
                Button(joy ? "ふつうのポーズ" : "大喜びのポーズ") { joy.toggle() }
                if trying != (model.devWearAll ? model.wardrobe : Wardrobe()) {
                    Button("もとにもどす") { trying = model.devWearAll ? model.wardrobe : Wardrobe() }
                }
            }
            .font(.system(.subheadline, design: .rounded, weight: .bold))
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Pop.cream)
    }

    private var parts: [CostumePart] {
        let present = Set(catalog.themes(for: character).flatMap { $0.items.map(\.part) })
        return CostumePart.allCases.filter(present.contains)
    }

    private func hairSection(_ look: AvatarLook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("髪型と髪の色（無料）")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HairStyle.allCases, id: \.self) { hair in
                        chip(hair.label, selected: look.hair == hair) {
                            var next = look
                            next.hair = hair
                            model.setLook(next)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                ForEach(HairColor.allCases, id: \.self) { color in
                    Button {
                        var next = look
                        next.hairColor = color
                        model.setLook(next)
                    } label: {
                        Circle().fill(color.color)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(Pop.orange, lineWidth: look.hairColor == color ? 4 : 0))
                    }
                    .accessibilityLabel(color.label)
                    .accessibilityAddTraits(look.hairColor == color ? .isSelected : [])
                }
            }
        }
    }

    private func partSection(_ part: CostumePart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(part.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(character == .avatar ? "いつもの" : "なし", selected: trying[character][part] == nil) {
                        trying[character][part] = nil
                    }
                    ForEach(catalog.themes(for: character).filter { $0.item(part) != nil }) { theme in
                        if let item = theme.item(part) {
                            chip("\(item.name)（\(theme.name)）", selected: trying[character][part] == theme.id) {
                                trying[character][part] = theme.id
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .foregroundStyle(Pop.ink)
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(selected ? .white : Pop.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(selected ? Pop.orange : Pop.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func wearTrying() {
        for c in CostumeCharacter.allCases {
            for part in CostumePart.allCases where trying[c][part] != model.wardrobe[c][part] {
                model.wear(c, part, theme: trying[c][part])
            }
        }
    }
}
