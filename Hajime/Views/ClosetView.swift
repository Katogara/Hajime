import SwiftUI

/// きせかえ (一覧の右上のハンガーから開く)。上の台座の 2 人に試着がすぐ反映される。
/// 「もとにもどす」「コーデを保存」「着る」は、いつでも押せるよう右上に置く。
/// 髪型と髪の色は無料で、選ぶとすぐ保存する。服は課金を作るまで、開発中の確かめ用の設定がオンのときだけ着られる。
/// 服は絵で選ぶ (文字の横並びはスクロールが長くなるため)。テーマのひとそろいは「セット」で一度に試着できる。
/// 試着の組み合わせは「コーデ」として保存し、あとで呼び出せる (買っていない服も入れられる)。NEW の印や「人気」の並びは付けない
struct ClosetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var character: CostumeCharacter = .avatar
    /// 試着で変えた組み合わせ。変えるまでは nil で、いま着ている服をそのまま見せる
    /// (開いたときに写しておくと、写す前の空の組み合わせが残ることがあるため)
    @State private var edited: Wardrobe?
    /// 最後に押したタイル。台座の下の帯に、その名前を省略せずに出す
    @State private var pick: TryOnPick?

    private let catalog = CostumeCatalog.shared
    private let pieceColumns = [GridItem(.adaptive(minimum: 76), spacing: 10, alignment: .top)]
    private let figureColumns = [GridItem(.adaptive(minimum: 96), spacing: 10, alignment: .top)]

    /// 着ている服 (着られないあいだは初期の服)
    private var worn: Wardrobe { model.devWearAll ? model.wardrobe : Wardrobe() }
    private var trying: Wardrobe { edited ?? worn }

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
                        PhraseText("服を買えるようになるまでは、試着だけできます。いま着るには、設定の「開発中の確かめ用」で「すべての服を着られるようにする」をオンにしてください。")
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
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { edited = nil; pick = nil } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(trying == worn)
                .accessibilityLabel("もとにもどす")
                Button { model.saveOutfit(character, trying[character]) } label: {
                    Image(systemName: isSaved(trying[character]) ? "bookmark.fill" : "bookmark")
                }
                .disabled(trying[character].isEmpty || isSaved(trying[character]))
                .accessibilityLabel(isSaved(trying[character]) ? "保存ずみのコーデ" : "コーデを保存")
                // 着られないあいだも見せておき、押せない理由は一覧の下に書く
                Button("着る") { wearTrying() }
                    .fontWeight(.bold)
                    .disabled(!model.devWearAll || trying == model.wardrobe)
            }
        }
        .sensoryFeedback(.selection, trigger: trying)
    }

    /// 上の台座。アバター (選んでいれば) とワンのすけに、試着中の服を着せて並べる。
    /// 一覧と同じふだんの姿 (アバターは「ふつう」、ワンのすけは手を振る) で見せ、ポーズは切り替えない
    /// (大喜びは褒める画面だけで見せる。切り替えのボタンは、今のポーズの説明に読まれたため外した)
    private var stage: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: -10) {
                if let avatar = model.avatar {
                    AvatarImage(figure: avatar, pose: .normal)
                        .frame(width: 170, height: 170)
                }
                WanImage(pose: .wave, facing: model.avatar == nil ? nil : .left)
                    .frame(width: model.avatar == nil ? 170 : 110, height: model.avatar == nil ? 170 : 110)
            }
            .environment(\.dressing, Dressing(look: model.look, wardrobe: trying))
            captionBand
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Pop.cream)
    }

    /// 最後に押したタイルの名前を省略せずに出す帯。タイルの名前は 2 行で切れるので、全文はここで読む。
    /// 高さは 52pt 以上で、文字を大きくしたときは伸ばす (省略しない)。白は使わずクリーム色にオレンジの細い枠
    private var captionBand: some View {
        let caption = pick.flatMap { $0.character == character ? TryOnCaption($0, catalog: catalog) : nil } ?? .hint
        return VStack(spacing: 2) {
            PhraseText(caption.name)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(caption == .hint ? Pop.ink.opacity(0.55) : Pop.ink)
            if !caption.detail.isEmpty {
                PhraseText(caption.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Pop.ink.opacity(0.6))
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Pop.cream))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Pop.orange, lineWidth: 1.5))
        .padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.2), value: caption)
        .accessibilityElement(children: .combine)
    }

    private var parts: [CostumePart] {
        let present = Set(catalog.themes(for: character).flatMap { $0.items.map(\.part) })
        return CostumePart.allCases.filter(present.contains)
    }

    /// 選んでいるキャラクターの試着を変える
    private func change(_ update: (inout [CostumePart: String]) -> Void) {
        var next = trying
        update(&next[character])
        edited = next
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
                            change { $0 = outfit.parts }
                            pick = .outfit(character, number: savedOutfits.count - index)
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

    /// 2 点以上あるテーマは、ひとそろいを一度に試着できる (ほかの部位は脱ぐ)。先頭の「いつもの」で全部脱ぐ
    @ViewBuilder
    private var setSection: some View {
        let sets = catalog.themes(for: character).filter { $0.items.count >= 2 }
        if !sets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("セット")
                LazyVGrid(columns: figureColumns, spacing: 12) {
                    tile(character == .avatar ? "いつもの" : "なし", selected: trying[character].isEmpty, side: 84) {
                        change { $0 = [:] }
                        pick = .set(character, theme: nil)
                    } picture: {
                        figure(wearing: [:])
                    }
                    ForEach(sets) { theme in
                        tile(theme.name, selected: trying[character] == theme.fullSet, side: 84) {
                            change { $0 = theme.fullSet }
                            pick = .set(character, theme: theme.id)
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
                AvatarImage(figure: model.avatar ?? .male, pose: .normal)
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
                        pick = .hair(hair)
                    } picture: {
                        // 全身の絵を大きく置き、頭のあたりだけを丸く切り取る
                        AvatarImage(figure: look.body, pose: .normal)
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
                    change { $0[part] = nil }
                    pick = .piece(character, part, theme: nil)
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
                            change { $0[part] = theme.id }
                            pick = .piece(character, part, theme: theme.id)
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

    /// 絵と名前のボタン。選んでいるものはオレンジの枠で囲む。
    /// 名前はいつも 2 行ぶんの高さを取り、1 行の名前と 2 行の名前で絵の上端がずれないようにする
    private func tile<Picture: View>(_ name: String, selected: Bool, side: CGFloat = 60,
                                     action: @escaping () -> Void,
                                     @ViewBuilder picture: () -> Picture) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // 髪型の絵は大きな全身を丸く切り抜いているだけで、はみ出した部分が隣のタイルのタップを拾っていた
                // (ひとつ結びを選んだあと、左隣のマッシュを押してもひとつ結びのまま)。絵ではタップを受けず、枠で受ける
                picture()
                    .allowsHitTesting(false)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pop.card))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Pop.orange, lineWidth: selected ? 4 : 0))
                Text(name)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(Pop.ink)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .contentShape(Rectangle())
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
        edited = nil
    }
}
