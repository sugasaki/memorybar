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

    func test最小サイズは既定サイズより小さく要約が収まる大きさである() {
        let min = FloatingWindowController.minimumSize
        let def = FloatingWindowController.defaultSize
        XCTAssertLessThan(min.width, def.width)
        XCTAssertLessThan(min.height, def.height)
        // 要約(見出し+残容量+帯)が収まらない大きさまで縮められると読めなくなる
        XCTAssertGreaterThanOrEqual(min.height, 110)
        XCTAssertGreaterThanOrEqual(min.width, 200)
    }

    func test内訳の合計は物理メモリと一致する() {
        // 帯が物理メモリを過不足なく覆っていること(隙間や超過があると構成比が嘘になる)
        let snapshot = MemorySnapshot(
            totalBytes: 1_572_864 * 16384, pageSize: 16384,
            internalPages: 500_000, purgeablePages: 20_000, wiredPages: 100_000,
            compressedPages: 80_000, externalPages: 150_000, freePages: 30_000,
            speculativePages: 5_000, swapUsedBytes: 0, pressure: .normal)
        let total = MemoryComposition.segments(of: snapshot).reduce(UInt64(0)) { $0 + $1.bytes }
        XCTAssertEqual(total, snapshot.total)
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
