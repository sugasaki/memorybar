import Darwin
import Foundation
import CMachSupport

/// Mach / sysctlからの計測。副作用(システムコール)はこのファイルに隔離し、
/// 数値の導出は`MemorySnapshot`側で行う。
enum MemorySampler {
    /// アクティビティモニタと同じデータソース(host_statistics64)から1回サンプリングする。
    /// pressureを省略したCLI利用時だけ、互換レイヤーから起動時相当の値を取得する。
    static func sample(pressure: MemoryPressure? = nil) -> MemorySnapshot? {
        // mach_host_self()は呼ぶたびに送信権の参照が増える。解放しないと上限(65535)まで
        // 蓄積する規約違反になるため、1回だけ取得して必ず解放する
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var stats = vm_statistics64_data_t()
        var count = memorybar_host_vm_info64_count()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        guard let total = sysctlUInt64("hw.memsize") else { return nil }

        return MemorySnapshot(
            totalBytes: total,
            // vm_statistics64のページカウントはカーネルページ単位。
            // host_page_sizeと同値だがホストポートを要さず、単位としてこちらが正しい
            pageSize: UInt64(memorybar_kernel_page_size()),
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            externalPages: UInt64(stats.external_page_count),
            freePages: UInt64(stats.free_count),
            speculativePages: UInt64(stats.speculative_count),
            swapUsedBytes: swapUsedBytes(),
            pressure: pressure ?? initialPressure()
        )
    }

    /// DispatchSourceが最初のイベントを通知するまでの同期初期値。
    /// 非公開sysctlへの依存をここだけに閉じ込め、失敗・未知値はunknownのまま返す。
    ///
    /// 生値のエンコーディングは実測で確定している(2026-08-11 / macOS 26.5 arm64):
    /// プレッシャー正常時に1、逼迫時(圧縮9.4GB)に2。XNU内部の別エンコーディング
    /// (0=normal系)なら正常時は0のはずで、1は観測されない。よって1/2/4で確定。
    /// 未知値をnormalに倒す案があるが、「分からないのに正常と表示する」ことになり
    /// Issue #6 の趣旨に反するため採らない(unknownは安全側の失敗)。
    static func initialPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        return MemoryPressure(rawSysctlLevel: level)
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// 取得失敗はnilのまま返す(0に置換すると「スワップ未使用」と誤認させるため)
    private static func swapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage.xsu_used
    }
}
