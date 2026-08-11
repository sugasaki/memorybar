import AppKit
import SwiftUI

/// フローティングウィンドウの内容。
/// 常時表示に耐えるよう、要約と内訳の両方を1枚に収める。
/// 高さが足りないときは内訳から順に省き、要約は必ず残す
struct FloatingContentView: View {
    let monitor: MemoryMonitor
    /// 閉じるボタンの動作。ウィンドウを隠すだけでなく設定も切り替える
    let onClose: () -> Void

    /// この高さを下回ったら内訳を省く(要約だけでも読めるようにする)
    private static let breakdownMinHeight: CGFloat = 210

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 10) {
                if let snapshot = monitor.snapshot {
                    header(snapshot)
                    summary(snapshot)
                    CompositionBar(snapshot: snapshot)
                    if geometry.size.height >= Self.breakdownMinHeight {
                        Divider()
                        breakdown(snapshot)
                    }
                    Spacer(minLength: 0)
                } else {
                    Text("計測に失敗しました")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(.regularMaterial)
        // 背景と同化して見失わないよう輪郭を明示する
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // タイトルバー領域を避けると上部に余白が残るため、全面に広げる
        .ignoresSafeArea()
    }

    private func header(_ snapshot: MemorySnapshot) -> some View {
        HStack(spacing: 6) {
            // ホバーで出す方式はこのウィンドウが key にならないため確実性に欠ける。
            // 常時表示にして、押せることが常に分かるようにする
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("フローティング表示を閉じる")
            Text("TrueMem")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Circle()
                .fill(pressureColor(snapshot.pressure))
                .frame(width: 9, height: 9)
            Text(snapshot.pressure.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func summary(_ snapshot: MemorySnapshot) -> some View {
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
    }

    /// 帯と同じ順序・同じ色で並べる。凡例と内訳を兼ねる
    private func breakdown(_ snapshot: MemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
        }
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

/// フローティングウィンドウの生成・表示・位置とサイズの記憶をまとめる。
/// `NSPanel` を直接扱うため SwiftUI の `Window` シーンは使わない
/// (`.accessory` なアプリでも前面に出し、全スペースへ追従させたいため)
@MainActor
final class FloatingWindowController {
    // テストや CLI から非 MainActor でも読めるようにする(値を持つだけで状態はない)
    nonisolated static let defaultsKey = "floatingWindowVisible"
    nonisolated static let frameAutosaveName = "TrueMemFloatingWindow"
    /// 内訳まで収まる既定サイズ
    nonisolated static let defaultSize = NSSize(width: 300, height: 286)
    /// これ以上小さくすると要約すら読めなくなる
    nonisolated static let minimumSize = NSSize(width: 220, height: 118)

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
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            // borderless では枠をドラッグしてもリサイズできないため .titled を使う。
            // タイトルバーは透明化して隠し、fullSizeContentView で内容を全面に広げる
            styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = Self.minimumSize
        // 他アプリの前面に出す。.floating は通常ウィンドウより上、メニューより下
        panel.level = .floating
        // canJoinAllSpaces でスペースを移動しても付いてくる。
        // fullScreenAuxiliary は他アプリのフルスクリーン中も表示させるため
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // .accessory なアプリでもクリックでアプリを前面化させない
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(
            rootView: FloatingContentView(monitor: monitor) { [weak self] in
                // 設定ごと切り替える。次回起動時に勝手に復活させないため
                self?.isVisible = false
            })

        // 位置とサイズを記憶する
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        // 記憶した位置がどの画面にも無い場合(表示構成の変更など)は見失うため、既定位置へ戻す
        if panel.frame.origin == .zero || !Self.isOnAnyScreen(panel.frame) {
            Self.moveToDefaultPosition(panel)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// 見失ったときに呼び出して、既定のサイズと位置へ引き戻す
    func resetPosition() {
        guard let panel else { return }
        panel.setContentSize(Self.defaultSize)
        Self.moveToDefaultPosition(panel)
        panel.orderFrontRegardless()
    }

    /// ウィンドウの一部でも可視領域に重なっているか。完全に画面外なら操作できない
    nonisolated static func isOnAnyScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    private static func moveToDefaultPosition(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: visible.maxX - panel.frame.width - 24,
                y: visible.maxY - panel.frame.height - 24))
    }
}
