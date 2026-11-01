import SwiftUI

/// きせかえ (設定から開く)。上の台座の 2 人に試着がすぐ反映され、「もとにもどす」で戻せる。
/// 髪型と髪の色は無料で、選ぶとすぐ保存する。服は課金を作るまで、開発中の確かめ用の設定がオンのときだけ着られる。
/// 服は絵で選ぶ (文字の横並びはスクロールが長くなるため)。テーマのひとそろいは「セット」で一度に試着できる。
/// 試着の組み合わせは「コーデ」として保存し、あとで呼び出せる (買っていない服も入れられる)。NEW の印や「人気」の並びは付けない
struct ClosetView: View {
    @Environment(AppModel.self) private var model
    @State private var character: CostumeCharacter = .avatar
    @State private var trying = Wardrobe()
    @State private var joy = false
    @State private var started = false

    private let catalog = CostumeCatalog.shared
    private let pieceColumns = [GridItem(.adaptive(minimum: 76), spacing: 10)]
    private let figureColumns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

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
                VStack(alignment: .leading, spacing: 22) {
                    outfitSection
                    setSection
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
                if !trying[character].isEmpty {
                    if isSaved(trying[character]) {
                        Text("保存ずみ")
                            .foregroundStyle(Pop.ink.opacity(0.5))
                    } else {
                        Button("コーデを保存") { model.saveOutfit(character, trying[character]) }
                    }
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

    // MARK: - コーデとセット

    private var savedOutfits: [SavedOutfit] {
        model.outfits.filter { $0.character == character }
    }

    private func isSaved(_ parts: [CostumePart: String]) -> Bool {
        savedOutfits.contains { $0.parts == parts }
    }

    @ViewBuilder
    private var outfitSection: some View {
        if !savedOutfits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("保存したコーデ")
                LazyVGrid(columns: figureColumns, spacing: 12) {
                    ForEach(Array(savedOutfits.enumerated()), id: \.element.id) { index, outfit in
                        tile("コーデ \(savedOutfits.count - index)", selected: trying[character] == outfit.parts, side: 84) {
                            trying[character] = outfit.parts
                        } picture: {
                            figure(wearing: outfit.parts)
                        }
                        .contextMenu {
                            Button("このコーデを消す", systemImage: "trash", role: .destructive) {
                                model.deleteOutfit(outfit.id)
                            }
                        }
                    }
                }
                PhraseText("長押しすると、コーデを消せます。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Pop.ink.opacity(0.55))
            }
        }
    }

    /// 2 点以上あるテーマは、ひとそろいを一度に試着できる (ほかの部位は脱ぐ)
    @ViewBuilder
    private var setSection: some View {
        let sets = catalog.themes(for: character).filter { $0.items.count >= 2 }
        if !sets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("セット")
                LazyVGrid(columns: figureColumns, spacing: 12) {
                    ForEach(sets) { theme in
                        tile(theme.name, selected: trying[character] == theme.fullSet, side: 84) {
                            trying[character] = theme.fullSet
                        } picture: {
                            figure(wearing: theme.fullSet)
                        }
                    }
                }
            }
        }
    }

    /// 選んでいるキャラクターに、この組み合わせを着せた全身の絵
    private func figure(wearing parts: [CostumePart: String]) -> some View {
        var wardrobe = Wardrobe()
        wardrobe[character] = parts
        return Group {
            if character == .avatar {
                AvatarImage(figure: model.avatar ?? .male, pose: .smile)
            } else {
                WanImage(pose: .wave)
            }
        }
        .environment(\.dressing, Dressing(look: model.look, wardrobe: wardrobe))
    }

    // MARK: - 髪と部位

    private func hairSection(_ look: AvatarLook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("髪型と髪の色（無料）")
            LazyVGrid(columns: pieceColumns, spacing: 12) {
                ForEach(HairStyle.allCases, id: \.self) { hair in
                    let next = AvatarLook(body: look.body, hair: hair, hairColor: look.hairColor)
                    tile(hair.label, selected: look.hair == hair) {
                        model.setLook(next)
                    } picture: {
                        // 全身の絵を大きく置き、頭のあたりだけを丸く切り取る
                        AvatarImage(figure: look.body, pose: .smile)
                            .frame(width: 190, height: 190)
                            .offset(y: 38)
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                            .environment(\.dressing, Dressing(look: next, wardrobe: trying))
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
            LazyVGrid(columns: pieceColumns, spacing: 12) {
                tile(character == .avatar ? "いつもの" : "なし", selected: trying[character][part] == nil) {
                    trying[character][part] = nil
                } picture: {
                    if let base = baseLayers(part) {
                        CostumePieceImage(layers: base)
                    } else {
                        Image(systemName: "nosign")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Pop.ink.opacity(0.3))
                    }
                }
                ForEach(catalog.themes(for: character).filter { $0.item(part) != nil }) { theme in
                    if let item = theme.item(part) {
                        tile(item.name, selected: trying[character][part] == theme.id) {
                            trying[character][part] = theme.id
                        } picture: {
                            CostumePieceImage(layers: pieceLayers(item))
                        }
                    }
                }
            }
        }
    }

    /// アバターの初期の服 (胴・下・足だけにある)。ほかの部位とワンのすけは何も付けない
    private func baseLayers(_ part: CostumePart) -> [FigureLayer]? {
        guard character == .avatar, [.top, .bottom, .feet].contains(part) else { return nil }
        return FigureRig.pair("av_std_\(part.rawValue)")
    }

    private func pieceLayers(_ item: CostumeItem) -> [FigureLayer] {
        guard let art = item.art(for: character == .avatar ? "std" : "all") ?? item.art.values.first else { return [] }
        return FigureRig.pair(art)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .foregroundStyle(Pop.ink)
    }

    /// 絵と名前のボタン。選んでいるものはオレンジの枠で囲む
    private func tile<Picture: View>(_ name: String, selected: Bool, side: CGFloat = 60,
                                     action: @escaping () -> Void,
                                     @ViewBuilder picture: () -> Picture) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                picture()
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pop.card))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Pop.orange, lineWidth: selected ? 4 : 0))
                Text(name)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(Pop.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
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
