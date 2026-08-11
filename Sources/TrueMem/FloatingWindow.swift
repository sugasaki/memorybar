import AppKit
import SwiftUI

/// フローティングウィンドウに出す要約表示。
/// 詳細パネルと違い、離れた位置から一目で読めることを優先する
struct FloatingContentView: View {
    let monitor: MemoryMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snapshot = monitor.snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(MemoryFormat.detail(snapshot.available))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("空き")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(pressureColor(snapshot.pressure))
                        .frame(width: 8, height: 8)
                    Text(snapshot.pressure.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // ProgressView は非アクティブウィンドウで tint が退色し灰色に見えるため、
                // フローティング側では自前で描く(このウインドウは key にならない)
                usageBar(snapshot)
                HStack {
                    Text("使用済み \(MemoryFormat.detail(snapshot.used))")
                    Spacer(minLength: 8)
                    Text("\(Int((snapshot.usedFraction * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("計測に失敗しました")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 200)
        // 背景のどこを掴んでも動かせるようにするため、内容側でクリックを奪わない
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func usageBar(_ snapshot: MemorySnapshot) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(usageBarTint(snapshot.pressure))
                    .frame(width: geometry.size.width * snapshot.usedFraction)
            }
        }
        .frame(height: 6)
    }

    private func usageBarTint(_ pressure: MemoryPressure) -> Color {
        pressure == .unknown ? .blue : pressureColor(pressure)
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

/// フローティングウィンドウの生成・表示・位置記憶をまとめる。
/// `NSPanel` を直接扱うため SwiftUI の `Window` シーンは使わない
/// (`.accessory` なアプリでも前面に出し、全スペースへ追従させたいため)
@MainActor
final class FloatingWindowController {
    static let defaultsKey = "floatingWindowVisible"
    private static let frameAutosaveName = "TrueMemFloatingWindow"

    private var panel: NSPanel?
    private let monitor: MemoryMonitor

    init(monitor: MemoryMonitor) {
        self.monitor = monitor
    }

    var isVisible: Bool {
        get { UserDefaults.standard.bool(forKey: Self.defaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.defaultsKey)
            apply(visible: newValue)
        }
    }

    /// 起動時に前回の状態を復元する
    func restore() {
        apply(visible: isVisible)
    }

    private func apply(visible: Bool) {
        if visible {
            show()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 96),
            // .titled にするとタイトルバーの高さぶん余白が残るため borderless にする。
            // 背景ドラッグで動かせるので操作性は損なわれない
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // 他アプリの前面に出す。.floating は通常ウィンドウより上、メニューより下
        panel.level = .floating
        // canJoinAllSpaces でスペースを移動しても付いてくる。
        // fullScreenAuxiliary は他アプリのフルスクリーン中も表示させるため
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // .accessory なアプリでもクリックでアプリを前面化させない
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: FloatingContentView(monitor: monitor))
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 200, height: 96))

        // 位置を記憶する。初回は右上寄りに置く
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: visible.maxX - panel.frame.width - 24,
                    y: visible.maxY - panel.frame.height - 24))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
