import AppKit
import SwiftUI

/// メニューバーアイコンをクリックしたときの詳細パネル
struct MenuContentView: View {
    let monitor: MemoryMonitor
    let updateController: UpdateController
    let floatingController: FloatingWindowController
    @State private var floatingVisible = false
    @AppStorage(DisplayMode.defaultsKey) private var displayModeRaw = DisplayMode.default.rawValue

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
            floating
            Divider()
            updates
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
                .tint(usageBarTint(snapshot.pressure))
        }
    }

    private func rows(_ snapshot: MemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row("使用済みメモリ", MemoryFormat.detail(snapshot.used), bold: true)
            subRow("アプリメモリ", MemoryFormat.detail(snapshot.appMemory))
            subRow("確保済みメモリ", MemoryFormat.detail(snapshot.wired))
            subRow("圧縮", MemoryFormat.detail(snapshot.compressed))
            // 内訳の合計が使用済みと一致するよう、どのカテゴリにも入らない分を示す
            subRow("その他", MemoryFormat.detail(snapshot.other))
            row("キャッシュされたファイル", MemoryFormat.detail(snapshot.cachedFiles))
            row("未使用", MemoryFormat.detail(snapshot.unused))
            row("使用済みスワップ", MemoryFormat.detail(snapshot.swapUsed))
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
            Toggle("起動時に自動で確認", isOn: updateAutomaticallyBinding)
                .font(.callout)
                .toggleStyle(.checkbox)
        }
    }

    private var updateAutomaticallyBinding: Binding<Bool> {
        Binding(
            get: { updateController.automaticChecksEnabled },
            set: { updateController.automaticChecksEnabled = $0 })
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

    /// 使用率バーの色。プレッシャーが取得不能でも使用率自体は有効な値なので、
    /// バーまで灰色にして「値が取れていない」と誤読させない。
    /// アクセントカラーはユーザー設定で灰色(グラファイト)や赤にできてしまうため使わない
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
