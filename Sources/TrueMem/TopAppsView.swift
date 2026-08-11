import AppKit
import SwiftUI

/// 使用量の多いアプリの一覧。メニューパネルとフローティングウィンドウで共用する
struct TopAppsView: View {
    let apps: [AppMemoryUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("使用量の多いアプリ")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                // 合計が物理メモリを超えることがあるため、その理由を常に添える
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help(
                        """
                        アクティビティモニタの「メモリ」列と同じ指標(phys_footprint)の合計です。
                        圧縮・スワップ済みの分を含むため、合計が物理メモリを超えることがあります。
                        他ユーザーやシステム所有のプロセスは取得できないため含まれません。
                        """)
            }
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
        if let pid = app.pid, let image = NSRunningApplication(processIdentifier: pid)?.icon {
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
