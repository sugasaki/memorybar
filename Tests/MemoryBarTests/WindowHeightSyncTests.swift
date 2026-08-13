import AppKit
import XCTest

@testable import MemoryBar

/// メニューパネルのウィンドウを内容の高さに合わせる判断(Issue #71)
final class WindowHeightSyncTests: XCTestCase {
    func test内容より大きいウィンドウは縮める() {
        // 詳細を開いたままパネルを閉じると、以後ずっと開いた分の高さで残る。
        // ウィンドウだけ大きいと内容が中央に浮いて二重の矩形に見える
        XCTAssertEqual(
            WindowHeightSync.action(current: 606, target: 257, requested: nil), .apply(257))
    }

    func test内容より小さいウィンドウは広げる() {
        XCTAssertEqual(
            WindowHeightSync.action(current: 257, target: 606, requested: nil), .apply(606))
    }

    func test誤差の範囲では動かさない() {
        // 見えない差で毎回設定し直すと、開くたびに窓が揺れる
        XCTAssertEqual(WindowHeightSync.action(current: 402, target: 402.3, requested: nil), .none)
    }

    func test小さすぎる測定値は無視する() {
        // 測定が壊れたときに窓を潰さないための歯止め。
        // スクロールで包んで高さを測る方式は実際に 10pt まで潰れた(Issue #41)
        XCTAssertEqual(
            WindowHeightSync.action(
                current: 402, target: WindowHeightSync.minimumHeight - 1, requested: nil), .none)
        XCTAssertEqual(WindowHeightSync.action(current: 402, target: 0, requested: nil), .none)
    }

    func test受け付けられない高さは要求し続けない() {
        // AppKit 側が受け付けない大きさだと、設定し直しても現在値が変わらない。
        // 判定だけ見て投げ続けると無限に往復する
        XCTAssertEqual(WindowHeightSync.action(current: 606, target: 257, requested: 257), .none)
        // 別の高さになったなら投げてよい
        XCTAssertEqual(
            WindowHeightSync.action(current: 606, target: 300, requested: 257), .apply(300))
    }

    func test同じ高さでも一度一致すればまた要求できる() {
        // 開閉を繰り返すと同じ高さを何度も要求することになる。
        // 諦めの記録を消さないと、2回目の折りたたみが効かず元の症状に戻る
        var requested: CGFloat?

        // 1回目の折りたたみ: 反映する
        guard case .apply(let first) = WindowHeightSync.action(
            current: 606, target: 257, requested: requested)
        else { return XCTFail("1回目が反映されない") }
        requested = first

        // 反映後は一致するので記録を消す
        XCTAssertEqual(
            WindowHeightSync.action(current: 257, target: 257, requested: requested),
            .clearRequest)
        requested = nil

        // 展開しても記録は消えたまま(自然に広がるので要求は要らない)
        XCTAssertEqual(
            WindowHeightSync.action(current: 606, target: 606, requested: requested), .none)

        // 2回目の折りたたみ: また反映できる
        XCTAssertEqual(
            WindowHeightSync.action(current: 606, target: 257, requested: requested), .apply(257))
    }

    func test上端を固定して伸縮する() {
        // メニューバーの下に貼り付いた位置が動くと、開くたびに飛んで見える
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        // 可視領域に収まっている窓を基準にする(はみ出していると丸めが働いて別の話になる)
        let current = NSRect(x: 100, y: 194, width: 280, height: 606)
        let shrunk = WindowHeightSync.frame(current: current, height: 257, within: screen)
        XCTAssertEqual(shrunk.maxY, current.maxY, accuracy: 0.5)
        XCTAssertEqual(shrunk.height, 257)
        XCTAssertEqual(shrunk.minX, current.minX)
        XCTAssertEqual(shrunk.width, current.width)

        let grown = WindowHeightSync.frame(current: current, height: 800, within: screen)
        XCTAssertEqual(grown.maxY, current.maxY, accuracy: 0.5)
        XCTAssertEqual(grown.height, 800)
    }

    func test画面からはみ出さない() {
        // パネルはスクロールできないので、はみ出すと下端に手が届かなくなる
        let small = NSRect(x: 0, y: 0, width: 1600, height: 500)
        let current = NSRect(x: 100, y: 400, width: 280, height: 257)
        let result = WindowHeightSync.frame(current: current, height: 900, within: small)
        XCTAssertLessThanOrEqual(result.height, small.height)
        XCTAssertGreaterThanOrEqual(result.minY, small.minY)
        XCTAssertLessThanOrEqual(result.maxY, small.maxY)
    }
}
