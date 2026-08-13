import AppKit
import SwiftUI

/// メニューバーアイコンをクリックしたときの詳細パネル
struct MenuContentView: View {
    let monitor: MemoryMonitor
    let updateController: UpdateController
    let loginItemController: LoginItemController
    let floatingController: FloatingWindowController
    @State private var floatingVisible = false
    @AppStorage(MenuContentView.detailsExpandedKey) private var detailsExpanded = false
    @AppStorage(MenuContentView.settingsExpandedKey) private var settingsExpanded = false
    @AppStorage(DisplayMode.defaultsKey) private var displayModeRaw = DisplayMode.default.rawValue

    /// 角丸の半径。
    /// システム描画時のパネルの角をピクセル単位で測ると 14pt だったが、
    /// 他アプリのパネルはそれより丸く見えるとの指摘を受けて一段大きくしている
    static let cornerRadius: CGFloat = 16
    /// 開閉状態の保存キー。テストからも参照できるよう定数にする
    static let detailsExpandedKey = "panelDetailsExpanded"
    static let settingsExpandedKey = "panelSettingsExpanded"
    /// 更新について利用者に伝えるべきことがあるか(更新あり・処理中・失敗)
    private var needsUpdateAttention: Bool {
        let state = updateController.state
        return state.availableRelease != nil || state.isBusy || state.failureDetail != nil
    }

    /// 内容の実測高さ。根の理想サイズと、ウィンドウへ反映する高さの両方の源
    @State private var contentHeight: CGFloat?
    /// パネルに使える高さの上限(内容座標系)。画面の可視領域から換算する。
    /// 分かるまでは制限しない
    @State private var heightBudget: CGFloat?

    /// 根とウィンドウに与える高さ。内容の実測を画面に収まる範囲へ丸める。
    /// 実測前は nil(制約しない)。
    /// 下限未満の値は contentHeight / heightBudget に入る前に捨てているので、
    /// ここで丸め上げはしない(丸め上げると、壊れた測定値を「100pt のパネル」
    /// という本物の目標に昇格させてしまう)
    private var resolvedHeight: CGFloat? {
        contentHeight.map { min($0, heightBudget ?? .infinity) }
    }

