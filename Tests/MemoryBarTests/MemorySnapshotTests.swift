import Dispatch
import XCTest

@testable import MemoryBar

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
        speculativePages: UInt64 = 5_000,
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
            speculativePages: speculativePages,
            swapUsedBytes: swapUsedBytes,
            pressure: pressure
        )
    }

    func testアプリメモリはinternalからpurgeableを引いた値になる() {
        let snapshot = makeSnapshot(internalPages: 500_000, purgeablePages: 20_000)
        XCTAssertEqual(snapshot.appMemory, 480_000 * pageSize)
    }

    /// 恒真式にならないよう、期待値をページ数から直接計算した具体値で固定する。
    /// 既定値: internal=500,000 purgeable=20,000 wired=100,000 compressed=80,000
    ///         external=150,000 free=30,000 speculative=5,000 / 総ページ=1,572,864
    func test各値が具体的なページ数から算出される() {
        let snapshot = makeSnapshot()
        // 未使用 = free − speculative = 25,000
        XCTAssertEqual(snapshot.unused, 25_000 * pageSize)
        // キャッシュ = external + purgeable = 170,000
        XCTAssertEqual(snapshot.cachedFiles, 170_000 * pageSize)
        // 残容量 = 25,000 + 170,000 = 195,000
        XCTAssertEqual(snapshot.available, 195_000 * pageSize)
        // 使用済み = 1,572,864 − 195,000 = 1,377,864
        XCTAssertEqual(snapshot.used, 1_377_864 * pageSize)
        // その他 = 1,377,864 − (480,000 + 100,000 + 80,000) = 717,864
        XCTAssertEqual(snapshot.other, 717_864 * pageSize)
    }

    func testSpeculativeは未使用から除かれる() {
        // free_count は speculative を含み、speculative は external にも含まれる。
        // 引かないと二重計上になり、残容量が過大・使用済みが過小になる(Issue #24)
        let withSpeculative = makeSnapshot(freePages: 30_000, speculativePages: 5_000)
        let withoutSpeculative = makeSnapshot(freePages: 30_000, speculativePages: 0)
        XCTAssertEqual(
            withoutSpeculative.available - withSpeculative.available, 5_000 * pageSize)
        XCTAssertEqual(withSpeculative.unused, 25_000 * pageSize)
    }

    func testSpeculativeがfreeを上回っても未使用は負にならない() {
        let snapshot = makeSnapshot(freePages: 100, speculativePages: 5_000)
        XCTAssertEqual(snapshot.unused, 0)
    }

    func test使用済みと残容量の合計は物理メモリに一致する() {
        // 別々に算出すると食い違うため、片方をもう片方から導出している
        for (free, spec) in [(UInt64(0), UInt64(0)), (30_000, 5_000), (500_000, 1_000)] {
            let snapshot = makeSnapshot(freePages: free, speculativePages: spec)
            XCTAssertEqual(snapshot.used + snapshot.available, totalBytes)
        }
    }

    func testその他を足すと内訳の合計が使用済みに一致する() {
        // これを示さないと画面上で内訳の合計が使用済みと合わない
        let snapshot = makeSnapshot()
        let categorized = snapshot.appMemory + snapshot.wired + snapshot.compressed
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
            compressedPages: 0, externalPages: 0, freePages: 0, speculativePages: 0,
            swapUsedBytes: 0,
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
