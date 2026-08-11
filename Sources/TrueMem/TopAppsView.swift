import AppKit
import SwiftUI

/// アプリアイコンの取得結果を保持する。
/// `NSRunningApplication(processIdentifier:)` は実測で5行あたり約1.5msかかり、
/// 表示中は毎秒再評価されるため、ほぼ変わらないアイコンを引き直さないようにする
@MainActor
enum AppIconCache {
    private static var cache: [pid_t: NSImage] = [:]
    /// 起動・終了を繰り返すと際限なく増えるため、頃合いで捨てる
    private static let capacity = 64

    static func icon(for pid: pid_t) -> NSImage? {
        if let cached = cache[pid] { return cached }
        guard let image = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        if cache.count >= capacity { cache.removeAll(keepingCapacity: true) }
        cache[pid] = image
        return image
    }
}

/// 使用量の多いアプリの一覧。メニューパネルとフローティングウィンドウで共用する
struct TopAppsView: View {
    let apps: [AppMemoryUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("使用量の多いアプリ")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help(
                        """
                        アクティビティモニタの「メモリ」列と同じ指標(phys_footprint)の合計です。
                        ヘルパープロセスは親アプリにまとめています。
                        他ユーザー所有のプロセスは権限の都合で取得できないため含まれません。
                        """)
            }
            // 合計が物理メモリを超えるのは驚かれる点なので、ホバーではなく常に見える形で示す
            Text("圧縮・スワップ済みを含むため、合計は物理メモリを超えることがあります")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(apps) { app in
                row(app)
            }
        }
    }

    private func row(_ app: AppMemoryUsage) -> some View {
        HStack(spacing: 6) {
            icon(for: app)
                .frame(width: 16, height: 16)
            Text(app.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(app.isGroupedOthers ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            Spacer(minLength: 8)
            Text(MemoryFormat.detail(app.footprint))
                .monospacedDigit()
                .foregroundStyle(app.isGroupedOthers ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .font(.callout)
        .help(helpText(for: app))
    }

    @ViewBuilder
    private func icon(for app: AppMemoryUsage) -> some View {
        // アイコンは描画時に引く。Sendable な集計結果に NSImage を持たせないため
        if let pid = app.pid, let image = AppIconCache.icon(for: pid) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: app.isGroupedOthers ? "ellipsis.circle" : "app.dashed")
                .foregroundStyle(.secondary)
        }
    }

    private func helpText(for app: AppMemoryUsage) -> String {
        app.isGroupedOthers
            ? "上位に入らなかったアプリと、アプリに属さないプロセス \(app.processCount) 件の合計"
            : "\(app.name) の \(app.processCount) プロセスの合計"
    }
}
