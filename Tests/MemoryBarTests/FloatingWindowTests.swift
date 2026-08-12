import AppKit
import XCTest

@testable import MemoryBar

@MainActor
final class FloatingWindowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: FloatingWindowController.defaultsKey)
        UserDefaults.standard.removeObject(forKey: FloatingWindowController.detailsExpandedKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FloatingWindowController.defaultsKey)
        UserDefaults.standard.removeObject(forKey: FloatingWindowController.detailsExpandedKey)
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

    func test閉じたあと再起動しても復活しない() {
        // 閉じる操作は isVisible を false にする。単にウィンドウを隠すだけだと
        // 次回起動時に勝手に出てきてしまう(Issue #37)
        let controller = FloatingWindowController(monitor: MemoryMonitor())
        controller.isVisible = true
        controller.isVisible = false  // 閉じるボタン相当

        let afterRelaunch = FloatingWindowController(monitor: MemoryMonitor())
        XCTAssertFalse(afterRelaunch.isVisible)
    }

    func test詳細を開くと高さが増える() {
        // 開いても高さが変わらないと、内容が枠に収まらずスクロール頼りになる
        XCTAssertGreaterThan(
            FloatingWindowController.expandedHeight,
            FloatingWindowController.compactSize.height)
    }

    func test既定では詳細を開かない() {
        // 既定で詳細まで開くと情報が多すぎて視認性が落ちる(Issue #43)
        UserDefaults.standard.removeObject(forKey: FloatingWindowController.detailsExpandedKey)
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: FloatingWindowController.detailsExpandedKey))
        XCTAssertEqual(FloatingWindowController.defaultSize, FloatingWindowController.compactSize)
    }

    // MARK: - 開閉時のフレーム計算

    private var screen: NSRect { NSRect(x: 0, y: 0, width: 1600, height: 1000) }

    func test展開しても上端が動かない() {
        let current = NSRect(x: 100, y: 700, width: 300, height: 168)
        let result = FloatingWindowController.frame(for: true, current: current, within: screen)
        XCTAssertEqual(result.maxY, current.maxY, accuracy: 0.5, "上端がずれると置いた位置が動いて見える")
        XCTAssertGreaterThan(result.height, current.height)
    }

    func test展開時に利用者が広げた高さを縮めない() {
        // 折りたたみ状態で手動で広げていた高さを、展開の瞬間に奪わない
        let current = NSRect(x: 100, y: 100, width: 300, height: 800)
        let result = FloatingWindowController.frame(for: true, current: current, within: screen)
        XCTAssertEqual(result.height, 800)
    }

    func test状態ごとに記憶した高さを復元する() {
        // 展開時に広げた高さは、折りたたんで再度開いたときに戻ってくる。
        // 上端を基準に下へ伸ばすので、画面に収まる位置に置いて確かめる
        let current = NSRect(x: 100, y: 700, width: 300, height: 168)
        let result = FloatingWindowController.frame(
            for: true, current: current, storedHeight: 720, within: screen)
        XCTAssertEqual(result.height, 720)
        XCTAssertEqual(result.maxY, current.maxY, accuracy: 0.5)
    }

    func test折りたたみ時に記憶した高さも復元する() {
        // 折りたたみ状態で広げていた高さを、展開から戻ったときに失わない
        let current = NSRect(x: 100, y: 300, width: 300, height: 560)
        let result = FloatingWindowController.frame(
            for: false, current: current, storedHeight: 300, within: screen)
        XCTAssertEqual(result.height, 300)
    }

    func test記憶した高さも画面外にはみ出さない() {
        let small = NSRect(x: 0, y: 0, width: 1600, height: 400)
        let current = NSRect(x: 100, y: 100, width: 300, height: 168)
        let result = FloatingWindowController.frame(
            for: true, current: current, storedHeight: 900, within: small)
        XCTAssertLessThanOrEqual(result.height, small.height)
        XCTAssertGreaterThanOrEqual(result.minY, small.minY)
    }

    func test折りたたむと要約の高さまで縮む() {
        let current = NSRect(x: 100, y: 300, width: 300, height: 560)
        let result = FloatingWindowController.frame(for: false, current: current, within: screen)
        XCTAssertEqual(result.height, FloatingWindowController.compactSize.height)
    }

    func test画面外にはみ出さない() {
        // 下端付近で展開すると画面外へ伸びてしまい、掴めなくなる
        let current = NSRect(x: 100, y: 10, width: 300, height: 168)
        let result = FloatingWindowController.frame(for: true, current: current, within: screen)
        XCTAssertGreaterThanOrEqual(result.minY, screen.minY)
        XCTAssertLessThanOrEqual(result.maxY, screen.maxY)
    }

    func test画面より高い要求でも可視領域に収まる() {
        let small = NSRect(x: 0, y: 0, width: 1600, height: 300)
        let current = NSRect(x: 100, y: 100, width: 300, height: 168)
        let result = FloatingWindowController.frame(for: true, current: current, within: small)
        XCTAssertLessThanOrEqual(result.height, small.height)
        XCTAssertGreaterThanOrEqual(result.minY, small.minY)
        XCTAssertLessThanOrEqual(result.maxY, small.maxY)
    }

    func test開閉を繰り返しても位置と大きさが往復する() {
        let start = NSRect(x: 100, y: 500, width: 300, height: 168)
        var frame = start
        for _ in 0..<3 {
            frame = FloatingWindowController.frame(for: true, current: frame, within: screen)
            frame = FloatingWindowController.frame(for: false, current: frame, within: screen)
        }
        XCTAssertEqual(frame.height, start.height)
        XCTAssertEqual(frame.maxY, start.maxY, accuracy: 0.5)
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
