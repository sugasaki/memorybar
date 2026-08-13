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

    var body: some View {
        // 画面に収まらないときだけスクロールで逃がす。
        // 高さを決めるのは中の内容の実測値(sized)のままで、ScrollView は
        // 器としてかぶせるだけ。ScrollView 自体を測ると縦の固有サイズが無く
        // 潰れるため(Issue #41)、測る対象は変えないこと
        ScrollView(.vertical) { sized }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: 280)
            // 角丸をシステムの描画に任せると環境によって四角くなる(Issue #45)。
            // ただし SwiftUI 側で形を描くとシステムの縁と二重になる(Issue #49)。
            // 縁を1本にするため、ウィンドウのレイヤー側だけで丸める
            .background(.regularMaterial)
            .background(RoundedWindowBackground(cornerRadius: Self.cornerRadius))
    }

    /// 内容と、その実測高さをウィンドウへ伝える仕掛け
    private var sized: some View {
        content
            .frame(width: 280)
            // ウィンドウは内容が伸びる方向にしか追随しないことがある(Issue #71)。
            // 縮んだときに置いていかれると、大きいままのウィンドウの中に
            // 内容が浮いて二重の矩形に見えるため、実測した高さを反映する。
            // 画面に収まらないぶんは WindowHeightSync 側で切り詰められ、
            // その差は上の ScrollView が引き受ける(Issue #68)
            .background(
                GeometryReader { geometry in
                    WindowHeightSync(height: geometry.size.height)
                })
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


/// 実測した内容の高さをウィンドウへ反映する。
///
/// `MenuBarExtra(.window)` のウィンドウは、この経路では**大きくなる方向にしか**
/// 内容に追随しない(実測: 詳細を開いたままパネルを閉じると、以後ずっと
/// 開いた分の高さのまま残り、開き直しても戻らない)。#55 でスクロールを外して
/// 「大きさは内容に任せる」方式にしたため、追随しないと差分がそのまま見える
struct WindowHeightSync: NSViewRepresentable {
    let height: CGFloat

    /// これを下回る測定値は反映しない。
    /// 測定が壊れたときにウィンドウを潰さないための歯止め(Issue #41 の再発防止)
    nonisolated static let minimumHeight: CGFloat = 100

    /// 次に何をするか
    enum Action: Equatable {
        /// 何もしない
        case none
        /// 一致しているので、要求済みの記録を消す。
        /// 同じ高さを次に要求できるようにするため(消さないと2回目の折りたたみが効かない)
        case clearRequest
        /// この高さを要求する
        case apply(CGFloat)
    }

    /// 現在の高さ・望む高さ・直前に要求した高さから、次の動作を決める。
    /// 高さはいずれもウィンドウのフレーム基準(内容基準ではない)
    nonisolated static func action(current: CGFloat, target: CGFloat, requested: CGFloat?)
        -> Action
    {
        // 0.5pt 未満の差は見えず、往復の原因にしかならない
        guard abs(current - target) > 0.5 else {
            return requested == nil ? .none : .clearRequest
        }
        guard target >= minimumHeight else { return .none }
        // 同じ高さを繰り返し要求するのは、AppKit 側が受け付けていない場合。
        // 何度も設定し直しても直らないので諦める(無限ループを避ける)。
        // 一度でも一致すれば上の分岐で記録が消えるので、諦めが恒久化はしない
        if let requested, abs(requested - target) < 0.5 { return .none }
        return .apply(target)
    }

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

    final class Coordinator {
        /// 直前に要求した高さ(ウィンドウのフレーム基準)
        var requested: CGFloat?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 明らかに使えない測定値は、非同期ホップを積む前に捨てる
        guard height >= Self.minimumHeight else { return }
        let contentHeight = height
        let coordinator = context.coordinator
        // 更新の途中ではウィンドウの大きさがまだ変わっていないため、
        // レイアウトが落ち着く次のループで見る
        DispatchQueue.main.async {
            guard let window = nsView.window, window.isVisible else { return }
            // 測っているのは内容の高さ。タイトルバー等がある窓でもずれないよう、
            // フレーム基準へ変換してから比べる
            let natural = window.frameRect(
                forContentRect: NSRect(x: 0, y: 0, width: window.frame.width, height: contentHeight)
            ).height
            // 判定も記録も**丸めた後の高さ**で行う。丸める前の値を記録すると、
            // 画面に収まらない間は現在値と一致しないまま記録だけが残り、
            // 後から可視領域が広がっても伸び直せなくなる(解像度変更・別画面へ移動)
            let visible =
                window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
                ?? window.frame.insetBy(dx: 0, dy: -natural)
            let targetFrame = Self.frame(current: window.frame, height: natural, within: visible)
            switch Self.action(
                current: window.frame.height, target: targetFrame.height,
                requested: coordinator.requested)
            {
            case .none:
                break
            case .clearRequest:
                coordinator.requested = nil
            case .apply(let height):
                coordinator.requested = height
                window.setFrame(targetFrame, display: true)
            }
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
