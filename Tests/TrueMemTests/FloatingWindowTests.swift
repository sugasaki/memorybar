import AppKit
import XCTest

@testable import TrueMem

@MainActor
final class FloatingWindowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: FloatingWindowController.defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FloatingWindowController.defaultsKey)
        super.tearDown()
    }

    func test既定では非表示() {
        // 常時表示を望まない利用者もいるため、勝手に出さない
        let controller = FloatingWindowController(monitor: MemoryMonitor())
        XCTAssertFalse(controller.isVisible)
    }

    func test表示状態が永続化される() {
        // 再起動しても前回の状態を保つ
        let controller = FloatingWindowController(monitor: MemoryMonitor())
        controller.isVisible = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: FloatingWindowController.defaultsKey))

        let restored = FloatingWindowController(monitor: MemoryMonitor())
        XCTAssertTrue(restored.isVisible)

        restored.isVisible = false
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: FloatingWindowController.defaultsKey))
    }

    func testオンオフを繰り返しても状態が壊れない() {
        let controller = FloatingWindowController(monitor: MemoryMonitor())
        for _ in 0..<3 {
            controller.isVisible = true
            XCTAssertTrue(controller.isVisible)
            controller.isVisible = false
            XCTAssertFalse(controller.isVisible)
        }
    }
}
