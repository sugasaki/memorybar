import AppKit
import XCTest

@testable import MemoryBar

/// メニューパネルのウィンドウを内容の高さに合わせる判断(Issue #71, #78)
final class WindowHeightSyncTests: XCTestCase {
    // MARK: - 高さ要求の判断(HeightGovernor)

    func test内容より大きいウィンドウは縮める() {
        // 詳細を開いたままパネルを閉じると、以後ずっと開いた分の高さで残る。
        // ウィンドウだけ大きいと内容が中央に浮いて二重の矩形に見える
        XCTAssertEqual(HeightGovernor().decide(current: 606, target: 257), 257)
    }

    func test内容より小さいウィンドウは広げる() {
        XCTAssertEqual(HeightGovernor().decide(current: 257, target: 606), 606)
    }

    func test誤差の範囲では動かさない() {
        // 見えない差で毎回設定し直すと、開くたびに窓が揺れる
        XCTAssertNil(HeightGovernor().decide(current: 402, target: 402.3))
    }

    func test小さすぎる測定値は無視する() {
        // 測定が壊れたときに窓を潰さないための歯止め。
        // スクロールで包んで高さを測る方式は実際に 10pt まで潰れた(Issue #41)
        XCTAssertNil(
            HeightGovernor().decide(current: 402, target: WindowHeightSync.minimumHeight - 1))
        XCTAssertNil(HeightGovernor().decide(current: 402, target: 0))
    }

    func test受け付けられない高さは有限回で諦める() {
        // AppKit 側が受け付けない大きさだと、設定し直しても現在値が変わらない。
        // 投げ続けると毎秒 setFrame で喧嘩することになる
        let governor = HeightGovernor()
        for attempt in 1...HeightGovernor.maxAttempts {
            XCTAssertEqual(
                governor.decide(current: 959, target: 770), 770, "\(attempt)回目までは再挑戦する")
        }
        XCTAssertNil(governor.decide(current: 959, target: 770), "上限に達したら打ち切る")
        XCTAssertNil(governor.decide(current: 959, target: 770))
    }

    func test諦めた後も外から動かされたら立て直す() {
        // 解像度変更やシステムの再配置でウィンドウが動いたら、諦めの根拠は古い。
        // 恒久的に諦めると、大きくされたウィンドウを直す機会が二度と来ない(#78)
        let governor = HeightGovernor()
        for _ in 1...HeightGovernor.maxAttempts {
            _ = governor.decide(current: 959, target: 770)
        }
        XCTAssertNil(governor.decide(current: 959, target: 770), "前提: 諦めた状態")
        XCTAssertEqual(governor.decide(current: 1000, target: 770), 770, "状況が変われば再挑戦する")
    }

    func test目標が変われば改めて要求する() {
        let governor = HeightGovernor()
        for _ in 1...HeightGovernor.maxAttempts {
            _ = governor.decide(current: 959, target: 770)
        }
        XCTAssertNil(governor.decide(current: 959, target: 770), "前提: 諦めた状態")
        XCTAssertEqual(governor.decide(current: 959, target: 800), 800)
    }

    func test一致したら記録が消えて同じ高さを再要求できる() {
        // 開閉を繰り返すと同じ高さを何度も要求することになる。
        // 記録を消さないと2回目の折りたたみが効かず、#71 の症状に戻る
        let governor = HeightGovernor()
        XCTAssertEqual(governor.decide(current: 606, target: 257), 257, "1回目の折りたたみ")
        XCTAssertNil(governor.decide(current: 257, target: 257), "反映されて一致")
        XCTAssertNil(governor.decide(current: 606, target: 606), "展開は自然に広がる")
        XCTAssertEqual(governor.decide(current: 606, target: 257), 257, "2回目の折りたたみも効く")
    }

    // MARK: - フレーム計算

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

    func test画面が広がったら本来の高さへ伸び直せる() {
        // 丸める前の高さで記録すると、収まらない間は現在値と一致しないまま
        // 記録だけが残り、解像度変更などで広がっても伸び直せなくなる
        let small = NSRect(x: 0, y: 0, width: 1600, height: 500)
        let current = NSRect(x: 100, y: 500, width: 280, height: 838)
        let clamped = WindowHeightSync.frame(current: current, height: 838, within: small)
        XCTAssertEqual(clamped.height, 500, "可視領域までに丸める")

        // 丸めた後の高さで判定するので、反映後は一致して記録が消える
        let governor = HeightGovernor()
        XCTAssertEqual(governor.decide(current: 838, target: 500), 500)
        XCTAssertNil(governor.decide(current: 500, target: 500), "反映されて一致")
        // 画面が広がれば、内容本来の高さを改めて要求できる
        XCTAssertEqual(governor.decide(current: 500, target: 838), 838)
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
