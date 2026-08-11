import CMachSupport
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

    /// 注意: このテストは成功パスしか通らないため、`sample()` が同一スコープの `defer` で
    /// 解放していることが前提。各 return 直前で解放する形にリファクタすると、
    /// 早期 return 経路のリークをこのテストは検出できない(AGENTS.md の Mach ポート規律を参照)
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

    /// 公式マクロ経由の要素数が構造体サイズと乖離したら検出する
    /// (乖離したまま host_statistics64 を呼ぶと取得値が壊れる)
    func testHOST_VM_INFO64_COUNTは構造体サイズと整合する() {
        let sizeBased = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        XCTAssertEqual(truemem_host_vm_info64_count(), sizeBased)
    }

    /// ページサイズは全計算の乗数なので、取得できないと値が全て 0 になる
    func testカーネルページサイズが取得できホストポート版と一致する() {
        let kernelPageSize = truemem_kernel_page_size()
        XCTAssertGreaterThan(kernelPageSize, 0)

        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var hostPageSize: vm_size_t = 0
        XCTAssertEqual(host_page_size(host, &hostPageSize), KERN_SUCCESS)
        XCTAssertEqual(kernelPageSize, hostPageSize)
    }
}
