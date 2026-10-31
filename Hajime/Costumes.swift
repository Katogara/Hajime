import Foundation
import SwiftUI

// 着せ替え。服の品目は Costumes.json にまとめ、品目を足すときは Art/ の SVG と JSON を足すだけにする
// (仕様書「服を増やすための再検討」)。絵は CI の scripts/make_assets.py が Art/ からアセットカタログにする。
// 1 つの部品は「名前_fill」(塗り) と「名前_line」(線) の 2 枚。外形 12px と白ふちは、重ねたあとに FigureRenderer が付ける。

/// 着せ替えるキャラクター
enum CostumeCharacter: String, Codable, CaseIterable {
    case avatar
    case wan
}

/// 服の部位。商品 ID の最後に入る (com.katogara.hajime.{wan|avatar}.{テーマ}.{部位})
enum CostumePart: String, Codable, CaseIterable {
    case head
    /// 顔まわり (めがね)
    case face
    case neck
    case top
    case bottom
    case feet
    case hand

    var label: String {
        switch self {
        case .head: return "頭"
        case .face: return "めがね"
        case .neck: return "首"
        case .top: return "胴"
        case .bottom: return "下"
        case .feet: return "足"
        case .hand: return "手"
        }
    }
}

/// 服の棚 (はじめての・季節・オシャレ)
enum CostumeShelf: String, Codable {
    case first
    case season
    case fashion
}

/// 1 つのテーマのひとそろい (例: アバターのギャル系)
struct CostumeTheme: Codable, Identifiable, Equatable {
    var id: String
    var character: CostumeCharacter
    var shelf: CostumeShelf
    var name: String
    /// 棚の一言 (オシャレもの)
    var note: String?
    /// 季節ものの月
    var month: Int?
    var order: Int
    var items: [CostumeItem]

    /// キャラクターとテーマの組で一意 (ワンのすけとアバターに同じテーマ名がある)
    var key: String { "\(character.rawValue).\(id)" }

    func item(_ part: CostumePart) -> CostumeItem? {
        items.first { $0.part == part }
    }

    func productID(_ part: CostumePart) -> String {
        "com.katogara.hajime.\(character.rawValue).\(id).\(part.rawValue)"
    }
}

/// テーマの中の 1 点 (部位ごとの単品)
struct CostumeItem: Codable, Equatable {
    var part: CostumePart
    var name: String
    /// 袖のない胴の服など、初期の服の上に重ねる (入れ替えない)
    var over: Bool?
    /// ポーズごとの絵の名前 (_fill / _line を除く)。"all" は全ポーズで同じ絵。
    /// アバターのポーズは std (ふつう・にっこり) と joy (大喜び)。ワンのすけの小物は手を振る絵の位置で描き、ほかのポーズは wanAnchors で動かす
    var art: [String: String]

    func art(for pose: String) -> String? {
        art[pose] ?? art["all"]
    }

    var layersOver: Bool { over ?? false }
}

/// ワンのすけの小物を、手を振る絵以外のポーズの頭の位置に合わせる (tools/wan_anchors.py で求めた値)。
/// 頭の真ん中 (center) を中心に scale 倍・deg 度回してから (dx, dy) ずらす。単位は 1024 のキャンバスの px
struct WanAnchor: Codable, Equatable {
    var dx: Double
    var dy: Double
    var scale: Double
    var deg: Double

    static let identity = WanAnchor(dx: 0, dy: 0, scale: 1, deg: 0)
}

struct WanAnchors: Codable, Equatable {
    var center: [Double]
    var poses: [String: WanAnchor]
}

/// Costumes.json の中身
struct CostumeCatalog: Codable, Equatable {
    var version: Int
    var wanAnchors: WanAnchors
    var themes: [CostumeTheme]

    static let empty = CostumeCatalog(version: 0, wanAnchors: WanAnchors(center: [512, 512], poses: [:]), themes: [])

    /// アプリに入れた Costumes.json。読めなければ空 (テストで見つける)
    static let shared: CostumeCatalog = {
        guard let url = Bundle.main.url(forResource: "Costumes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(CostumeCatalog.self, from: data) else { return .empty }
        return catalog
    }()

    func themes(for character: CostumeCharacter) -> [CostumeTheme] {
        themes.filter { $0.character == character }
            .sorted { ($0.shelf.sortKey, $0.order) < ($1.shelf.sortKey, $1.order) }
    }

    func theme(_ character: CostumeCharacter, _ id: String) -> CostumeTheme? {
        themes.first { $0.character == character && $0.id == id }
    }

    func anchor(for pose: WanPose) -> WanAnchor {
        wanAnchors.poses[pose.rawValue] ?? .identity
    }
}

private extension CostumeShelf {
    /// 棚の並び: はじめての、季節、オシャレ
    var sortKey: Int {
        switch self {
        case .first: return 0
        case .season: return 1
        case .fashion: return 2
        }
    }
}

// MARK: - アバターの見た目

/// 髪型。男女どちらでもすべて選べ、無料 (最初は男性がショート、女性がボブ)
enum HairStyle: String, Codable, CaseIterable {
    case short
    case bob
    case mash
    case ponytail

