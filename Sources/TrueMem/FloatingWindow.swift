import AppKit
import SwiftUI

/// フローティングウィンドウの内容。
/// 常時表示に耐えるよう、要約と内訳の両方を1枚に収める。
/// 高さが足りないときは内訳から順に省き、要約は必ず残す
struct FloatingContentView: View {
    let monitor: MemoryMonitor
    /// 閉じるボタンの動作。ウィンドウを隠すだけでなく設定も切り替える
    let onClose: () -> Void
    /// 詳細の開閉が変わったときに、ウィンドウの高さを合わせるために呼ぶ
    let onDetailsToggled: (Bool) -> Void

    @AppStorage(FloatingWindowController.detailsExpandedKey) private var isExpanded = false

    var body: some View {
        GeometryReader { geometry in
            // 端数の高さでも末尾が読めるようにする
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if let snapshot = monitor.snapshot {
                        MemorySummaryView(
                            snapshot: snapshot, leadingAccessory: AnyView(closeButton))
                        Divider()
                        DisclosureHeader(title: "詳細", isExpanded: $isExpanded)
                        if isExpanded {
                            MemoryDetailsView(snapshot: snapshot)
                            if !monitor.topApps.isEmpty {
                                Divider()
                                TopAppsView(apps: monitor.topApps)
                            }
                        }
                    } else {
                        Text("計測に失敗しました")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(width: geometry.size.width, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(.regularMaterial)
        // 背景と同化して見失わないよう輪郭を明示する
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // タイトルバー領域を避けると上部に余白が残るため、全面に広げる
        .ignoresSafeArea()
        .onChange(of: isExpanded) { onDetailsToggled(isExpanded) }
    }

    private var closeButton: some View {
        // ホバーで出す方式はこのウィンドウが key にならないため確実性に欠ける。
        // 常時表示にして、押せることが常に分かるようにする
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("フローティング表示を閉じる")
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
    /// 詳細の開閉状態。パネルとは別に持つ(常時表示と都度確認で役割が異なるため)
    nonisolated static let detailsExpandedKey = "floatingDetailsExpanded"
    /// 要約のみの既定サイズ。既定はコンパクトに保つ
    nonisolated static let compactSize = NSSize(width: 300, height: 168)
    /// 詳細を開いたときの高さ(内訳7行 + アプリ一覧6行が収まる)
    nonisolated static let expandedHeight: CGFloat = 560
    nonisolated static var defaultSize: NSSize { compactSize }
    /// これ以上小さくすると要約すら読めなくなる
    nonisolated static let minimumSize = NSSize(width: 220, height: 130)

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
            rootView: FloatingContentView(
                monitor: monitor,
                onClose: { [weak self] in
                    // 設定ごと切り替える。次回起動時に勝手に復活させないため
                    self?.isVisible = false
                },
                onDetailsToggled: { [weak self] expanded in
                    self?.resizeForDetails(expanded: expanded)
                }))

        // 位置とサイズを記憶する
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        // 記憶した位置がどの画面にも無い場合(表示構成の変更など)は見失うため、既定位置へ戻す
        if panel.frame.origin == .zero || !Self.isOnAnyScreen(panel.frame) {
            Self.moveToDefaultPosition(panel)
        }
        // 詳細を開いた状態で起動したとき、記憶した高さが足りないと中身が収まらない。
        // 利用者が広げた高さは尊重したいので、足りないときだけ伸ばす
        let requiredHeight =
            UserDefaults.standard.bool(forKey: Self.detailsExpandedKey)
            ? Self.expandedHeight : Self.compactSize.height
        if panel.frame.height < requiredHeight {
            var frame = panel.frame
            let top = frame.maxY
            frame.size.height = requiredHeight
            frame.origin.y = top - requiredHeight
            panel.setFrame(frame, display: false)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// 詳細の開閉に合わせて高さを変える。上端を固定して下方向へ伸ばす
    private func resizeForDetails(expanded: Bool) {
        guard let panel else { return }
        let targetHeight =
            expanded
            ? Self.expandedHeight
            : Self.compactSize.height
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = targetHeight
        frame.origin.y = top - targetHeight
        panel.setFrame(frame, display: true, animate: true)
    }

    /// 見失ったときに呼び出して、既定のサイズと位置へ引き戻す
    func resetPosition() {
        guard let panel else { return }
        let expanded = UserDefaults.standard.bool(forKey: Self.detailsExpandedKey)
        panel.setContentSize(
            NSSize(
                width: Self.compactSize.width,
                height: expanded ? Self.expandedHeight : Self.compactSize.height))
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
