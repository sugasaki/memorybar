import SwiftUI

extension MemoryPressure {
    /// 表示面ごとにばらつかないよう、色は一箇所で決める
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        case .unknown: .gray
        }
    }
}

/// 要約表示。残容量を大きく出し、離れていても一目で読めることを優先する。
/// メニューパネルとフローティングウィンドウで共用し、見た目を揃える
struct MemorySummaryView<Accessory: View>: View {
    let snapshot: MemorySnapshot
    /// 見出しの左に置く要素(パネルではアイコン、フローティングでは閉じるボタン)。
    /// AnyView で型消去するとビューの同一性が失われ差分更新が効かないため、型で受ける
    private let accessory: Accessory

    init(snapshot: MemorySnapshot, @ViewBuilder accessory: () -> Accessory) {
        self.snapshot = snapshot
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                accessory
                Text("TrueMem")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Circle()
                    .fill(snapshot.pressure.color)
                    .frame(width: 9, height: 9)
                Text(snapshot.pressure.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(MemoryFormat.detail(snapshot.available))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("空き")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(Int((snapshot.usedFraction * 100).rounded()))%")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            CompositionBar(snapshot: snapshot)
        }
    }
}

/// 内訳。帯と同じ順序・同じ色で並べ、凡例を兼ねる
struct MemoryDetailsView: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // アクティビティモニタとの突き合わせに使う2値。内訳だけだと照合できない
            HStack {
                Text("使用済みメモリ")
                Spacer(minLength: 8)
                Text(MemoryFormat.detail(snapshot.used))
                    .monospacedDigit()
            }
            .font(.callout.weight(.semibold))
            ForEach(MemoryComposition.segments(of: snapshot)) { segment in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segment.color)
                        .frame(width: 9, height: 9)
                    Text(segment.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(MemoryFormat.detail(segment.bytes))
                        .monospacedDigit()
                }
                .font(.callout)
            }
            Divider()
            HStack {
                Text("使用済みスワップ")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(MemoryFormat.detail(snapshot.swapUsed))
                    .monospacedDigit()
            }
            .font(.callout)
            HStack {
                Text("物理メモリ")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(MemoryFormat.detail(snapshot.total))
                    .monospacedDigit()
            }
            .font(.callout)
        }
    }
}

/// 折りたたみの見出し。パネルとフローティングで同じ操作感にする
struct DisclosureHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
