import AppKit
import Dispatch
import SwiftUI

/// Swift 6.1では@MainActorクラスのdeinitが非分離のため、
/// ライフサイクル資源を非Actorの専用ホルダーへまとめて確実に停止する。
private final class MemoryMonitorResources: @unchecked Sendable {
    var pressureSource: DispatchSourceMemoryPressure?
    var timer: Timer?

    deinit {
        timer?.invalidate()
        pressureSource?.cancel()
    }
}

@main
enum Main {
    static func main() {
        // 取り違えると意図しない副作用(インストール)が起きるため、併用は明示的に拒否する
        if CommandLine.arguments.contains("--check-update"),
            CommandLine.arguments.contains("--install-update")
        {
            FileHandle.standardError.write(
                Data("--check-update と --install-update は同時に指定できません\n".utf8))
            exit(64)
        }
        // 検証用: --printで1サンプルを標準出力に出して終了する
        if CommandLine.arguments.contains("--print") {
            printSample()
            return
        }
        // 検証用: 使用量の多いアプリを標準出力に出す
        if CommandLine.arguments.contains("--apps") {
            printTopApps()
            return
        }
        // 検証用: 更新確認だけを行って結果を標準出力に出す(インストールはしない)
        if CommandLine.arguments.contains("--check-update") {
            printUpdateStatus()
            return
        }
        // 検証用: 更新があれば実際にインストールする。
        // GUI ではパネルのボタン操作が同意にあたるが、ここでは実行自体が同意にあたる
        if CommandLine.arguments.contains("--install-update") {
            installUpdateFromCLI()
            return
        }
        MemoryBarApp.main()
    }

