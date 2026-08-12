import AppKit
import SwiftUI

/// メニューバーアイコンをクリックしたときの詳細パネル
struct MenuContentView: View {
    let monitor: MemoryMonitor
    let updateController: UpdateController
    let floatingController: FloatingWindowController
    @State private var floatingVisible = false
    @AppStorage(MenuContentView.detailsExpandedKey) private var detailsExpanded = false
    @AppStorage(MenuContentView.settingsExpandedKey) private var settingsExpanded = false
    @State private var contentHeight: CGFloat = MenuContentView.fallbackPanelHeight
    @AppStorage(DisplayMode.defaultsKey) private var displayModeRaw = DisplayMode.default.rawValue

    /// 角丸の半径。
    /// システム描画時のパネルの角をピクセル単位で測ると 14pt だったが、
    /// 他アプリのパネルはそれより丸く見えるとの指摘を受けて一段大きくしている
    static let cornerRadius: CGFloat = 16
    /// 開閉状態の保存キー。テストからも参照できるよう定数にする
    static let detailsExpandedKey = "panelDetailsExpanded"
    static let settingsExpandedKey = "panelSettingsExpanded"
    /// 画面に対して残す余白。メニューバーと画面端に食い込ませない
    private static let screenMargin: CGFloat = 120
    /// 実測できるまでの高さ。既定はコンパクトなので、その実寸に近い値にしておく
    static let fallbackPanelHeight: CGFloat = 240

    /// 更新について利用者に伝えるべきことがあるか(更新あり・処理中・失敗)
    private var needsUpdateAttention: Bool {
        let state = updateController.state
        return state.availableRelease != nil || state.isBusy || state.failureDetail != nil
    }

    /// パネルの高さの上限。アプリ一覧や更新の詳細が加わると、
    /// 短い画面や拡大表示では画面高を超えて末尾が操作できなくなる
    private var maxPanelHeight: CGFloat {
        let usable = NSScreen.main?.visibleFrame.height ?? 800
        return max(320, usable - Self.screenMargin)
    }

    var body: some View {
        // MenuBarExtra(.window) は内容の固有サイズからパネルの大きさを決めるが、
        // ScrollView は縦の固有サイズを持たない。そのまま包むとパネルが潰れるため、
        // 内容の高さを実測して明示的に与える(Issue #41)
        ScrollView(.vertical) {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PanelContentHeightKey.self, value: proxy.size.height)
                    })
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 280)
        .frame(height: min(contentHeight, maxPanelHeight))
        .onPreferenceChange(PanelContentHeightKey.self) { height in
            // 0 を採用すると潰れるため、実測できるまでは既定値のままにする
            if height > 0 { contentHeight = height }
        }
        // 角丸をシステムの描画に任せると環境によって四角くなる(Issue #45)。
        // フローティングと同じく自前で描き、見た目も揃える
        .background(.regularMaterial)
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        // ホスト側のウィンドウが四角い背景を塗ると角丸が隠れるため透明にする
        .background(TransparentWindowBackground())
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = monitor.snapshot {
                // フローティングと同じ要約表示を使い、見た目を揃える
                MemorySummaryView(snapshot: snapshot) {
                    Image(systemName: "memorychip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                DisclosureHeader(title: "詳細", isExpanded: $detailsExpanded)
                if detailsExpanded {
                    MemoryDetailsView(snapshot: snapshot)
                    if !monitor.topApps.isEmpty {
                        Divider()
                        TopAppsView(apps: monitor.topApps)
                    }
                }
            } else {
                Text("計測に失敗しました")
                    .foregroundStyle(.secondary)
            }
            // 更新の状態は「設定」を畳んでいても見えるようにする。
            // 中に隠すと、確認やインストールの失敗が利用者に伝わらない
            if needsUpdateAttention {
                Divider()
                updates
            }
            Divider()
            DisclosureHeader(title: "設定", isExpanded: $settingsExpanded)
            if settingsExpanded {
                settings
                floating
                if !needsUpdateAttention {
                    Divider()
                    updates
                }
            }
            Divider()
            footer
        }
        .padding(12)
    }

    private var settings: some View {
        Picker("メニューバー表示", selection: $displayModeRaw) {
            ForEach(DisplayMode.allCases) { mode in
                Text(mode.label).tag(mode.rawValue)
            }
        }
        .font(.callout)
        // メニューバーの文字列は更新時にしか作られないため、切り替えを即座に反映させる
        .onChange(of: displayModeRaw) { monitor.refreshMenuBarText() }
    }

    private var floating: some View {
        HStack {
            Toggle("フローティング表示", isOn: $floatingVisible)
                .font(.callout)
                .toggleStyle(.checkbox)
                // パネルを開くたびに実際の状態へ合わせる
                .onAppear { floatingVisible = floatingController.isVisible }
                .onChange(of: floatingVisible) { floatingController.isVisible = floatingVisible }
            Spacer()
            // 見失ったときの復帰手段
            Button("位置を戻す") { floatingController.resetPosition() }
                .font(.callout)
                .disabled(!floatingVisible)
        }
    }

    private var updates: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("更新を確認") { updateController.check() }
                    .font(.callout)
                    .disabled(updateController.state.isBusy)
                Button("リリースページ") { updateController.openReleasePage() }
                    .font(.callout)
                Spacer()
                Text(updateController.state.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if updateController.state == .installing {
                // 上段のキャプションは幅が足りず切り詰められるため、
                // 進行中は専用の行で状態を示す
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("ダウンロードしてインストールしています…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // インストールはこのボタンを押したときにだけ実行する(この操作が同意そのもの)
            if let release = updateController.state.availableRelease {
                HStack {
                    Text("最新: \(Updater.shortCommit(release.commit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("インストールして再起動") {
                        updateController.installAvailableUpdate()
                    }
                    .font(.callout)
                    .buttonStyle(.borderedProminent)
                    .disabled(updateController.state.isBusy)
                }
            }
            if let detail = updateController.state.failureDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // gh の生出力がそのまま入ることがあるため、パネルが伸び続けないようにする
                    .lineLimit(3)
                    .help(detail)
            }
            Toggle("定期的に自動で確認", isOn: updateAutomaticallyBinding)
                .font(.callout)
                .toggleStyle(.checkbox)
            Toggle("更新を自動でインストール", isOn: automaticInstallBinding)
                .font(.callout)
                .toggleStyle(.checkbox)
                .disabled(!updateController.automaticChecksEnabled)
                .help("更新が見つかったら確認を挟まずインストールします。適用時にアプリが再起動します")
        }
    }

    private var updateAutomaticallyBinding: Binding<Bool> {
        Binding(
            get: { updateController.automaticChecksEnabled },
            set: { updateController.automaticChecksEnabled = $0 })
    }

    private var automaticInstallBinding: Binding<Bool> {
        Binding(
            get: { updateController.automaticInstallEnabled },
            set: { updateController.automaticInstallEnabled = $0 })
    }

    private var footer: some View {
        HStack {
            Text("v\(UpdateController.currentVersionLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("終了") { NSApp.terminate(nil) }
                .font(.callout)
        }
    }

}

/// パネル内容の実測高さを親へ伝える
private struct PanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// ホストしているウィンドウの背景を透明にする。
/// MenuBarExtra のパネルは環境によって四角い不透明背景を塗ることがあり、
/// そのままだと自前で描いた角丸が隠れてしまう(Issue #45)
private struct TransparentWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // ビュー階層に入るまで window は nil のため、次のループで適用する
        DispatchQueue.main.async { Self.makeTransparent(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.makeTransparent(nsView.window)
    }

    private static func makeTransparent(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}
