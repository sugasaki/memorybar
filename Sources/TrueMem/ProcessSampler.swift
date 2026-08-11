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
    /// GUI アプリの pid。まとめ行では nil
    let pid: pid_t?

    var isGroupedOthers: Bool { pid == nil }
}

/// 集計に必要なアプリの情報だけを取り出したもの。
/// `NSRunningApplication` を集計ロジックから切り離し、テストできるようにする
struct AppIdentity: Sendable, Equatable {
    let id: String
    let name: String
    let pid: pid_t
    /// Dock に出る通常のアプリか。false はメニューバー常駐などのアクセサリアプリ
    let isRegular: Bool
}

/// プロセスごとのメモリ使用量を集計する。
/// `ri_phys_footprint` はアクティビティモニタの「メモリ」列と同じ指標で、root なしで取得できる
enum ProcessSampler {
    /// GUI アプリに紐づかない分をまとめる行の識別子
    static let othersID = "__others__"
    /// 親を辿る深さの上限。循環や異常な連鎖で止まらなくなるのを防ぐ(実測の最大は6)
    static let maxAncestorDepth = 16

    /// 上位 `limit` 件のアプリと、それ以外をまとめた1行を返す
    @MainActor
    static func topApps(limit: Int = 5) -> [AppMemoryUsage] {
        aggregate(
            footprints: allFootprints(),
            appOfPID: runningAppIdentities(),
            parentOf: parentPID(of:),
            limit: limit)
    }

    /// 集計の本体。入力を差し替えられるよう純粋関数にしてある
    static func aggregate(
        footprints: [(pid: pid_t, bytes: UInt64)],
        appOfPID: [pid_t: AppIdentity],
        parentOf: (pid_t) -> pid_t?,
        limit: Int
    ) -> [AppMemoryUsage] {
        guard !footprints.isEmpty else { return [] }

        var totals: [String: (name: String, bytes: UInt64, count: Int, pid: pid_t)] = [:]
        var othersBytes: UInt64 = 0
        var othersCount = 0

        for entry in footprints {
            guard let app = owningApp(of: entry.pid, in: appOfPID, parentOf: parentOf) else {
                othersBytes += entry.bytes
                othersCount += 1
                continue
            }
            let current = totals[app.id]
            totals[app.id] = (
                name: app.name,
                bytes: (current?.bytes ?? 0) + entry.bytes,
                count: (current?.count ?? 0) + 1,
                pid: app.pid
            )
        }

        let ranked =
            totals
            .map {
                AppMemoryUsage(
                    id: $0.key, name: $0.value.name, footprint: $0.value.bytes,
                    processCount: $0.value.count, pid: $0.value.pid)
            }
            .sorted { $0.footprint > $1.footprint }

        var result = Array(ranked.prefix(limit))
        // 表示から漏れた分と GUI に紐づかない分を、黙って消さずにまとめて示す
        let hidden = ranked.dropFirst(limit)
        let remainingBytes = othersBytes + hidden.reduce(UInt64(0)) { $0 + $1.footprint }
        let remainingCount = othersCount + hidden.reduce(0) { $0 + $1.processCount }
        if remainingBytes > 0 {
            result.append(
                AppMemoryUsage(
                    id: othersID, name: "その他のプロセス", footprint: remainingBytes,
                    processCount: remainingCount, pid: nil))
        }
        return result
    }

    /// 祖先を辿って所属アプリを決める。
    ///
    /// 規則は「最も近い通常アプリ。無ければ祖先のうち最も外側のアクセサリアプリ」。
    /// アクセサリを単純に採用すると、自分自身がアクセサリ登録されたヘルパー
    /// (Discord Helper など)が親から切り離されて別行になってしまう
    static func owningApp(
        of pid: pid_t, in appOfPID: [pid_t: AppIdentity], parentOf: (pid_t) -> pid_t?
    ) -> AppIdentity? {
        var current = pid
        var outermostAccessory: AppIdentity?
        for _ in 0..<maxAncestorDepth {
            if let app = appOfPID[current] {
                if app.isRegular { return app }
                // 上へ辿るほど外側なので、最後に見つかったものが最も外側になる
                outermostAccessory = app
            }
            guard let parent = parentOf(current), parent > 1 else { break }
            current = parent
        }
        return outermostAccessory
    }

    /// 名前を出せるアプリ(通常・アクセサリの両方)
    @MainActor
    private static func runningAppIdentities() -> [pid_t: AppIdentity] {
        var result: [pid_t: AppIdentity] = [:]
        for app in NSWorkspace.shared.runningApplications {
            let policy = app.activationPolicy
            guard policy == .regular || policy == .accessory else { continue }
            let pid = app.processIdentifier
            result[pid] = AppIdentity(
                id: app.bundleIdentifier ?? "pid:\(pid)",
                name: displayName(of: app),
                pid: pid,
                isRegular: policy == .regular)
        }
        return result
    }

    /// 親 pid を返す。
    /// `PROC_PIDTBSDINFO` は他ユーザー所有のプロセスで失敗するため使わない。
    /// 端末は root 所有の `login` を挟むため、それだと端末配下が全て辿れなくなる
    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = proc_pidinfo(
            pid, PROC_PIDT_SHORTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdshortinfo>.size))
        guard size == Int32(MemoryLayout<proc_bsdshortinfo>.size) else { return nil }
        return pid_t(info.pbsi_ppid)
    }

    /// 名前が取れないアプリでも空欄にしない
    private static func displayName(of app: NSRunningApplication) -> String {
        if let name = app.localizedName, !name.isEmpty { return name }
        if let bundle = app.bundleIdentifier, !bundle.isEmpty { return bundle }
        return "pid \(app.processIdentifier)"
    }

    /// 取得できたプロセスの (pid, phys_footprint)。
    /// 他ユーザー・システム所有のプロセスは取得できないため黙って除外される
    static func allFootprints() -> [(pid: pid_t, bytes: UInt64)] {
        guard let pids = listAllPIDs() else { return [] }
        var result: [(pid: pid_t, bytes: UInt64)] = []
        result.reserveCapacity(pids.count)
        for pid in pids where pid > 0 {
            var info = rusage_info_current()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            guard ok == 0, info.ri_phys_footprint > 0 else { continue }
            result.append((pid: pid, bytes: info.ri_phys_footprint))
        }
        return result
    }

    /// 必要量を問い合わせてから取得する。固定長だと上限に達したとき黙ってプロセスが欠ける
    private static func listAllPIDs() -> [pid_t]? {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return nil }
        // 問い合わせから取得までの間に増えることがあるため余裕を持たせる
        let capacity = Int(needed) / MemoryLayout<pid_t>.size + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let byteCount = proc_listpids(
            UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard byteCount > 0 else { return nil }
        return Array(pids.prefix(Int(byteCount) / MemoryLayout<pid_t>.size))
    }
}
