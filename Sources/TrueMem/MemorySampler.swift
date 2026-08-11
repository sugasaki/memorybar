import Darwin
import Foundation

/// Mach / sysctl からの計測。副作用(システムコール)はこのファイルに隔離し、
/// 数値の導出は `MemorySnapshot` 側で行う。
enum MemorySampler {
    /// アクティビティモニタと同じデータソース(host_statistics64)から1回サンプリングする
    static func sample() -> MemorySnapshot? {
        // mach_host_self() は呼ぶたびに送信権の参照が増えるため、解放しないと
        // 常駐運用(2秒間隔)でポート権がリークし続ける。1回だけ取得して必ず解放する
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return nil
        }
        guard let total = sysctlUInt64("hw.memsize") else { return nil }

        return MemorySnapshot(
            totalBytes: total,
            pageSize: UInt64(pageSize),
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            externalPages: UInt64(stats.external_page_count),
            swapUsedBytes: swapUsedBytes(),
            pressure: pressureLevel()
        )
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// 取得失敗は nil のまま返す(0 に置換すると「スワップ未使用」と誤認させるため)
    private static func swapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage.xsu_used
    }

    /// 取得失敗は .unknown を返す(.normal に置換すると「正常」と誤認させるため)
    private static func pressureLevel() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        return MemoryPressure(rawSysctlLevel: level)
    }
}
