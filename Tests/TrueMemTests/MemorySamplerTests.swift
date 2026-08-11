import Darwin
import XCTest

@testable import TrueMem

/// 実機サンプリングの検証(CI の macOS ランナーでも実行される)
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

        // 修正前は mach_host_self() の解放漏れにより 200 サンプルで +400 になる
        XCTAssertEqual(refsAfter, refsBefore, "サンプリングでホストポートの送信権参照が増えている")
    }
}
