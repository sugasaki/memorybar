import Foundation

/// 表示する値の種類(設定で切替可能)。
/// メニューバーと要約表示の両方で同じ値を出すために使う
enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
    case freeGB
    case usedGB
    case usedPercent

    static let `default`: DisplayMode = .freeGB
    /// UserDefaults のキー。文字列リテラルを散らさない
    static let defaultsKey = "displayMode"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .freeGB: "残容量(GB)"
        case .usedGB: "使用量(GB)"
        case .usedPercent: "使用率(%)"
        }
    }

    /// メニューバー用の短い表示文字列
    func menuBarText(for snapshot: MemorySnapshot) -> String {
        switch self {
        case .freeGB: Self.compactGB(snapshot.available)
        case .usedGB: Self.compactGB(snapshot.used)
        case .usedPercent: Self.percentText(snapshot)
        }
    }

    /// 要約表示の大きな数値。メニューバーと同じ値を出す
    func primaryText(for snapshot: MemorySnapshot) -> String {
        switch self {
        case .freeGB: MemoryFormat.detail(snapshot.available)
        case .usedGB: MemoryFormat.detail(snapshot.used)
        case .usedPercent: Self.percentText(snapshot)
        }
    }

    /// 大きな数値が何を指すかを示す語
    var primaryCaption: String {
        switch self {
        case .freeGB: MemoryLabel.available
        case .usedGB: MemoryLabel.used
        // 単位が%なので「使用済みメモリ」だと量に読める。詳細の行名と揃える
        case .usedPercent: MemoryLabel.usedRatio
        }
    }

    static func percentText(_ snapshot: MemorySnapshot) -> String {
        "\(Int((snapshot.usedFraction * 100).rounded()))%"
    }

    /// メニューバー向けのコンパクトな GB 表記(例: "12.3G")。メモリ慣例に合わせ 1GB = 1024^3
    static func compactGB(_ bytes: UInt64) -> String {
        String(format: "%.1fG", Double(bytes) / 1_073_741_824)
    }
}

/// 表示に使う名称。表示面ごとに言い回しがぶれないよう一箇所で決める
enum MemoryLabel {
    /// 搭載されている物理メモリの総量。「物理」は伝わりにくいため使わない
    static let total = "搭載メモリ"
    static let used = "使用済みメモリ"
    /// いま使える量。「空き」より意味が明確
    static let available = "利用可能なメモリ"
    static let usedRatio = "使用率"
}

enum MemoryFormat {
    /// 取得不能を表す表記。0バイトと区別がつくよう数値では表さない
    static let unavailable = "取得不能"

    /// 詳細パネル用の表記(例: "12.34 GB")。アクティビティモニタと同じメモリ表記
    static func detail(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    /// 取得できなかった値を一貫した表記で返す(表示面ごとに文言がぶれないようにする)。
    /// `map(detail)` は非Optional版のシグネチャが変わると静かにこの関数自身へ
    /// 解決されて無限再帰しうるため、明示的に分岐する
    static func detail(_ bytes: UInt64?) -> String {
        guard let bytes else { return unavailable }
        return detail(bytes)
    }
}
