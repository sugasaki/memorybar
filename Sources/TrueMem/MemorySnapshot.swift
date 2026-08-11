import Dispatch
import Foundation

/// システムが通知するメモリプレッシャー。
enum MemoryPressure: Sendable, Equatable {
    case normal
    case warning
    case critical
    /// 取得失敗・未知の値。正常(.normal)に置換すると誤認させるため区別する
    case unknown

    /// 起動直後の互換取得で使用するsysctlの生値。
    /// 1=normal, 2=warning, 4=critical。それ以外はunknown。
    init(rawSysctlLevel: Int32) {
        switch rawSysctlLevel {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unknown
        }
    }

    /// 公開APIであるDispatchSourceのイベントを表示状態へ変換する。
    init(dispatchEvent: DispatchSource.MemoryPressureEvent) {
        if dispatchEvent.contains(.critical) {
            self = .critical
        } else if dispatchEvent.contains(.warning) {
            self = .warning
        } else if dispatchEvent.contains(.normal) {
            self = .normal
        } else {
            self = .unknown
        }
    }

    var label: String {
        switch self {
        case .normal: "通常"
        case .warning: "注意"
        case .critical: "危険"
        case .unknown: MemoryFormat.unavailable
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
    /// 何も保持していない純粋な空きページ。
    /// `free_count` は先読みされたファイル内容を持つ speculative ページを含み、
    /// それは `external_page_count` にも入っているため、引かないと二重計上になる
    /// (`vm_stat` の「Pages free」も `free_count − speculative` を表示している)
    let unused: UInt64
    /// 使用済みスワップ(バイト)。取得失敗時はnil(0と区別する)
    let swapUsed: UInt64?
    let pressure: MemoryPressure

    /// 残容量。いま解放されている領域と、解放できるファイルキャッシュの合計。
    /// これを一次的な定義とし、使用済みをここから導出することで両者が必ず整合する。
    /// vm_statの「free pages」との混同を避けるためfreeではなくavailableと呼ぶ
    var available: UInt64 { min(total, unused + cachedFiles) }

    /// アクティビティモニタの「使用済みメモリ」。
    ///
    /// アプリ+確保済み+圧縮の合計**ではない**点に注意。実測では約0.7GB大きく、
    /// その差はVMがどのカテゴリにも計上していないページ(カーネル/ファームウェア予約や
    /// 圧縮機構のオーバーヘッド)にあたる。同時採取での照合は Issue #24 を参照
    var used: UInt64 { total - available }

    /// 使用済みのうち、アプリ・確保済み・圧縮のどれにも計上されない分。
    /// これを示さないと画面上で内訳の合計が使用済みと合わず、誤りに見える
    var other: UInt64 {
        let categorized = appMemory + wired + compressed
        return used > categorized ? used - categorized : 0
    }

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
        freePages: UInt64,
        speculativePages: UInt64,
        swapUsedBytes: UInt64?,
        pressure: MemoryPressure
    ) {
        self.total = totalBytes
        // purgeableがinternalを上回ることは通常ないが、負にならないようクランプする
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        self.appMemory = appPages * pageSize
        self.wired = wiredPages * pageSize
        self.compressed = compressedPages * pageSize
        self.cachedFiles = (externalPages + purgeablePages) * pageSize
        // speculative は external 側で数えるため、free からは除く
        let trulyFree = freePages > speculativePages ? freePages - speculativePages : 0
        self.unused = trulyFree * pageSize
        self.swapUsed = swapUsedBytes
        self.pressure = pressure
    }
}
