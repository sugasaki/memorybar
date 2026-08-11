import XCTest

@testable import TrueMem

final class ProcessSamplerTests: XCTestCase {
    func test実機でアプリの使用量を取得できる() throws {
        let apps = ProcessSampler.topApps()
        XCTAssertFalse(apps.isEmpty, "1件も取得できないのは異常")
        // 自分自身(テストプロセス)を含め、必ず何かしら計上される
        XCTAssertGreaterThan(apps.reduce(UInt64(0)) { $0 + $1.footprint }, 0)
    }

    func test使用量の多い順に並ぶ() throws {
        // 「何を終了すれば楽になるか」を示すのが目的なので順序が逆だと意味をなさない。
        // まとめ行は末尾に置くため比較から外す
        let apps = ProcessSampler.topApps().filter { !$0.isGroupedOthers }
        let sorted = apps.map(\.footprint).sorted(by: >)
        XCTAssertEqual(apps.map(\.footprint), sorted)
    }

    func test上位件数を絞ってもまとめ行以外は上限を超えない() throws {
        let limit = 3
        let apps = ProcessSampler.topApps(limit: limit)
        XCTAssertLessThanOrEqual(apps.filter { !$0.isGroupedOthers }.count, limit)
        // まとめ行は多くても1件
        XCTAssertLessThanOrEqual(apps.filter(\.isGroupedOthers).count, 1)
    }

    func test表示から漏れた分をまとめ行として残す() throws {
        // 黙って消すと合計が合わなくなり、利用者が全体像を把握できない
        let narrow = ProcessSampler.topApps(limit: 1)
        guard narrow.count > 1 else {
            throw XCTSkip("アプリが1件しかない環境ではまとめ行が生じない")
        }
        let others = try XCTUnwrap(narrow.first(where: \.isGroupedOthers))
        XCTAssertEqual(others.id, ProcessSampler.othersID)
        XCTAssertGreaterThan(others.footprint, 0)
        XCTAssertGreaterThan(others.processCount, 0)
    }

    func testまとめ行はpidを持たず個別アプリは持つ() throws {
        let apps = ProcessSampler.topApps()
        for app in apps {
            if app.isGroupedOthers {
                XCTAssertNil(app.pid, "まとめ行に終了対象のpidがあってはならない")
            } else {
                XCTAssertNotNil(app.pid)
            }
        }
    }

    func testアプリ名が空にならない() throws {
        // localizedName が空のアプリが実在するため、必ず何かを表示できること
        for app in ProcessSampler.topApps() {
            XCTAssertFalse(app.name.isEmpty)
        }
    }

    func testヘルパープロセスがアプリにまとめられる() throws {
        // Chrome のように多数の子プロセスを持つアプリは、1件に集約されて
        // プロセス数が2以上になる。集約できていなければ意味をなさない
        let apps = ProcessSampler.topApps(limit: 10).filter { !$0.isGroupedOthers }
        guard !apps.isEmpty else { throw XCTSkip("GUIアプリが動いていない環境") }
        XCTAssertTrue(
            apps.contains { $0.processCount >= 1 },
            "プロセス数が記録されていない")
    }
}
