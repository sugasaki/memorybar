import Dispatch
import XCTest

@testable import TrueMem

final class MemorySnapshotTests: XCTestCase {
    private let pageSize: UInt64 = 16384
    private let totalBytes: UInt64 = 24 * 1_073_741_824  // 24GB

    private func makeSnapshot(
        internalPages: UInt64 = 500_000,
        purgeablePages: UInt64 = 20_000,
        wiredPages: UInt64 = 100_000,
        compressedPages: UInt64 = 80_000,
        externalPages: UInt64 = 150_000,
        freePages: UInt64 = 30_000,
        swapUsedBytes: UInt64? = 0,
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
            freePages: freePages,
            swapUsedBytes: swapUsedBytes,
            pressure: pressure
        )
    }

    func testアプリメモリはinternalからpurgeableを引いた値になる() {
        let snapshot = makeSnapshot(internalPages: 500_000, purgeablePages: 20_000)
        XCTAssertEqual(snapshot.appMemory, 480_000 * pageSize)
    }

    func test残容量は未使用とキャッシュの合計になる() {
        // 解放できる領域が残容量。これを一次的な定義とする
        let snapshot = makeSnapshot(purgeablePages: 20_000, externalPages: 150_000, freePages: 30_000)
        XCTAssertEqual(snapshot.available, (30_000 + 170_000) * pageSize)
    }

    func test使用済みは物理メモリから残容量を引いた値になる() {
        // アクティビティモニタの「使用済みメモリ」は3内訳の合計ではない(Issue #24)
        let snapshot = makeSnapshot()
        XCTAssertEqual(snapshot.used, totalBytes - snapshot.available)
    }

    func test使用済みと残容量は必ず物理メモリに一致する() {
        // 別々に算出すると食い違うため、片方をもう片方から導出している
        for free in [UInt64(0), 30_000, 500_000] {
            let snapshot = makeSnapshot(freePages: free)
            XCTAssertEqual(snapshot.used + snapshot.available, totalBytes)
        }
    }

    func testその他は使用済みと3内訳の差になる() {
        // これを示さないと画面上で内訳の合計が使用済みと合わない
        let snapshot = makeSnapshot()
        let categorized = snapshot.appMemory + snapshot.wired + snapshot.compressed
        XCTAssertEqual(snapshot.other, snapshot.used - categorized)
        XCTAssertEqual(categorized + snapshot.other, snapshot.used)
    }

    func test3内訳が使用済みを上回ってもその他は負にならない() {
        let snapshot = makeSnapshot(wiredPages: 10_000_000, freePages: 1_000_000)
        XCTAssertEqual(snapshot.other, 0)
    }

    func testキャッシュはexternalとpurgeableの合計になる() {
        let snapshot = makeSnapshot(purgeablePages: 20_000, externalPages: 150_000)
        XCTAssertEqual(snapshot.cachedFiles, 170_000 * pageSize)
    }

    func testPurgeableがinternalを上回ってもアプリメモリは負にならない() {
        let snapshot = makeSnapshot(internalPages: 10, purgeablePages: 100)
        XCTAssertEqual(snapshot.appMemory, 0)
    }

    func test残容量が物理メモリを上回っても使用済みは負にならない() {
        // 採取値の不整合で合計が総量を超えても破綻しないこと
        let snapshot = makeSnapshot(freePages: 10_000_000)
        XCTAssertEqual(snapshot.available, totalBytes)
        XCTAssertEqual(snapshot.used, 0)
        XCTAssertEqual(snapshot.usedFraction, 0)
    }

    func test未使用がゼロなら残容量はキャッシュ分だけになる() {
        let snapshot = makeSnapshot(purgeablePages: 0, externalPages: 100_000, freePages: 0)
        XCTAssertEqual(snapshot.available, 100_000 * pageSize)
        XCTAssertEqual(snapshot.usedFraction, Double(snapshot.used) / Double(totalBytes), accuracy: 0.0001)
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
            compressedPages: 0, externalPages: 0, freePages: 0, swapUsedBytes: 0,
            pressure: .normal)
        XCTAssertEqual(snapshot.usedFraction, 0)
    }

    func testメモリプレッシャーはsysctl生値から変換できる() {
        XCTAssertEqual(MemoryPressure(rawSysctlLevel: 1), .normal)
        XCTAssertEqual(MemoryPressure(rawSysctlLevel: 2), .warning)
        XCTAssertEqual(MemoryPressure(rawSysctlLevel: 4), .critical)
    }

    func test未知のメモリプレッシャー値は正常扱いせずunknownになる() {
        XCTAssertEqual(MemoryPressure(rawSysctlLevel: 0), .unknown)
        XCTAssertEqual(MemoryPressure(rawSysctlLevel: 3), .unknown)
        XCTAssertEqual(MemoryPressure(rawSysctlLevel: 99), .unknown)
        XCTAssertEqual(MemoryPressure.unknown.label, "取得不能")
    }

    func testDispatchSourceイベントをメモリプレッシャーへ変換できる() {
        XCTAssertEqual(MemoryPressure(dispatchEvent: .normal), .normal)
        XCTAssertEqual(MemoryPressure(dispatchEvent: .warning), .warning)
        XCTAssertEqual(MemoryPressure(dispatchEvent: .critical), .critical)
        XCTAssertEqual(MemoryPressure(dispatchEvent: []), .unknown)
        XCTAssertEqual(MemoryPressure(dispatchEvent: [.normal, .critical]), .critical)
    }

    func testスワップ取得失敗はゼロに置換されずnilのまま保持される() {
        let snapshot = makeSnapshot(swapUsedBytes: nil, pressure: .unknown)
        XCTAssertNil(snapshot.swapUsed)
    }
}
