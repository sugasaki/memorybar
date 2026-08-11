import AppKit
import Dispatch
import SwiftUI

@main
enum Main {
    static func main() {
        // 検証用: --printで1サンプルを標準出力に出して終了する
        if CommandLine.arguments.contains("--print") {
            printSample()
            return
        }
        TrueMemApp.main()
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
            "使用済みスワップ:     \(snapshot.swapUsed.map(MemoryFormat.detail) ?? "取得不能")",
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
    private var pressureSource: DispatchSourceMemoryPressure?
    private var timer: Timer?

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
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
        pressureSource?.cancel()
    }

    func refresh() {
        snapshot = MemorySampler.sample(pressure: currentPressure)
    }

    private func startPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main)
        pressureSource = source
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handlePressureEvent()
            }
        }
        source.resume()
    }

    private func handlePressureEvent() {
        guard let event = pressureSource?.data else { return }
        currentPressure = MemoryPressure(dispatchEvent: event)
        refresh()
    }
}

struct TrueMemApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor = MemoryMonitor()
    @AppStorage("displayMode") private var displayModeRaw = DisplayMode.default.rawValue

    private var displayMode: DisplayMode {
        DisplayMode(rawValue: displayModeRaw) ?? .default
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
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
    }
}
