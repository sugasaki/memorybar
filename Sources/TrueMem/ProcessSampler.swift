import AppKit
import Darwin
import Foundation

/// メモリを多く使っているアプリ1件分。
/// 「何を終了すれば楽になるか」を示すのが目的なので、ヘルパープロセスは親アプリへまとめる
struct AppMemoryUsage: Identifiable, Sendable, Equatable {
    /// GUI アプリなら bundle identifier、まとめられないプロセス群なら固定の識別子
    let id: String
    let name: String
    /// アプリに属する全プロセスの phys_footprint 合計
    let footprint: UInt64
    /// 合計に含めたプロセス数
    let processCount: Int
    /// GUI アプリの pid。終了操作に使う。まとめ行では nil
    let pid: pid_t?

    var isGroupedOthers: Bool { pid == nil }
}

/// プロセスごとのメモリ使用量を集計する。
/// `ri_phys_footprint` はアクティビティモニタの「メモリ」列と同じ指標で、root なしで取得できる
enum ProcessSampler {
    /// GUI アプリに紐づかない分をまとめる行の識別子
    static let othersID = "__others__"

    /// 上位 `limit` 件のアプリと、それ以外をまとめた1行を返す
    static func topApps(limit: Int = 5) -> [AppMemoryUsage] {
        let footprints = allFootprints()
        guard !footprints.isEmpty else { return [] }

        // GUI アプリの pid → アプリ情報
        var appOfPID: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            appOfPID[app.processIdentifier] = app
        }

        var totals: [String: (name: String, bytes: UInt64, count: Int, pid: pid_t)] = [:]
        var othersBytes: UInt64 = 0
        var othersCount = 0

        for (pid, bytes) in footprints {
            guard let app = owningApp(of: pid, in: appOfPID) else {
                othersBytes += bytes
                othersCount += 1
                continue
            }
            let key = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            let name = displayName(of: app)
            let current = totals[key]
            totals[key] = (
                name: name,
                bytes: (current?.bytes ?? 0) + bytes,
                count: (current?.count ?? 0) + 1,
                pid: app.processIdentifier
            )
        }

        var result =
            totals
            .map {
                AppMemoryUsage(
                    id: $0.key, name: $0.value.name, footprint: $0.value.bytes,
                    processCount: $0.value.count, pid: $0.value.pid)
            }
            .sorted { $0.footprint > $1.footprint }

        let shown = Array(result.prefix(limit))
        // 表示から漏れた分と GUI に紐づかない分を、黙って消さずにまとめて示す
        let hiddenBytes = result.dropFirst(limit).reduce(UInt64(0)) { $0 + $1.footprint }
        let hiddenCount = result.dropFirst(limit).reduce(0) { $0 + $1.processCount }
        result = shown

        let remainingBytes = othersBytes + hiddenBytes
        if remainingBytes > 0 {
            result.append(
                AppMemoryUsage(
                    id: othersID, name: "その他のプロセス", footprint: remainingBytes,
                    processCount: othersCount + hiddenCount, pid: nil))
        }
        return result
    }

    /// 祖先を辿って GUI アプリへ帰属させる。Chrome のヘルパーを Chrome にまとめるため
    private static func owningApp(
        of pid: pid_t, in appOfPID: [pid_t: NSRunningApplication]
    ) -> NSRunningApplication? {
        var current = pid
        // 親を辿る深さの上限。循環や異常な連鎖で止まらなくなるのを防ぐ
        for _ in 0..<16 {
            if let app = appOfPID[current] { return app }
            guard let parent = parentPID(of: current), parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(
            pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size == Int32(MemoryLayout<proc_bsdinfo>.size) else { return nil }
        return pid_t(info.pbi_ppid)
    }

    /// 名前が取れないアプリでも空欄にしない
    private static func displayName(of app: NSRunningApplication) -> String {
        if let name = app.localizedName, !name.isEmpty { return name }
        if let bundle = app.bundleIdentifier, !bundle.isEmpty { return bundle }
        return "pid \(app.processIdentifier)"
    }

    /// 取得できたプロセスの (pid, phys_footprint)。
    /// 他ユーザー・システム所有のプロセスは取得できないため黙って除外される
    private static func allFootprints() -> [(pid_t, UInt64)] {
        var pids = [pid_t](repeating: 0, count: 8192)
        let byteCount = proc_listpids(
            UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard byteCount > 0 else { return [] }

        var result: [(pid_t, UInt64)] = []
        for index in 0..<(Int(byteCount) / MemoryLayout<pid_t>.size) where pids[index] > 0 {
            let pid = pids[index]
            var info = rusage_info_current()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            guard ok == 0, info.ri_phys_footprint > 0 else { continue }
            result.append((pid, info.ri_phys_footprint))
        }
        return result
    }
}
