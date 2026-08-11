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
        // 検証用: --printで1サンプルを標準出力に出して終了する
        if CommandLine.arguments.contains("--print") {
            printSample()
            return
        }
        // 検証用: 更新確認だけを行って結果を標準出力に出す(インストールはしない)
        if CommandLine.arguments.contains("--check-update") {
            printUpdateStatus()
            return
        }
        TrueMemApp.main()
    }

    private static func printUpdateStatus() {
        print("現在のビルド: \(UpdateController.currentVersionLabel)")
        guard let gh = Updater.locateGH() else {
            FileHandle.standardError.write(
                Data("gh が見つかりません(PATH非依存の既定パスにも存在しない)\n".utf8))
            exit(1)
        }
        print("gh: \(gh.path)")
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
            "キャッシュされたファイル: \(MemoryFormat.detail(snapshot.cachedFiles))",
            "使用済みスワップ:     \(MemoryFormat.detail(snapshot.swapUsed))",
            "残容量:               \(MemoryFormat.detail(snapshot.available))",
            "使用率:               \(Int((snapshot.usedFraction * 100).rounded()))%",
            "メモリプレッシャー:   \(snapshot.pressure.label)",
        ]
        print(lines.joined(separator: "\n"))
    }
}

/// 約2秒間隔でメモリ状況を再計測する監視モデル
@Observable
@MainActor
final class MemoryMonitor {
    static let refreshInterval: TimeInterval = 2.0
    static let timerTolerance: TimeInterval = 0.2

    private(set) var snapshot: MemorySnapshot?
    private var currentPressure = MemorySampler.initialPressure()
    private let resources = MemoryMonitorResources()

    init() {
        startPressureMonitoring()
        refresh()

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        // OSが他の処理とまとめて起床できるよう、更新間隔の10%を許容する
        timer.tolerance = Self.timerTolerance
        // メニュー表示中(イベントトラッキング中)も更新が止まらないようcommonモードで回す
        RunLoop.main.add(timer, forMode: .common)
        resources.timer = timer
    }

    func refresh() {
        snapshot = MemorySampler.sample(pressure: currentPressure)
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

struct TrueMemApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor = MemoryMonitor()
    @State private var updateController = UpdateController.shared
    @AppStorage("displayMode") private var displayModeRaw = DisplayMode.default.rawValue

    private var displayMode: DisplayMode {
        DisplayMode(rawValue: displayModeRaw) ?? .default
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor, updateController: updateController)
        } label: {
            if let snapshot = monitor.snapshot {
                Label(displayMode.menuBarText(for: snapshot), systemImage: "memorychip")
            } else {
                Label("--", systemImage: "memorychip")
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