    var label: String {
        switch self {
        case .short: return "ショート"
        case .bob: return "ボブ"
        case .mash: return "マッシュ"
        case .ponytail: return "ひとつ結び"
        }
    }
}

/// 髪の色 (仕様書「髪型と色」)。こげ茶は絵の色のままで、ほかは髪の塗りの部品に色を付ける
enum HairColor: String, Codable, CaseIterable {
    case black
    case brown
    case milkTea
    case ashGray
    case pinkBrown
    case blueBlack

    var label: String {
        switch self {
        case .black: return "黒"
        case .brown: return "こげ茶"
        case .milkTea: return "ミルクティー"
        case .ashGray: return "アッシュグレー"
        case .pinkBrown: return "ピンクブラウン"
        case .blueBlack: return "ブルーブラック"
        }
    }

    var hex: UInt32 {
        switch self {
        case .black: return 0x2F2724
        case .brown: return 0x6B4428
        case .milkTea: return 0xC9A27E
        case .ashGray: return 0x8E908F
        case .pinkBrown: return 0xA86E62
        case .blueBlack: return 0x283449
        }
    }

    var color: Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

/// アバターの見た目 (体と髪)。JSON で UserDefaults の avatarLook に保存し、知らない値や足りない項目は既定値で読む
struct AvatarLook: Codable, Equatable, Hashable {
    var body: AvatarBody
    var hair: HairStyle
    var hairColor: HairColor

    static func initial(for body: AvatarBody) -> AvatarLook {
        AvatarLook(body: body, hair: body == .male ? .short : .bob, hairColor: .brown)
    }

    /// 男女の違いは髪型とまつ毛だけ。まつ毛は女性の体に付ける
    var lashes: Bool { body == .female }

    init(body: AvatarBody, hair: HairStyle, hairColor: HairColor) {
        self.body = body
        self.hair = hair
        self.hairColor = hairColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        body = (try? c.decode(AvatarBody.self, forKey: .body)) ?? .male
        let initial = AvatarLook.initial(for: body)
        hair = (try? c.decode(HairStyle.self, forKey: .hair)) ?? initial.hair
        hairColor = (try? c.decode(HairColor.self, forKey: .hairColor)) ?? initial.hairColor
    }
}

// MARK: - 着ている服

/// キャラクターごとの、部位ごとに着ているテーマ (テーマの id)。UserDefaults の wardrobe に保存する
struct Wardrobe: Codable, Equatable {
    var avatar: [CostumePart: String] = [:]
    var wan: [CostumePart: String] = [:]

    subscript(character: CostumeCharacter) -> [CostumePart: String] {
        get { character == .avatar ? avatar : wan }
        set { if character == .avatar { avatar = newValue } else { wan = newValue } }
    }

    /// 品目のある組だけを残す (服を Costumes.json から外したときなど)
    func valid(in catalog: CostumeCatalog) -> Wardrobe {
        var out = Wardrobe()
        for character in CostumeCharacter.allCases {
            for (part, theme) in self[character] where catalog.theme(character, theme)?.item(part) != nil {
                out[character][part] = theme
            }
        }
        return out
    }

    init() {}

    // 部位の名前をキーにした辞書として保存する (知らない部位は読み飛ばす)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read(_ key: CodingKeys) -> [CostumePart: String] {
            let raw = (try? c.decode([String: String].self, forKey: key)) ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in CostumePart(rawValue: k).map { ($0, v) } })
        }
        avatar = read(.avatar)
        wan = read(.wan)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: avatar.map { ($0.key.rawValue, $0.value) }), forKey: .avatar)
        try c.encode(Dictionary(uniqueKeysWithValues: wan.map { ($0.key.rawValue, $0.value) }), forKey: .wan)
    }

    private enum CodingKeys: String, CodingKey { case avatar, wan }
}

/// 絵に着せるものをまとめた値。画面の環境 (\.dressing) で渡す。
/// 環境が届かない ImageRenderer (シェアのカード) には、呼ぶ側で明示して渡す
struct Dressing: Equatable {
    /// 選んだアバターの見た目 (選んでいなければ nil。絵には体ごとの最初の見た目を使う)
    var look: AvatarLook?
    var wardrobe = Wardrobe()

    func look(for body: AvatarBody) -> AvatarLook {
        if let look, look.body == body { return look }
        return .initial(for: body)
    }
}

