import AppKit
import SwiftUI

/// フローティングウィンドウの内容。
/// 既定は要約のみのコンパクト表示。「詳細」を開くと内訳とアプリ一覧が加わる
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
                        MemorySummaryView(snapshot: snapshot) { closeButton }
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
        .overlay(
            RoundedRectangle(cornerRadius: MenuContentView.cornerRadius)
                .strokeBorder(.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: MenuContentView.cornerRadius))
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
    nonisolated static let frameAutosaveName = "MemoryBarFloatingWindow"
    /// 詳細の開閉状態。パネルとは別に持つ(常時表示と都度確認で役割が異なるため)
    nonisolated static let detailsExpandedKey = "floatingDetailsExpanded"
    /// 状態ごとの高さ。開閉を往復しても利用者が決めた大きさを失わないため
    nonisolated static let compactHeightKey = "floatingCompactHeight"
    nonisolated static let expandedHeightKey = "floatingExpandedHeight"
    /// 表示項目を増減したら上げる。上げた版で一度だけ記憶した高さを捨てる
    nonisolated static let layoutVersion = 2
    nonisolated static let layoutVersionKey = "floatingLayoutVersion"
    /// 要約のみの既定サイズ。既定はコンパクトに保つ。
    /// 総量・使用量・利用可能の3行を含めた実測値(Issue #66)
    nonisolated static let compactSize = NSSize(width: 300, height: 236)
    /// 詳細を開いたときの高さ(内訳7行 + アプリ一覧6行が収まる)
    nonisolated static let expandedHeight: CGFloat = 620
    nonisolated static var defaultSize: NSSize { compactSize }
    /// これ以上小さくすると要約すら読めなくなる
    nonisolated static let minimumSize = NSSize(width: 240, height: 180)

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
        // NSHostingView をそのまま contentView にすると、Auto Layout で
        // ウィンドウの大きさが内容に支配される。根が GeometryReader で固有サイズを
        // 持たないため最小値に張り付くので、器に載せて追従だけさせる(Issue #66)
        let hosting = NSHostingView(
            rootView: FloatingContentView(
                monitor: monitor,
                onClose: { [weak self] in
                    // 設定ごと切り替える。次回起動時に勝手に復活させないため
                    self?.isVisible = false
                },
                onDetailsToggled: { [weak self] expanded in
                    self?.resizeForDetails(expanded: expanded)
                }))
        let container = NSView(frame: NSRect(origin: .zero, size: Self.defaultSize))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        panel.setContentSize(Self.defaultSize)

        // 位置とサイズを記憶する
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        // 記憶した位置がどの画面にも無い場合(表示構成の変更など)は見失うため、既定位置へ戻す
        if panel.frame.origin == .zero || !Self.isOnAnyScreen(panel.frame) {
            Self.moveToDefaultPosition(panel)
        }
        // 表示項目を変えた版の初回だけ、記憶を捨てて必要量まで広げる。
        // 縮めはしないので、利用者が広げていた大きさは残る
        let expanded = UserDefaults.standard.bool(forKey: Self.detailsExpandedKey)
        if Self.consumeLayoutChange() {
            let visible = Self.visibleFrame(containing: panel.frame)
            panel.setFrame(
                Self.grownFrame(for: expanded, current: panel.frame, within: visible),
                display: false)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// 詳細の開閉に合わせて高さを変える。
    /// 状態ごとに高さを覚えるので、利用者がどちらかで広げてもそれを失わない
    private func resizeForDetails(expanded: Bool) {
        guard let panel else { return }
        // 切り替える前の状態の高さを覚えておく
        Self.storeHeight(panel.frame.height, expanded: !expanded)
        let visible = Self.visibleFrame(containing: panel.frame)
        let target = Self.frame(
            for: expanded, current: panel.frame, storedHeight: Self.storedHeight(expanded: expanded),
            within: visible)
        // animate: true は表示中のウィンドウで約0.35秒メインスレッドを止め、
        // その間 1秒更新もメニューバーの文字列も停止するため使わない
        panel.setFrame(target, display: true)
    }

    /// 表示項目を変えた版で最初に呼ばれたときだけ true を返し、記憶した高さを捨てる。
    ///
    /// 更新で行が増えても記憶した高さはそのままなので、以前の高さで復元すると
    /// 増えた行が隠れる。かといって毎回必要量まで広げると、利用者が意図して
    /// 小さくした窓を起動のたびに押し戻してしまう。変えた回だけに限る
    @discardableResult
    nonisolated static func consumeLayoutChange(_ defaults: UserDefaults = .standard) -> Bool {
        guard defaults.integer(forKey: layoutVersionKey) != layoutVersion else { return false }
        defaults.set(layoutVersion, forKey: layoutVersionKey)
        defaults.removeObject(forKey: compactHeightKey)
        defaults.removeObject(forKey: expandedHeightKey)
        return true
    }

    /// 状態ごとに記憶した高さ。無ければ nil
    nonisolated static func storedHeight(expanded: Bool) -> CGFloat? {
        let key = expanded ? expandedHeightKey : compactHeightKey
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? CGFloat(value) : nil
    }

    nonisolated static func storeHeight(_ height: CGFloat, expanded: Bool) {
        UserDefaults.standard.set(
            Double(height), forKey: expanded ? expandedHeightKey : compactHeightKey)
    }

    /// 開閉後のフレームを求める。
    ///
    /// - 上端を固定して下方向へ伸縮する(置いた位置がずれないようにする)
    /// - その状態で記憶した高さがあればそれを使う。利用者がどちらの状態で
    ///   広げても、開閉を往復して失われないようにする
    /// - 画面の可視領域からはみ出さないよう収める。AppKit の自動補正は
    ///   上端しか守らないため、下端は自分で見る必要がある
    nonisolated static func frame(
        for expanded: Bool, current: NSRect, storedHeight: CGFloat? = nil, within visible: NSRect
    ) -> NSRect {
        let fallback = expanded ? expandedHeight : compactSize.height
        // 記憶が無い場合も、展開なら現在より縮めない(中身が収まらなくなるため)
        let desired = storedHeight ?? (expanded ? max(current.height, fallback) : fallback)
        var frame = current
        let top = current.maxY
        frame.size.height = min(desired, max(minimumSize.height, visible.height))
        frame.origin.y = top - frame.size.height
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.size.height }
        return frame
    }

    /// 表示項目を変えた版の初回に使うフレーム。
    /// 増えた行が隠れないよう必要量までは広げるが、利用者が広げていた窓は縮めない
    nonisolated static func grownFrame(for expanded: Bool, current: NSRect, within visible: NSRect)
        -> NSRect
    {
        let required = expanded ? expandedHeight : compactSize.height
        return frame(
            for: expanded, current: current, storedHeight: max(current.height, required),
            within: visible)
    }

    /// ウィンドウが最も重なっている画面の可視領域
    nonisolated static func visibleFrame(containing frame: NSRect) -> NSRect {
        let screen =
            NSScreen.screens.max {
                $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area
            } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
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

extension NSRect {
    /// 重なりの大きさ比較用。空の交差は 0 になる
    fileprivate var area: CGFloat { isEmpty ? 0 : width * height }
}
