import SwiftUI

/// 物理メモリの内訳を、構成比の帯と凡例で共用するための定義。
/// 帯と凡例で色や順序がずれないよう、単一の配列から両方を描く
struct MemorySegment: Identifiable {
    let id: String
    let label: String
    let bytes: UInt64
    let color: Color

    var name: String { label }
}

enum MemoryComposition {
    /// 物理メモリを覆う内訳。合計は必ず物理メモリと一致する
    /// (使用済み = アプリ+確保済み+圧縮+その他、残容量 = キャッシュ+未使用)
    static func segments(of snapshot: MemorySnapshot) -> [MemorySegment] {
        [
            MemorySegment(id: "app", label: "アプリメモリ", bytes: snapshot.appMemory, color: .yellow),
            MemorySegment(id: "wired", label: "確保済み", bytes: snapshot.wired, color: .orange),
            MemorySegment(id: "compressed", label: "圧縮", bytes: snapshot.compressed, color: .cyan),
            MemorySegment(id: "other", label: "その他", bytes: snapshot.other, color: .purple),
            MemorySegment(
                id: "cached", label: "キャッシュされたファイル", bytes: snapshot.cachedFiles,
                color: .blue.opacity(0.45)),
            MemorySegment(id: "unused", label: "未使用", bytes: snapshot.unused, color: .green),
        ]
    }
}

/// 構成比を1本の帯で表す。幅が狭くても各区画が消えないよう最小幅を確保する
struct CompositionBar: View {
    let snapshot: MemorySnapshot
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(MemoryComposition.segments(of: snapshot)) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: width(of: segment, in: geometry.size.width))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }

    private func width(of segment: MemorySegment, in total: CGFloat) -> CGFloat {
        guard snapshot.total > 0 else { return 0 }
        let ratio = Double(segment.bytes) / Double(snapshot.total)
        // 0 のときは描かない。わずかでもあるものは細くても見えるようにする
        guard ratio > 0 else { return 0 }
        return max(2, total * ratio)
    }
}
