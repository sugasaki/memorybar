import Darwin
import XCTest

@testable import TrueMem

/// 実機サンプリングの検証(CIのmacOSランナーでも実行される)
final class MemorySamplerTests: XCTestCase {
    func test実機でサンプリングでき妥当な値が取れる() throws {
        let snapshot = try XCTUnwrap(MemorySampler.sample())
        XCTAssertGreaterThan(snapshot.total, 0)
        XCTAssertGreaterThan(snapshot.used, 0)
        XCTAssertLessThanOrEqual(snapshot.used, snapshot.total)
    }

    func test連続サンプリングでもMachポート送信権がリークしない() throws {
        // ウォームアップ(遅延初期化などの影響を除外)
        _ = MemorySampler.sample()

        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var refsBefore: mach_port_urefs_t = 0
        XCTAssertEqual(
            mach_port_get_refs(mach_task_self_, host, MACH_PORT_RIGHT_SEND, &refsBefore),
            KERN_SUCCESS)

        for _ in 0..<200 {
            XCTAssertNotNil(MemorySampler.sample())
        }

        var refsAfter: mach_port_urefs_t = 0
        XCTAssertEqual(
            mach_port_get_refs(mach_task_self_, host, MACH_PORT_RIGHT_SEND, &refsAfter),
            KERN_SUCCESS)

        XCTAssertEqual(refsAfter, refsBefore, "サンプリングでホストポートの送信権参照が増えている")
    }

    @MainActor
    func test監視モデルは保持解除後に破棄される() {
        weak var weakMonitor: MemoryMonitor?
        autoreleasepool {
            let monitor = MemoryMonitor()
            weakMonitor = monitor
        }
        XCTAssertNil(weakMonitor)
    }

    @MainActor
    func testタイマーの許容誤差は更新間隔の10パーセント() {
        XCTAssertEqual(MemoryMonitor.refreshInterval, 2.0)
        XCTAssertEqual(MemoryMonitor.timerTolerance, 0.2)
    }
}
