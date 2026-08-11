import XCTest

@testable import MemoryInfoMenubar

final class MemorySnapshotTests: XCTestCase {
    private let pageSize: UInt64 = 16384
    private let totalBytes: UInt64 = 24 * 1_073_741_824  // 24GB

    private func makeSnapshot(
        internalPages: UInt64 = 500_000,
        purgeablePages: UInt64 = 20_000,
        wiredPages: UInt64 = 100_000,
        compressedPages: UInt64 = 80_000,
        externalPages: UInt64 = 150_000,
        swapUsedBytes: UInt64 = 0,
        pressure: MemoryPressure = .normal
    ) -> MemorySnapshot {
        MemorySnapshot(
            totalBytes: totalBytes,
            pageSize: pageSize,
            internalPages: internalPages,
            purgeablePages: purgeablePages,
            wiredPages: wiredPages,
            compressedPages: compressedPages,
            externalPages: externalPages,
            swapUsedBytes: swapUsedBytes,
            pressure: pressure
        )
    }

    func testアプリメモリはinternalからpurgeableを引いた値になる() {
        let snapshot = makeSnapshot(internalPages: 500_000, purgeablePages: 20_000)
        XCTAssertEqual(snapshot.appMemory, 480_000 * pageSize)
    }

    func test使用済みはアプリメモリと確保済みと圧縮の合計になる() {
        let snapshot = makeSnapshot()
        let expected = (480_000 + 100_000 + 80_000) * pageSize
        XCTAssertEqual(snapshot.used, expected)
    }

    func test残容量は物理メモリから使用済みを引いた値になる() {
        let snapshot = makeSnapshot()
        XCTAssertEqual(snapshot.free, totalBytes - snapshot.used)
    }

    func testキャッシュはexternalとpurgeableの合計になる() {
        let snapshot = makeSnapshot(purgeablePages: 20_000, externalPages: 150_000)
        XCTAssertEqual(snapshot.cachedFiles, 170_000 * pageSize)
    }

    func testPurgeableがinternalを上回ってもアプリメモリは負にならない() {
        let snapshot = makeSnapshot(internalPages: 10, purgeablePages: 100)
        XCTAssertEqual(snapshot.appMemory, 0)
    }

    func test使用済みが物理メモリを上回っても残容量は負にならない() {
        let snapshot = makeSnapshot(wiredPages: 10_000_000)
        XCTAssertEqual(snapshot.free, 0)
        XCTAssertEqual(snapshot.usedFraction, 1.0)
    }

    func test使用率は使用済みを物理メモリで割った値になる() {
        let snapshot = makeSnapshot()
        let expected = Double(snapshot.used) / Double(totalBytes)
        XCTAssertEqual(snapshot.usedFraction, expected, accuracy: 0.0001)
    }

    func test物理メモリゼロなら使用率はゼロになる() {
        let snapshot = MemorySnapshot(
            totalBytes: 0, pageSize: pageSize,
            internalPages: 0, purgeablePages: 0, wiredPages: 0,
            compressedPages: 0, externalPages: 0, swapUsedBytes: 0,
            pressure: .normal)
        XCTAssertEqual(snapshot.usedFraction, 0)
    }

    func testメモリプレッシャーはsysctl生値から変換できる() {
        XCTAssertEqual(MemoryPressure(rawSysctlLevel: 1), .normal)
        XCTAssertEqual(MemoryPressure(rawSysctlLevel: 2), .warning)
        XCTAssertEqual(MemoryPressure(rawSysctlLevel: 4), .critical)
        XCTAssertEqual(MemoryPressure(rawSysctlLevel: 99), .normal)
    }
}
