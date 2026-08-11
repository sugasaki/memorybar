import XCTest

@testable import TrueMem

final class DisplayModeTests: XCTestCase {
    private func makeSnapshot(usedBytes: UInt64, totalBytes: UInt64) -> MemorySnapshot {
        // wired だけで使用済みを構成した単純なスナップショット(pageSize=1 でバイト直指定)
        MemorySnapshot(
            totalBytes: totalBytes,
            pageSize: 1,
            internalPages: 0, purgeablePages: 0,
            wiredPages: usedBytes,
            compressedPages: 0, externalPages: 0,
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

    func test未知のrawValueはデフォルトにフォールバックする() {
        XCTAssertNil(DisplayMode(rawValue: "unknown"))
        XCTAssertEqual(DisplayMode.default, .freeGB)
    }
}
