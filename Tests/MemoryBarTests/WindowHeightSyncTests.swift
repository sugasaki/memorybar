import AppKit
import XCTest

@testable import MemoryBar

/// メニューパネルのウィンドウを内容の高さに合わせる判断(Issue #71)
final class WindowHeightSyncTests: XCTestCase {
    func test内容より大きいウィンドウは縮める() {
        // 詳細を開いたままパネルを閉じると、以後ずっと開いた分の高さで残る。
        // ウィンドウだけ大きいと内容が中央に浮いて二重の矩形に見える
        XCTAssertTrue(
            WindowHeightSync.shouldApply(current: 606, target: 257, lastApplied: nil))
    }

    func test内容より小さいウィンドウは広げる() {
        XCTAssertTrue(
            WindowHeightSync.shouldApply(current: 257, target: 606, lastApplied: nil))
    }

    func test誤差の範囲では動かさない() {
        // 見えない差で毎回設定し直すと、開くたびに窓が揺れる
        XCTAssertFalse(
            WindowHeightSync.shouldApply(current: 402, target: 402.3, lastApplied: nil))
    }

    func test小さすぎる測定値は無視する() {
        // 測定が壊れたときに窓を潰さないための歯止め。
        // スクロールで包んで高さを測る方式は実際に 10pt まで潰れた(Issue #41)
        XCTAssertFalse(
            WindowHeightSync.shouldApply(
                current: 402, target: WindowHeightSync.minimumHeight - 1, lastApplied: nil))
        XCTAssertFalse(WindowHeightSync.shouldApply(current: 402, target: 0, lastApplied: nil))
    }

    func test同じ高さを繰り返し要求しない() {
        // AppKit 側が受け付けない大きさだと、設定し直しても現在値が変わらない。
        // 判定だけ見て投げ続けると無限に往復する
        XCTAssertFalse(
            WindowHeightSync.shouldApply(current: 606, target: 257, lastApplied: 257))
        // 別の高さになったなら投げてよい
        XCTAssertTrue(
            WindowHeightSync.shouldApply(current: 606, target: 300, lastApplied: 257))
    }

    func test上端を固定して伸縮する() {
        // メニューバーの下に貼り付いた位置が動くと、開くたびに飛んで見える
        let current = NSRect(x: 100, y: 400, width: 280, height: 606)
        let shrunk = WindowHeightSync.frame(current: current, height: 257)
        XCTAssertEqual(shrunk.maxY, current.maxY, accuracy: 0.5)
        XCTAssertEqual(shrunk.height, 257)
        XCTAssertEqual(shrunk.minX, current.minX)
        XCTAssertEqual(shrunk.width, current.width)

        let grown = WindowHeightSync.frame(current: current, height: 800)
        XCTAssertEqual(grown.maxY, current.maxY, accuracy: 0.5)
        XCTAssertEqual(grown.height, 800)
    }
}
