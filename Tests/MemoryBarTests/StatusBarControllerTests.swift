import AppKit
import XCTest

@testable import MemoryBar

@MainActor
final class StatusBarControllerTests: XCTestCase {
    func test表示モードを繰り返し変えてもネイティブタイトルが追随する() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let originalMode = defaults.object(forKey: DisplayMode.defaultsKey)
        defer { defaults.set(originalMode, forKey: DisplayMode.defaultsKey) }

        let monitor = MemoryMonitor()
        let controller = StatusBarController(
            monitor: monitor, floatingController: FloatingWindowController(monitor: monitor))
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        let button = try XCTUnwrap(controller.statusItem.button)
        let image = try XCTUnwrap(button.image)
        XCTAssertEqual(button.title, monitor.menuBarText)

        // Observation の通知は代入前に届くため、通知の中で読んだまま登録を
        // やり直すと古い値が残る。2回以上変更し、購読が継続することも確かめる。
        for mode in [DisplayMode.usedPercent, .usedGB, .freeGB] {
            defaults.set(mode.rawValue, forKey: DisplayMode.defaultsKey)
            monitor.refreshMenuBarText()
            for _ in 0..<100 {
                if button.title == monitor.menuBarText { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(button.title, monitor.menuBarText)
            XCTAssertTrue(button.image === image, "数値変更のたびに画像を作り直さない")
        }
    }
}
