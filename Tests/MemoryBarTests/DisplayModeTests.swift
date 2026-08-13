import XCTest

@testable import MemoryBar

final class DisplayModeTests: XCTestCase {
    private func makeSnapshot(usedBytes: UInt64, totalBytes: UInt64) -> MemorySnapshot {
        // pageSize=1 でバイト直指定。使用済みは残容量から導出されるため、
        // 目的の使用済みになるよう未使用ページ数を逆算する
        MemorySnapshot(
            totalBytes: totalBytes,
            pageSize: 1,
            internalPages: 0, purgeablePages: 0,
            wiredPages: usedBytes,
            compressedPages: 0, externalPages: 0,
            freePages: totalBytes > usedBytes ? totalBytes - usedBytes : 0,
            speculativePages: 0,
            swapUsedBytes: 0, pressure: .normal)
    }

    func testコンパクトGB表記は小数1桁になる() {
        XCTAssertEqual(DisplayMode.compactGB(12_884_901_888), "12.0G")  // 12 * 1024^3
        XCTAssertEqual(DisplayMode.compactGB(0), "0.0G")
    }

    func test残容量モードは空きバイトをGB表記する() {
        let snapshot = makeSnapshot(
            usedBytes: 8 * 1_073_741_824, totalBytes: 24 * 1_073_741_824)
        XCTAssertEqual(DisplayMode.freeGB.menuBarText(for: snapshot), "16.0G")
    }

    func test使用量モードは使用済みバイトをGB表記する() {
        let snapshot = makeSnapshot(
            usedBytes: 8 * 1_073_741_824, totalBytes: 24 * 1_073_741_824)
        XCTAssertEqual(DisplayMode.usedGB.menuBarText(for: snapshot), "8.0G")
    }

    func test使用率モードは百分率を整数表示する() {
        let snapshot = makeSnapshot(
            usedBytes: 12 * 1_073_741_824, totalBytes: 24 * 1_073_741_824)
        XCTAssertEqual(DisplayMode.usedPercent.menuBarText(for: snapshot), "50%")
    }

    func test取得できなかった値は取得不能と表示される() {
        XCTAssertEqual(MemoryFormat.detail(nil as UInt64?), "取得不能")
        // 0 バイトは「取得不能」と区別される(0 に潰さないことがこのプロジェクトの要件)
        XCTAssertNotEqual(MemoryFormat.detail(0 as UInt64?), "取得不能")
        XCTAssertEqual(MemoryPressure.unknown.label, MemoryFormat.unavailable)
    }

    func test未知のrawValueはデフォルトにフォールバックする() {
        XCTAssertNil(DisplayMode(rawValue: "unknown"))
        XCTAssertEqual(DisplayMode.default, .freeGB)
    }
}

/// 表示モードが要約表示にも反映されること(Issue #63)
extension DisplayModeTests {
    private func snapshot() -> MemorySnapshot {
        // 総量 24GB のうち 21GB 使用、残り 3GB(pageSize=1 でバイト直指定)
        let total: UInt64 = 24 * 1_073_741_824
        let free: UInt64 = 3 * 1_073_741_824
        return MemorySnapshot(
            totalBytes: total, pageSize: 1,
            internalPages: 0, purgeablePages: 0, wiredPages: total - free,
            compressedPages: 0, externalPages: 0, freePages: free,
            speculativePages: 0, swapUsedBytes: 0, pressure: .normal)
    }

    func test要約の大きな数値はメニューバーと同じ値を指す() {
        let s = snapshot()
        // 残容量モード: どちらも残容量
        XCTAssertEqual(DisplayMode.freeGB.menuBarText(for: s), "3.0G")
        XCTAssertEqual(DisplayMode.freeGB.primaryText(for: s), MemoryFormat.detail(s.available))
        // 使用量モード: どちらも使用済み
        XCTAssertEqual(DisplayMode.usedGB.menuBarText(for: s), "21.0G")
        XCTAssertEqual(DisplayMode.usedGB.primaryText(for: s), MemoryFormat.detail(s.used))
        // 使用率モード: どちらも百分率
        XCTAssertEqual(DisplayMode.usedPercent.menuBarText(for: s), "88%")
        XCTAssertEqual(DisplayMode.usedPercent.primaryText(for: s), "88%")
    }

    func test大きな数値の説明語がモードに合う() {
        // MemoryLabel と突き合わせても同語反復になるため、期待する語を直に書く
        XCTAssertEqual(DisplayMode.freeGB.primaryCaption, "利用可能なメモリ")
        XCTAssertEqual(DisplayMode.usedGB.primaryCaption, "使用済みメモリ")
        // %表示のとき「使用済みメモリ」だと量に読めるので使用率と呼ぶ
        XCTAssertEqual(DisplayMode.usedPercent.primaryCaption, "使用率")
    }

    func test伝わりにくい表記を使わない() {
        // 「空き」「物理」は意味が取りにくいとして置き換えた(Issue #66)。
        // 名称を足すときに戻ってしまわないよう、まとめて見張る
        let labels = [
            MemoryLabel.total, MemoryLabel.used, MemoryLabel.available, MemoryLabel.usedRatio,
        ]
        for label in labels {
            XCTAssertFalse(label.contains("空き"), "「\(label)」に「空き」が残っている")
            XCTAssertFalse(label.contains("物理"), "「\(label)」に「物理」が残っている")
        }
        XCTAssertEqual(Set(labels).count, labels.count, "同じ語が2つの意味に使われている")
    }

    func test使用率は百分率で表す() {
        XCTAssertEqual(DisplayMode.percentText(snapshot()), "88%")
    }
}
