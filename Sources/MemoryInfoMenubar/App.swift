import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        // 検証用: --print で1サンプルを標準出力に出して終了する
        if CommandLine.arguments.contains("--print") {
            printSample()
            return
        }
        MemoryInfoMenubarApp.main()
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
            "残容量:               \(MemoryFormat.detail(snapshot.free))",
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
    private(set) var snapshot: MemorySnapshot?
    private var timer: Timer?

    init() {
        refresh()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // メニュー表示中(イベントトラッキング中)も更新が止まらないよう common モードで回す
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        snapshot = MemorySampler.sample()
    }
}

struct MemoryInfoMenubarApp: App {
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
        // swift run など .app バンドル外から起動しても Dock に出さない
        NSApp.setActivationPolicy(.accessory)
    }
}
