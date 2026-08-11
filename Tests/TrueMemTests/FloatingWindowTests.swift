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

    func test画面外の位置は画面上と判定しない() {
        // 表示構成が変わって保存位置が画面外になると、ウィンドウを見失う。
        // その場合は既定位置へ戻す必要があるため、判定できることを確かめる
        let offscreen = NSRect(x: -99_000, y: -99_000, width: 260, height: 120)
        XCTAssertFalse(FloatingWindowController.isOnAnyScreen(offscreen))

        let onscreen = try? XCTUnwrap(NSScreen.main).visibleFrame
        if let onscreen {
            XCTAssertTrue(
                FloatingWindowController.isOnAnyScreen(
                    NSRect(x: onscreen.midX, y: onscreen.midY, width: 260, height: 120)))
        }
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