    var body: some View {
        // 画面に収まらないときだけスクロールで逃がす(#68)。
        //
        // ウィンドウの大きさは MenuBarExtra が根のビューへ「現在の大きさ」を
        // 提案し、返った答えを次の大きさとして保持する(#78 の実測)。
        // 提案をそのまま通す作り(素の ScrollView や min/max だけの frame)だと、
        // システムが保持している古い大きさを**こだまのように反射**して固定され、
        // 画面構成の変更などで狂った値が入るとウィンドウだけ大きいまま戻らなく
        // なる(v0.5.13 の症状)。理想サイズが不定だと 10pt で開くことも実測した。
        // 高さを実測値で**固定**し、どんな提案にも同じ答えを返すことで、
        // システム側の保持値をこちらの値へ収束させる
        ScrollView(.vertical) { sized }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: 280)
            .frame(height: resolvedHeight)
            // 角丸をシステムの描画に任せると環境によって四角くなる(Issue #45)。
            // ただし SwiftUI 側で形を描くとシステムの縁と二重になる(Issue #49)。
            // 縁を1本にするため、ウィンドウのレイヤー側だけで丸める
            .background(.regularMaterial)
            .background(RoundedWindowBackground(cornerRadius: Self.cornerRadius))
            // ウィンドウは内容が伸びる方向にしか追随しないことがある(Issue #71)。
            // 縮んだときに置いていかれると内容が切れたままになるため、
            // 実測した高さを反映する。受け付けられない場合は有限回で引き下がり、
            // 状況が変わったら挑み直す(HeightGovernor)
            .background(
                WindowHeightSync(
                    contentHeight: resolvedHeight,
                    onBudgetChange: { budget in
                        if heightBudget != budget { heightBudget = budget }
                    }))
    }

    /// 内容そのもの。実測した高さを contentHeight へ届ける。
    /// 測るのは器の ScrollView ではなく中身(器を測ると潰れる: Issue #41)。
    /// 壊れた測定値(下限未満)は捨てて、直前の正しい値を保つ
    private var sized: some View {
        content
            .frame(width: 280)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                guard height >= WindowHeightSync.minimumHeight else { return }
                if contentHeight != height { contentHeight = height }
            }
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
                loginItem
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
        Picker("表示する値", selection: $displayModeRaw) {
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

    private var loginItem: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("ログイン時に開く", isOn: loginItemBinding)
                .font(.callout)
                .toggleStyle(.checkbox)
            if let message = loginItemController.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(message)
            }
            if loginItemController.requiresApproval {
                Button("ログイン項目の設定を開く") {
                    loginItemController.openSystemSettings()
                }
                .font(.callout)
            }
        }
        // システム設定で切り替えた状態を、パネルを開き直したときに反映する。
        .onAppear { loginItemController.refresh() }
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { loginItemController.isEnabled },
            set: { loginItemController.setEnabled($0) })
    }

    private var updates: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ボタンと状態を同じ行に並べるとパネルの幅に収まらない。
            // 収まらない行があると内容全体の幅がそれに引きずられ、外側の
            // .frame(width:) が折り返しではなく切り落としとして働くため、
            // 失敗の理由と対処が読めなくなる(Issue #73)
            HStack {
                Button("更新を確認") { updateController.check() }
                    .font(.callout)
                    .disabled(updateController.state.isBusy)
                Button("リリースページ") { updateController.openReleasePage() }
                    .font(.callout)
                Spacer(minLength: 0)
            }
            // インストール中は次の行が進行を示すので、短い状態語は出さない
            if updateController.state != .installing, !updateController.state.message.isEmpty {
                Text(updateController.state.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if updateController.state == .installing {
                // 何が進んでいるのかを、短い状態語より具体的に示す
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
                    // 失敗の本文がそのまま入ることがあるため、パネルが伸び続けないようにする。
                    // 折り返させないと1行で切れて対処方法が読めない(Issue #73)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
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


/// ウィンドウの高さ要求の判断。
/// 「同じ高さを繰り返し要求して AppKit と喧嘩し続けない」ことと、
/// 「一度諦めても状況が変われば立て直す」ことを両立させる(#71, #78)。
/// 高さはいずれもウィンドウのフレーム基準
final class HeightGovernor {
    /// 同じ目標を続けて要求する上限。受け付けられない場合に無限に往復しない
    static let maxAttempts = 3
    /// これ以下の差は見えず、往復の原因にしかならない
    static let tolerance: CGFloat = 0.5

    /// 直前に要求した高さ
    private var requested: CGFloat?
    private var attempts = 0
    /// 直前に要求したときのウィンドウの高さ。ここから動いていたら
    /// 「外から動かされた」= 諦めの根拠が古い、と判断する
    private var baseline: CGFloat?

    /// 適用すべき高さを返す。nil は「何もしない」
    func decide(current: CGFloat, target: CGFloat) -> CGFloat? {
        guard target >= WindowHeightSync.minimumHeight else { return nil }
        // 一致したら要求の記録を消す。消さないと同じ高さへ二度と
        // 戻せなくなる(#71 で「2回目の折りたたみが効かない」として実際に起きた)
        if abs(current - target) <= Self.tolerance {
            requested = nil
            attempts = 0
            baseline = nil
            return nil
        }
        // 要求後にウィンドウが外から動いた(解像度変更・システムの再配置)なら、
        // 諦めの根拠が古いので数え直す。恒久的に諦めると、システムが
        // 大きくしたウィンドウを直す機会が二度と来ない(#78)
        if let baseline, abs(current - baseline) > Self.tolerance {
            requested = nil
            attempts = 0
        }
        if let requested, abs(requested - target) <= Self.tolerance {
            guard attempts < Self.maxAttempts else { return nil }
            attempts += 1
        } else {
            requested = target
            attempts = 1
        }
        baseline = current
        return target
    }
}

/// 実測した内容の高さをウィンドウへ反映し、パネルに使える高さを報告する。
///
/// `MenuBarExtra(.window)` のウィンドウは、この経路では**大きくなる方向にしか**
/// 内容に追随しない(実測: 詳細を開いたままパネルを閉じると、以後ずっと
/// 開いた分の高さのまま残り、開き直しても戻らない: #71)。さらに画面構成が
/// 変わると、システム側がウィンドウを内容と無関係な大きさへ再配置することが
/// ある(#78)。どちらも実測高さを直接反映して立て直す
struct WindowHeightSync: NSViewRepresentable {
    /// 反映したい高さ(内容座標系。画面の上限で丸めた後の値)。実測前は nil
    let contentHeight: CGFloat?
    /// パネルに使える高さ(内容座標系)が分かる・変わるたびに呼ばれる
    let onBudgetChange: (CGFloat) -> Void

    /// これを下回る測定値は反映しない。
    /// 測定が壊れたときにウィンドウを潰さないための歯止め(Issue #41 の再発防止)
    nonisolated static let minimumHeight: CGFloat = 100

    /// 上端を固定して下方向に伸縮させたフレーム。
    /// メニューバーの下に貼り付いた位置を動かさないため。
    /// 画面からはみ出すとパネルはスクロールできないので下端に手が届かなくなる。
    /// 収まらないなら可視領域までに留める(Issue #68 と同じ制約)
    nonisolated static func frame(current: NSRect, height: CGFloat, within visible: NSRect)
        -> NSRect
    {
        let limited = min(height, visible.height)
        var frame = NSRect(
            x: current.minX, y: current.maxY - limited, width: current.width, height: limited)
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - limited }
        return frame
    }

    func makeNSView(context: Context) -> ScreenAwareView { ScreenAwareView() }

    func updateNSView(_ view: ScreenAwareView, context: Context) {
        view.contentHeight = contentHeight
        view.onBudgetChange = onBudgetChange
        // 更新の途中ではウィンドウの大きさがまだ変わっていないため、
        // レイアウトが落ち着く次のループで見る
        DispatchQueue.main.async { [weak view] in view?.sync() }
    }

    /// 登録した観測を寿命に合わせて確実に外すための持ち手。
    /// (MainActor 隔離のビューは deinit から自分のプロパティへ触れないため)
    private final class ObservationHolder {
        private let token: NSObjectProtocol
        init(_ token: NSObjectProtocol) { self.token = token }
        deinit { NotificationCenter.default.removeObserver(token) }
    }

    /// ウィンドウを持つ側の実務。画面構成の変更もここで受ける
    final class ScreenAwareView: NSView {
        var contentHeight: CGFloat?
        var onBudgetChange: ((CGFloat) -> Void)?
        let governor = HeightGovernor()
        private var screenObservation: ObservationHolder?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // 解像度や画面の増減はイベントで知る。1秒ごとの再計算だけに頼ると、
            // 変化の直後に古い可視領域で丸めた結果がしばらく残る(#78)
            guard window != nil, screenObservation == nil else { return }
            screenObservation = ObservationHolder(
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in
                    // queue: .main でもコンパイラ上は MainActor と同値ではないため、
                    // 仮定(assumeIsolated)ではなくホップで渡す
                    Task { @MainActor in self?.sync() }
                })
        }

        func sync() {
            guard let window, window.isVisible else { return }
            let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            if let visible {
                // パネルに使える内容の高さ。タイトルバー等の分を除いて伝える。
                // 画面遷移中の壊れた値(下限未満)で根を潰さないよう、伝えない
                let budget = window.contentRect(
                    forFrameRect: NSRect(
                        x: 0, y: 0, width: window.frame.width, height: visible.height)
                ).height
                if budget >= WindowHeightSync.minimumHeight { onBudgetChange?(budget) }
            }
            guard let contentHeight else { return }
            // 測っているのは内容の高さ。タイトルバー等がある窓でもずれないよう、
            // フレーム基準へ変換してから比べる
            let target = window.frameRect(
                forContentRect: NSRect(
                    x: 0, y: 0, width: window.frame.width, height: contentHeight)
            ).height
            // 判定も記録も丸めた後の高さで行う。丸める前の値で記録すると、
            // 画面に収まらない間は現在値と一致しないまま記録だけが残り、
            // 後から可視領域が広がっても伸び直せなくなる
            let clamped = visible.map { min(target, $0.height) } ?? target
            guard let height = governor.decide(current: window.frame.height, target: clamped)
            else { return }
            window.setFrame(
                WindowHeightSync.frame(
                    current: window.frame, height: height,
                    within: visible ?? window.frame.insetBy(dx: 0, dy: -height)),
                display: true)
        }
    }
}

/// ホストしているウィンドウを透明にし、角丸マスクを適用する。
///
/// SwiftUI 側で `clipShape` と `strokeBorder` を重ねると、システムが描く縁と
/// 二重の輪郭になる(Issue #49)。レイヤー側だけで丸めることで縁を1本にする
private struct RoundedWindowBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // ビュー階層に入るまで window は nil のため、次のループで適用する
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView.window)
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = cornerRadius
        contentView.layer?.masksToBounds = true
        // 角の曲がり方をシステムの窓と揃える
        contentView.layer?.cornerCurve = .continuous
    }
}
