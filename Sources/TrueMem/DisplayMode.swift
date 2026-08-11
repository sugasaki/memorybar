import Foundation

/// メニューバーに常時表示する数値の種類(設定で切替可能)
enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
    case freeGB
    case usedGB
    case usedPercent

    static let `default`: DisplayMode = .freeGB

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
        case .usedPercent: "\(Int((snapshot.usedFraction * 100).rounded()))%"
        }
    }

    /// メニューバー向けのコンパクトな GB 表記(例: "12.3G")。メモリ慣例に合わせ 1GB = 1024^3
    static func compactGB(_ bytes: UInt64) -> String {
        String(format: "%.1fG", Double(bytes) / 1_073_741_824)
    }
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
