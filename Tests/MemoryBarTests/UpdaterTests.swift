import XCTest

@testable import MemoryBar

final class UpdaterTests: XCTestCase {
    private func release(commit: String, assets: [String] = ["MemoryBar.zip"]) -> Updater.ReleaseInfo
    {
        Updater.ReleaseInfo(commit: commit, publishedAt: "2026-08-11T00:00:00Z", assetNames: assets)
    }

    func test同じコミットなら更新なしと判定される() {
        let commit = "0123456789abcdef0123456789abcdef01234567"
        XCTAssertTrue(Updater.isSameCommit(commit, commit))
    }

    func test短縮SHAと完全SHAを同一と判定できる() {
        let full = "0123456789abcdef0123456789abcdef01234567"
        XCTAssertTrue(Updater.isSameCommit(full, "0123456"))
        XCTAssertTrue(Updater.isSameCommit("0123456", full))
    }

    func test大文字小文字の差は無視される() {
        XCTAssertTrue(Updater.isSameCommit("ABCDEF0", "abcdef0"))
    }

    func test異なるコミットは別物と判定される() {
        XCTAssertFalse(
            Updater.isSameCommit(
                "0123456789abcdef0123456789abcdef01234567",
                "fedcba9876543210fedcba9876543210fedcba98"))
    }

    func test空のコミットは同一と判定しない() {
        // 前方一致で比較するため、空文字を素通しすると常に一致してしまう
        XCTAssertFalse(Updater.isSameCommit("", "abcdef0"))
        XCTAssertFalse(Updater.isSameCommit("abcdef0", ""))
        XCTAssertFalse(Updater.isSameCommit("", ""))
    }

    func test短すぎるSHAは比較対象にしない() {
        // 最小長がないと、1文字の前方一致だけで同一と誤判定してしまう
        XCTAssertNil(Updater.normalizedCommit("abcde"))
        XCTAssertFalse(Updater.isSameCommit("a", "abcdef0123456"))
    }

    func test16進でない文字列はコミットとして扱わない() {
        // targetCommitish はブランチ名を返すことがある
        XCTAssertNil(Updater.normalizedCommit("main"))
        XCTAssertNil(Updater.normalizedCommit("feature/19-release"))
        XCTAssertFalse(Updater.isSameCommit("main", "main"))
    }

    func testリリースがブランチ名を指す場合は更新を促さない() {
        // 判定不能なまま更新を促すと、同じビルドの更新を延々と繰り返すことになる
        XCTAssertFalse(Updater.isUpdateAvailable(release(commit: "main")))
    }

    func testビルド元コミットが不明なら更新を促さない() {
        // テスト実行時は .app ではないため MBSourceCommit を持たない。
        // 不明なまま更新を促すと、毎回更新ダイアログが出てしまう
        XCTAssertNil(Updater.currentCommit)
        XCTAssertFalse(Updater.isUpdateAvailable(release(commit: "abcdef0")))
    }

    func test資産名が一致しないリリースはアセットなしと判定される() {
        XCTAssertTrue(release(commit: "abcdef0").hasAsset)
        XCTAssertFalse(release(commit: "abcdef0", assets: ["Other.zip"]).hasAsset)
        XCTAssertFalse(release(commit: "abcdef0", assets: []).hasAsset)
    }

    func test短縮表示は7文字になり不明な場合も表示できる() {
        XCTAssertEqual(Updater.shortCommit("0123456789abcdef"), "0123456")
        XCTAssertEqual(Updater.shortCommit(nil), "unknown")
        XCTAssertEqual(Updater.shortCommit(""), "unknown")
    }

    func test認証エラーはログインを促す文言になる() {
        let recovery = Updater.ghFailureRecovery("error: not logged in to any GitHub hosts")
        XCTAssertTrue(recovery.contains("gh auth login"))
    }

    func testリリース未公開のエラーは原因が分かる文言になる() {
        let recovery = Updater.ghFailureRecovery("release not found")
        XCTAssertTrue(recovery.contains("latest"))
    }

    func test想定外のエラーは出力をそのまま返す() {
        XCTAssertEqual(Updater.ghFailureRecovery("  boom  "), "boom")
        XCTAssertFalse(Updater.ghFailureRecovery("").isEmpty)
    }