    private static func installUpdateFromCLI() {
        // 差し替えスクリプトは「起動元プロセスの終了」を待つ。CLI から実行すると
        // 待つ相手が CLI 自身になるため、常駐中の GUI があるとその実行中バンドルを
        // 上書きしてしまう(利用者には旧版が動いたままに見える)
        if let running = otherRunningInstance() {
            FileHandle.standardError.write(
                Data(
                    """
                    MemoryBar が起動中のため実行できません (pid=\(running))。
                    メニューの「インストールして再起動」を使うか、先に MemoryBar を終了してください。

                    """.utf8))
            exit(1)
        }
        do {
            let release = try Updater.fetchLatestRelease()
            guard Updater.isUpdateAvailable(release) else {
                print("更新はありません(現在: \(UpdateController.currentVersionLabel))")
                return
            }
            print("インストールします: \(Updater.shortCommit(release.commit))")
            // 成功するとプロセスが終了するため、以降は実行されない
            try Updater.downloadAndInstall(release)
        } catch let error as Updater.UpdateError {
            let detail = [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }.joined(separator: " / ")
            FileHandle.standardError.write(Data("\(detail)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    /// 自分以外に同じアプリが動いていれば、その pid を返す
    private static func otherRunningInstance() -> pid_t? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .map(\.processIdentifier)
            .first { $0 != selfPID }
    }

    @MainActor
    private static func printTopApps() {
        let apps = ProcessSampler.topApps()
        guard !apps.isEmpty else {
            FileHandle.standardError.write(Data("プロセス情報を取得できませんでした\n".utf8))
            exit(1)
        }
        // %s は日本語を含む文字列で空欄になるため自前で揃える。
        // padding(toLength:) は UTF-16 長で数えるため絵文字などで切り詰められる。
        // 全角の表示幅も考慮し、幅を数えて空白を足す
        func displayWidth(_ text: String) -> Int {
            text.unicodeScalars.reduce(0) { width, scalar in
                // 全角・絵文字はおおむね2列分を占める
                switch scalar.value {
                case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3,
                    0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60,
                    0xFFE0...0xFFE6, 0x1F300...0x1FAFF:
                    return width + 2
                default:
                    return width + 1
                }
            }
        }
        let nameWidth = max(28, apps.map { displayWidth($0.name) }.max() ?? 0)
        for app in apps {
            let padding = String(repeating: " ", count: max(1, nameWidth - displayWidth(app.name)))
            print(
                "\(app.name)\(padding)  \(MemoryFormat.detail(app.footprint))  (\(app.processCount) プロセス)"
            )
        }
        let total = apps.reduce(UInt64(0)) { $0 + $1.footprint }
        print("合計: \(MemoryFormat.detail(total))  ※圧縮・スワップ済みを含むため物理メモリを超えうる")
    }

    private static func printUpdateStatus() {
        print("現在のビルド: \(UpdateController.currentVersionLabel)")
        print("取得元: \(Updater.releaseAPIURL.absoluteString)")
        do {
            let release = try Updater.fetchLatestRelease()
            print("最新リリース: \(Updater.shortCommit(release.commit)) (\(release.publishedAt))")
            print("アセット: \(release.assetNames.joined(separator: ", "))")
            print(
                Updater.isUpdateAvailable(release)
                    ? "更新あり" : "更新なし(最新、またはビルド元コミット不明)")
        } catch let error as Updater.UpdateError {
            let detail = [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }.joined(separator: " / ")
            FileHandle.standardError.write(Data("\(detail)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func printSample() {
        guard let snapshot = MemorySampler.sample() else {
            FileHandle.standardError.write(Data("計測に失敗しました\n".utf8))
            exit(1)
        }
        let lines = [
            "物理メモリ:           \(MemoryFormat.detail(snapshot.total))",
            "使用済みメモリ:       \(MemoryFormat.detail(snapshot.used))",
            "  アプリメモリ:       \(MemoryFormat.detail(snapshot.appMemory))",
            "  確保済みメモリ:     \(MemoryFormat.detail(snapshot.wired))",
            "  圧縮:               \(MemoryFormat.detail(snapshot.compressed))",
            "  その他:             \(MemoryFormat.detail(snapshot.other))",
            "キャッシュされたファイル: \(MemoryFormat.detail(snapshot.cachedFiles))",
            "未使用:               \(MemoryFormat.detail(snapshot.unused))",
            "使用済みスワップ:     \(MemoryFormat.detail(snapshot.swapUsed))",
            "残容量:               \(MemoryFormat.detail(snapshot.available))",
            "使用率:               \(Int((snapshot.usedFraction * 100).rounded()))%",
            "メモリプレッシャー:   \(snapshot.pressure.label)",
        ]
        print(lines.joined(separator: "\n"))
    }
}

/// 約1秒間隔でメモリ状況を再計測する監視モデル
@Observable
@MainActor
final class MemoryMonitor {
    static let refreshInterval: TimeInterval = 1.0
    /// 省電力のためタイマーに許す誤差。OS が他の起床とまとめられる幅を決めるもので、
    /// 表示にタイミング要件はないため、Apple が下限として挙げる10%より広く取る。
    /// 更新間隔から導出し、間隔を変えても比率がずれないようにする
    static let timerTolerance: TimeInterval = refreshInterval * 0.3

    private(set) var snapshot: MemorySnapshot?
    /// メニューバーに出す文字列。値が動いても表示が変わらないティックでは更新しないことで、
    /// 再描画を省く(1秒間隔では約半分のティックが該当する)
    private(set) var menuBarText: String = "--"
    /// 使用量の多いアプリ。全プロセスの走査に約2msかかるため、毎ティックではなく間引いて更新する
    private(set) var topApps: [AppMemoryUsage] = []
    /// アプリ一覧を更新する間隔(秒)。順位はそう頻繁に入れ替わらない
    static let appsRefreshInterval: TimeInterval = 5.0
    /// 前回の走査時刻。回数で数えると、タイマー以外からの refresh() で間引きが崩れる
    private var lastAppsRefresh: Date?
    private var currentPressure = MemorySampler.initialPressure()
    private let resources = MemoryMonitorResources()

    init() {
        startPressureMonitoring()
        refresh()

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        // OSが他の処理とまとめて起床できるよう誤差を許容する
        timer.tolerance = Self.timerTolerance
        // メニュー表示中(イベントトラッキング中)も更新が止まらないようcommonモードで回す
        RunLoop.main.add(timer, forMode: .common)
        resources.timer = timer
    }

    func refresh() {
        snapshot = MemorySampler.sample(pressure: currentPressure)
        refreshTopAppsIfDue()
        refreshMenuBarText()
    }

    /// 時刻で間引く。「まだ一度も取得していない」と「取得したが空だった」を区別しないと、
    /// 取得できない環境で毎ティック全プロセスを走査し続けることになる
    private func refreshTopAppsIfDue() {
        let now = Date()
        if let last = lastAppsRefresh, now.timeIntervalSince(last) < Self.appsRefreshInterval {
            return
        }
        lastAppsRefresh = now
        topApps = ProcessSampler.topApps()
    }

    /// 表示モードの変更時にも即座に反映できるよう分けている
    func refreshMenuBarText() {
        let mode =
            DisplayMode(rawValue: UserDefaults.standard.string(forKey: DisplayMode.defaultsKey) ?? "")
            ?? .default
        let text = snapshot.map(mode.menuBarText(for:)) ?? "--"
        // 同じ文字列なら代入しない(代入すると観測側の再描画が走るため)
        if text != menuBarText { menuBarText = text }
    }

    private func startPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main)
        resources.pressureSource = source
        source.setEventHandler { [weak self] in
            // dataはイベントハンドラ内で読み取る。非同期ホップ後に読むと次のイベントで
            // 上書き・クリアされ、プレッシャーを取りこぼして.unknownと誤表示しうる
            let event = source.data
            Task { @MainActor [weak self] in
                self?.apply(pressure: MemoryPressure(dispatchEvent: event))
            }
        }
        source.resume()
    }

    private func apply(pressure: MemoryPressure) {
        currentPressure = pressure
        refresh()
    }
}

struct MemoryBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor: MemoryMonitor
    @State private var updateController = UpdateController.shared
    @State private var floatingController: FloatingWindowController
    @AppStorage(DisplayMode.defaultsKey) private var displayModeRaw = DisplayMode.default.rawValue

    init() {
        let monitor = MemoryMonitor()
        let floating = FloatingWindowController(monitor: monitor)
        _monitor = State(initialValue: monitor)
        _floatingController = State(initialValue: floating)
        // ウィンドウの生成は起動完了後に回す(init 中に前面化しても反映されない)
        Task { @MainActor in floating.restore() }
    }

    private var displayMode: DisplayMode {
        DisplayMode(rawValue: displayModeRaw) ?? .default
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(
                monitor: monitor, updateController: updateController,
                floatingController: floatingController)
        } label: {
            // Label(_:systemImage:) を渡すと SwiftUI はアイコンだけを
            // NSStatusItem に設定し、数値が描画されない(Issue #25)。
            // 常時表示が本アプリの中心機能なので、テキストで描画する
            HStack(spacing: 3) {
                Image(systemName: "memorychip")
                // 表示文字列そのものを読むことで、値が動いても文字列が同じティックでは
                // 再描画が走らない(1秒更新では約半分がこれに当たる)
                Text(monitor.menuBarText)
                    // 桁が変わったときに他のメニューバー項目がずれないようにする
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // swift runなど.appバンドル外から起動してもDockに出さない
        NSApp.setActivationPolicy(.accessory)
        // メニューのコンテンツは初回クリックまで生成されないため、
        // 起動時の確認はビューの task ではなくここで行う
        UpdateController.shared.checkAtLaunchIfEnabled()
    }
}