private struct DressingKey: EnvironmentKey {
    static let defaultValue = Dressing()
}

extension EnvironmentValues {
    var dressing: Dressing {
        get { self[DressingKey.self] }
        set { self[DressingKey.self] = newValue }
    }
}

// MARK: - 重ね方

/// 重ねる 1 枚の絵
struct FigureLayer: Hashable {
    /// アセットの名前 (_fill / _line まで含む)
    var asset: String
    /// 色を付ける (髪の塗り)。nil なら絵の色のまま
    var tint: UInt32?
    /// ワンのすけの小物を、ポーズの頭の位置に合わせる
    var anchor: WanAnchorKey?
}

/// FigureLayer に入れるため、WanAnchor を Hashable な形にしたもの
struct WanAnchorKey: Hashable {
    var dx: Double
    var dy: Double
    var scale: Double
    var deg: Double
    var cx: Double
    var cy: Double
}

/// 部品の名前から、重ねる順の絵のリストを作る
enum FigureRig {
    /// 部品 1 つは、塗りの上に線を重ねた 2 枚 (色は塗りにだけ付ける)
    static func pair(_ name: String, tint: UInt32? = nil, anchor: WanAnchorKey? = nil) -> [FigureLayer] {
        [FigureLayer(asset: name + "_fill", tint: tint, anchor: anchor), FigureLayer(asset: name + "_line", anchor: anchor)]
    }

    /// アバター。重ね順は、髪のない頭、顔、まつ毛、髪、首と手、足、下、胴、(袖のない胴の服)、首、めがね、頭、手に持つ物。
    /// 服を着替えるときは、その部位の初期の服だけを外す。手に持つ物は、ばんざいの大喜びでは出さない
    static func avatar(_ look: AvatarLook, pose: AvatarPose, wardrobe: Wardrobe,
                       catalog: CostumeCatalog = .shared) -> [FigureLayer] {
        let p = pose == .joy ? "joy" : "std"
        let face: String
        switch pose {
        case .normal: face = "av_face_normal"
        case .smile: face = "av_face_smile"
        case .joy: face = "av_face_joy"
        }
        // 着ている服 (この部位、このポーズの絵があるものだけ)
        func worn(_ part: CostumePart) -> CostumeItem? {
            guard let id = wardrobe.avatar[part], let item = catalog.theme(.avatar, id)?.item(part),
                  item.art(for: p) != nil else { return nil }
            return item
        }
        var layers = pair("av_\(p)_headbase") + pair(face)
        if look.lashes { layers += [FigureLayer(asset: "av_lashes_\(p)_line")] }
        // 髪の色は塗りだけに付ける (こげ茶は絵の色のまま)
        layers += pair("av_hair_\(look.hair.rawValue)", tint: look.hairColor == .brown ? nil : look.hairColor.hex)
        layers += pair("av_\(p)_hands")
        for part in [CostumePart.feet, .bottom, .top] {
            if let item = worn(part), let art = item.art(for: p) {
                if item.layersOver { layers += pair("av_\(p)_\(part.rawValue)") }
                layers += pair(art)
            } else {
                layers += pair("av_\(p)_\(part.rawValue)")
            }
        }
        for part in [CostumePart.neck, .face, .head] {
            if let art = worn(part)?.art(for: p) { layers += pair(art) }
        }
        if pose != .joy, let art = worn(.hand)?.art(for: p) { layers += pair(art) }
        return layers
    }

    /// ワンのすけ。首の小物を付けるときはバンダナを外した絵にする (そのポーズの絵があるときだけ。今は手を振る絵だけ)
    static func wan(pose: WanPose, wardrobe: Wardrobe, catalog: CostumeCatalog = .shared,
                    hasAsset: (String) -> Bool = assetExists) -> [FigureLayer] {
        let neck = wardrobe.wan[.neck].flatMap { catalog.theme(.wan, $0)?.item(.neck) }
        let head = wardrobe.wan[.head].flatMap { catalog.theme(.wan, $0)?.item(.head) }
        let bare = "wan_\(pose.rawValue)_nobandana"
        var layers = pair(neck != nil && hasAsset(bare + "_fill") ? bare : "wan_\(pose.rawValue)")
        let a = catalog.anchor(for: pose)
        let c = catalog.wanAnchors.center
        let key = pose == .wave ? nil
            : WanAnchorKey(dx: a.dx, dy: a.dy, scale: a.scale, deg: a.deg, cx: c.first ?? 512, cy: c.last ?? 512)
        for item in [neck, head].compactMap({ $0 }) {
            if let art = item.art(for: "all") { layers += pair(art, anchor: key) }
        }
        return layers
    }

    static func assetExists(_ name: String) -> Bool {
        UIImage(named: name) != nil
    }
}
