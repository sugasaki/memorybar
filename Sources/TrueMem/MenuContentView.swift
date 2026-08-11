import AppKit
import SwiftUI

/// メニューバーアイコンをクリックしたときの詳細パネル
struct MenuContentView: View {
    let monitor: MemoryMonitor
    @AppStorage("displayMode") private var displayModeRaw = DisplayMode.default.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = monitor.snapshot {
                header(snapshot)
                Divider()
                rows(snapshot)
            } else {
                Text("計測に失敗しました")
                    .foregroundStyle(.secondary)
            }
            Divider()
            settings
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 280)
    }

    private func header(_ snapshot: MemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("メモリ").font(.headline)
                Spacer()
                Text("物理 \(MemoryFormat.detail(snapshot.total))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: snapshot.usedFraction)
                .tint(pressureColor(snapshot.pressure))
        }
    }

    private func rows(_ snapshot: MemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row("使用済みメモリ", MemoryFormat.detail(snapshot.used), bold: true)
            subRow("アプリメモリ", MemoryFormat.detail(snapshot.appMemory))
            subRow("確保済みメモリ", MemoryFormat.detail(snapshot.wired))
            subRow("圧縮", MemoryFormat.detail(snapshot.compressed))
            row("キャッシュされたファイル", MemoryFormat.detail(snapshot.cachedFiles))
            row("使用済みスワップ", snapshot.swapUsed.map(MemoryFormat.detail) ?? "--")
            row("残容量", MemoryFormat.detail(snapshot.available), bold: true)
            HStack {
                Text("メモリプレッシャー")
                Spacer()
                Circle()
                    .fill(pressureColor(snapshot.pressure))
                    .frame(width: 8, height: 8)
                Text(snapshot.pressure.label)
                    .monospacedDigit()
            }
            .font(.callout)
        }
    }

    private var settings: some View {
        Picker("メニューバー表示", selection: $displayModeRaw) {
            ForEach(DisplayMode.allCases) { mode in
                Text(mode.label).tag(mode.rawValue)
            }
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            Text("約2秒ごとに更新")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("終了") { NSApp.terminate(nil) }
                .font(.callout)
        }
    }

    private func row(_ title: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(bold ? .callout.weight(.semibold) : .callout)
    }

    private func subRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.callout)
        .padding(.leading, 12)
    }

    private func pressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        case .unknown: .gray
        }
    }
}