    /// インストールが呼ばれたかを別スレッドからでも安全に記録する
    private final class InstallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var wasCalled: Bool { lock.withLock { value } }
        func record() { lock.withLock { value = true } }
    }

    /// インストールの呼び出しを記録する差し替え可能なコントローラを作る。
    /// 実際の更新判定を経由させるため、リリースのコミットは現在のビルドと必ず異なる値にする
    @MainActor
    private func makeController(_ recorder: InstallRecorder) -> UpdateController {
        let latest = release(commit: "abcdef0123456789abcdef0123456789abcdef01")
        return UpdateController(
            fetch: { .success(latest) },
            install: { _ in
                recorder.record()
                return nil
            },
            // テストは .app ではないため実際の判定は常に「更新なし」になる。
            // 同意の検証が目的なので、更新ありの状況を作る
            shouldOffer: { _ in true })
    }

    /// state が .checking から抜けるまで待つ(確認は非同期に走るため)
    @MainActor
    private func waitUntilSettled(_ controller: UpdateController) async {
        for _ in 0..<200 where controller.state.isBusy {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @MainActor
    func test自動インストールが無効なら確認だけでインストールしない() async {
        // Issue #22 の保証。設定をオフにしている限り、確認だけで適用されない
        let recorder = InstallRecorder()
        let controller = makeController(recorder)
        controller.automaticChecksEnabled = true
        controller.automaticInstallEnabled = false

        controller.checkAtLaunchIfEnabled()
        await waitUntilSettled(controller)

        XCTAssertFalse(recorder.wasCalled, "起動時の確認だけでインストールが実行された")
        XCTAssertNotNil(controller.state.availableRelease, "更新は検出されているべき")
    }

    @MainActor
    func test自動インストールが有効なら確認だけで適用される() async {
        // Issue #51 で利用者の指示により追加した挙動
        let recorder = InstallRecorder()
        let controller = makeController(recorder)
        controller.automaticInstallEnabled = true

        controller.check()
        await waitUntilSettled(controller)

        XCTAssertTrue(recorder.wasCalled, "自動インストールが有効なのに適用されなかった")
    }

    @MainActor
    func test明示的に呼んだときだけインストールされる() async {
        let recorder = InstallRecorder()
        let controller = makeController(recorder)
        controller.automaticInstallEnabled = false

        controller.check()
        await waitUntilSettled(controller)
        XCTAssertFalse(recorder.wasCalled)

        // パネルのボタンに相当する操作
        controller.installAvailableUpdate()
        await waitUntilSettled(controller)
        XCTAssertTrue(recorder.wasCalled, "同意操作をしてもインストールが実行されなかった")
    }

    @MainActor
    func test自動確認が無効なら確認自体を行わない() async {
        let recorder = InstallRecorder()
        let controller = makeController(recorder)
        controller.automaticInstallEnabled = false
        controller.automaticChecksEnabled = false

        controller.checkAtLaunchIfEnabled()
        await waitUntilSettled(controller)

        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(recorder.wasCalled)
    }

    @MainActor
    func test定期確認の間隔は数時間おきである() {
        // 頻繁に見に行くとネットワークと gh の起動が無駄に走る
        XCTAssertGreaterThanOrEqual(UpdateController.periodicCheckInterval, 60 * 60)
        XCTAssertLessThanOrEqual(UpdateController.periodicCheckInterval, 24 * 60 * 60)
    }

    @MainActor
    func test更新が無い状態でインストールを呼んでも何も起きない() {
        let controller = UpdateController()
        controller.installAvailableUpdate()
        // .installing に遷移しない(インストール対象が無いため)
        XCTAssertEqual(controller.state, .idle)
    }

    func test確認の失敗とインストールの失敗を区別する() {
        let checkFailure = UpdateState.checkFailed("gh が見つかりません")
        XCTAssertEqual(checkFailure.message, "確認できませんでした")
        XCTAssertEqual(checkFailure.failureDetail, "gh が見つかりません")
        XCTAssertNil(checkFailure.availableRelease)

        // インストール失敗後も、再試行できるよう対象を保持する
        let target = release(commit: "abcdef0123456")
        let installFailure = UpdateState.installFailed(target, "展開に失敗しました")
        XCTAssertEqual(installFailure.message, "インストールに失敗しました")
        XCTAssertEqual(installFailure.failureDetail, "展開に失敗しました")
        XCTAssertEqual(installFailure.availableRelease, target)
        XCTAssertFalse(installFailure.isBusy)
    }

    @MainActor
    func testビルド元コミットが不明なときは最新版ですと断言しない() {
        // 判定できないだけの状態を .upToDate にすると、改変ビルドでも
        // 「最新版です」と表示されてしまう
        let latest = release(commit: "abcdef0123456789abcdef0123456789abcdef01")
        let controller = UpdateController(
            fetch: { .success(latest) }, install: { _ in nil },
            shouldOffer: { _ in false }, isBuildIdentified: { false })

        controller.check()
        let expectation = XCTestExpectation()
        Task { @MainActor in
            for _ in 0..<200 where controller.state.isBusy {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)

        XCTAssertEqual(controller.state, .undeterminable)
        XCTAssertEqual(controller.state.message, "判定できません")
        XCTAssertNotNil(controller.state.failureDetail, "対処方法を示すべき")
    }

    @MainActor
    func testビルド元コミットが判明していれば最新版と表示する() {
        let latest = release(commit: "abcdef0123456789abcdef0123456789abcdef01")
        let controller = UpdateController(
            fetch: { .success(latest) }, install: { _ in nil },
            shouldOffer: { _ in false }, isBuildIdentified: { true })

        controller.check()
        let expectation = XCTestExpectation()
        Task { @MainActor in
            for _ in 0..<200 where controller.state.isBusy {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)

        XCTAssertEqual(controller.state, .upToDate)
    }

    func test資産の無いリリースは更新として提示しない() {
        // ボタンを出しても押した時点で失敗するだけなので提示条件から外す
        XCTAssertFalse(
            UpdateController.defaultOfferPolicy(
                release(commit: "abcdef0123456789abcdef0123456789abcdef01", assets: [])))
    }

    func test実行中の状態は操作を受け付けない() {
        XCTAssertTrue(UpdateState.checking.isBusy)
        XCTAssertTrue(UpdateState.installing.isBusy)
        XCTAssertFalse(UpdateState.idle.isBusy)
        XCTAssertFalse(UpdateState.upToDate.isBusy)
    }

    func testダウンロードURLはリポジトリと一致する() {
        XCTAssertEqual(Updater.repository, "sugasaki/memorybar")
        XCTAssertEqual(Updater.assetName, "MemoryBar.zip")
        XCTAssertEqual(
            Updater.releaseURL.absoluteString,
            "https://github.com/sugasaki/memorybar/releases/latest")
    }
}
