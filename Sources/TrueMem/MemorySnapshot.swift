import Foundation

/// メモリプレッシャー(`kern.memorystatus_vm_pressure_level` の値に対応)
enum MemoryPressure: Sendable, Equatable {
    case normal
    case warning
    case critical

    /// sysctl の生値は 1=normal, 2=warning, 4=critical
    init(rawSysctlLevel: Int32) {
        switch rawSysctlLevel {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }

    var label: String {
        switch self {
        case .normal: "通常"
        case .warning: "注意"
        case .critical: "危険"
        }
    }
}

/// アクティビティモニタと同じ計算式でメモリ使用状況を導出する純粋モデル。
/// 生のページカウント(vm_statistics64 相当)から値を計算し、計測(Mach API)には依存しない。
struct MemorySnapshot: Sendable, Equatable {
    /// 物理メモリ合計(バイト)
    let total: UInt64
    /// アプリメモリ = (internal − purgeable) × ページサイズ
    let appMemory: UInt64
    /// 確保済みメモリ(wired)
    let wired: UInt64
    /// 圧縮メモリ(compressor が保持するページ)
    let compressed: UInt64
    /// キャッシュされたファイル = (external + purgeable) × ページサイズ
    let cachedFiles: UInt64
    /// 使用済みスワップ(バイト)
    let swapUsed: UInt64
    let pressure: MemoryPressure

    /// アクティビティモニタの「使用済みメモリ」
    var used: UInt64 { appMemory + wired + compressed }
    /// 残容量(物理メモリ − 使用済み)。キャッシュは解放可能なので残容量に含まれる
    var free: UInt64 { total > used ? total - used : 0 }
    /// 使用率(0.0〜1.0)
    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(used) / Double(total))
    }

    init(
        totalBytes: UInt64,
        pageSize: UInt64,
        internalPages: UInt64,
        purgeablePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        externalPages: UInt64,
        swapUsedBytes: UInt64,
        pressure: MemoryPressure
    ) {
        self.total = totalBytes
        // purgeable が internal を上回ることは通常ないが、負にならないようクランプする
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        self.appMemory = appPages * pageSize
        self.wired = wiredPages * pageSize
        self.compressed = compressedPages * pageSize
        self.cachedFiles = (externalPages + purgeablePages) * pageSize
        self.swapUsed = swapUsedBytes
        self.pressure = pressure
    }
}
