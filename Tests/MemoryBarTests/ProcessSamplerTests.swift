import XCTest

@testable import MemoryBar

final class ProcessSamplerTests: XCTestCase {

    // MARK: - 集計ロジック(純粋関数として決定的に検証する)

    private func identity(_ pid: pid_t, _ name: String, regular: Bool) -> AppIdentity {
        AppIdentity(id: "app.\(name)", name: name, pid: pid, isRegular: regular)
    }

    /// pid -> 親pid の対応から親を引く
    private func parents(_ map: [pid_t: pid_t]) -> (pid_t) -> pid_t? {
        { map[$0] }
    }

    func testヘルパープロセスが親アプリにまとめられる() {
        // 100 = アプリ本体、101/102 はその子。1行にまとまるべき
        let apps: [pid_t: AppIdentity] = [100: identity(100, "Chrome", regular: true)]
        let result = ProcessSampler.aggregate(
            footprints: [(100, 1_000), (101, 2_000), (102, 3_000)],
            appOfPID: apps,
            parentOf: parents([101: 100, 102: 101]),  // 孫も辿れること
            limit: 5)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Chrome")
        XCTAssertEqual(result[0].footprint, 6_000)
        XCTAssertEqual(result[0].processCount, 3)
    }

    func test通常アプリが祖先にいればアクセサリより優先される() {
        // Discord Helper のようにヘルパー自身がアクセサリ登録されている場合、
        // 単純にアクセサリを採用すると親から切り離されて別行になってしまう
        let apps: [pid_t: AppIdentity] = [
            100: identity(100, "Discord", regular: true),
            101: identity(101, "Discord Helper", regular: false),
        ]
        let result = ProcessSampler.aggregate(
            footprints: [(100, 1_000), (101, 5_000)],
            appOfPID: apps, parentOf: parents([101: 100]), limit: 5)

        XCTAssertEqual(result.count, 1, "ヘルパーが別行に分かれてはいけない")
        XCTAssertEqual(result[0].name, "Discord")
        XCTAssertEqual(result[0].footprint, 6_000)
    }

    func test通常アプリが無ければ最も外側のアクセサリに帰属する() {
        // メニューバー常駐アプリ配下のプロセスも名前を出せるようにする
        let apps: [pid_t: AppIdentity] = [
            100: identity(100, "常駐アプリ", regular: false),
            101: identity(101, "内側のヘルパー", regular: false),
        ]
        let result = ProcessSampler.aggregate(
            footprints: [(102, 7_000)],
            appOfPID: apps, parentOf: parents([102: 101, 101: 100]), limit: 5)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "常駐アプリ", "内側ではなく最も外側に帰属すべき")
    }

    func test端末のように所有者の違う祖先を挟んでも辿れる() {
        // login(root所有)を挟む端末配下のプロセスが「その他」に落ちないこと。
        // 親が引けない場合を模して、途中の pid には親情報だけを与える
        let apps: [pid_t: AppIdentity] = [100: identity(100, "Terminal", regular: true)]
        let result = ProcessSampler.aggregate(
            footprints: [(103, 9_000)],
            appOfPID: apps,
            parentOf: parents([103: 102, 102: 101, 101: 100]),
            limit: 5)

        XCTAssertEqual(result.first?.name, "Terminal")
        XCTAssertEqual(result.first?.footprint, 9_000)
    }

    func test親を辿れないプロセスはその他にまとめる() {
        let result = ProcessSampler.aggregate(
            footprints: [(200, 4_000)], appOfPID: [:], parentOf: parents([:]), limit: 5)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isGroupedOthers)
        XCTAssertEqual(result[0].id, ProcessSampler.othersID)
        XCTAssertEqual(result[0].footprint, 4_000)
    }

    func test合計は入力の総和と一致する() {
        // 上位から漏れた分を黙って落とすと全体像が分からなくなる
        let apps: [pid_t: AppIdentity] = [
            1: identity(1, "A", regular: true), 2: identity(2, "B", regular: true),
            3: identity(3, "C", regular: true), 4: identity(4, "D", regular: true),
        ]
        let footprints: [(pid: pid_t, bytes: UInt64)] = [
            (1, 400), (2, 300), (3, 200), (4, 100), (99, 50),
        ]
        let expected = footprints.reduce(UInt64(0)) { $0 + $1.bytes }

        for limit in 1...4 {
            let result = ProcessSampler.aggregate(
                footprints: footprints, appOfPID: apps, parentOf: parents([:]), limit: limit)
            XCTAssertEqual(
                result.reduce(UInt64(0)) { $0 + $1.footprint }, expected,
                "limit=\(limit) で合計が失われた")
            XCTAssertEqual(result.filter { !$0.isGroupedOthers }.count, limit)
            XCTAssertEqual(result.filter(\.isGroupedOthers).count, 1)
        }
    }

    func test使用量の多い順に並ぶ() {
        let apps: [pid_t: AppIdentity] = [
            1: identity(1, "小", regular: true), 2: identity(2, "大", regular: true),
        ]
        let result = ProcessSampler.aggregate(
            footprints: [(1, 100), (2, 900)], appOfPID: apps, parentOf: parents([:]), limit: 5)
        XCTAssertEqual(result.map(\.name), ["大", "小"])
    }

    func test循環した親子関係でも止まる() {
        // 異常なデータで無限ループしないこと
        let result = ProcessSampler.aggregate(
            footprints: [(1, 100)], appOfPID: [:], parentOf: parents([1: 2, 2: 3, 3: 1]), limit: 5)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isGroupedOthers)
    }

    func test入力が空なら空を返す() {
        XCTAssertTrue(
            ProcessSampler.aggregate(
                footprints: [], appOfPID: [:], parentOf: parents([:]), limit: 5
            ).isEmpty)
    }

    // MARK: - 実機での取得

    func test実機で全プロセスの使用量を取得できる() {
        let footprints = ProcessSampler.allFootprints()
        XCTAssertFalse(footprints.isEmpty, "1件も取得できないのは異常")
        XCTAssertGreaterThan(footprints.reduce(UInt64(0)) { $0 + $1.bytes }, 0)
    }

    func test実機で親pidを辿れる() {
        // PROC_PIDTBSDINFO では他ユーザー所有のプロセスで失敗する。
        // 自プロセスの親は必ず引けること
        let parent = ProcessSampler.parentPID(of: ProcessInfo.processInfo.processIdentifier)
        XCTAssertNotNil(parent)
        XCTAssertGreaterThan(parent ?? 0, 0)
    }

    @MainActor
    func test実機でアプリ単位に集計できる() {
        let apps = ProcessSampler.topApps()
        XCTAssertFalse(apps.isEmpty)
        for app in apps {
            XCTAssertFalse(app.name.isEmpty, "名前が空だと何のアプリか分からない")
            if app.isGroupedOthers {
                XCTAssertNil(app.pid)
            } else {
                XCTAssertNotNil(app.pid)
            }
        }
    }
}
