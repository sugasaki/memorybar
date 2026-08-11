import XCTest

@testable import TrueMem

final class UpdaterTests: XCTestCase {
    private func release(commit: String, assets: [String] = ["TrueMem.zip"]) -> Updater.ReleaseInfo
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
        // テスト実行時は .app ではないため TMSourceCommit を持たない。
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

    @MainActor
    func test更新が見つかってもインストールは自動で始まらない() {
        // 起動時の自動確認で勝手にインストールされないこと(Issue #22 の回帰防止)。
        // 同意はパネルのボタン操作のみで、状態は .available に留まる
        let controller = UpdateController()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.state.availableRelease)

        let state = UpdateState.available(release(commit: "abcdef0123456"))
        XCTAssertNotNil(state.availableRelease)
        XCTAssertFalse(state.isBusy)
        XCTAssertEqual(state.message, "新しいバージョンがあります")
    }

    @MainActor
    func test更新が無い状態でインストールを呼んでも何も起きない() {
        let controller = UpdateController()
        controller.installAvailableUpdate()
        // .installing に遷移しない(インストール対象が無いため)
        XCTAssertEqual(controller.state, .idle)
    }

    func test失敗状態は詳細を保持し実行中とみなさない() {
        let state = UpdateState.failed("gh が見つかりません")
        XCTAssertEqual(state.failureDetail, "gh が見つかりません")
        XCTAssertFalse(state.isBusy)
        XCTAssertNil(state.availableRelease)
    }

    func test実行中の状態は操作を受け付けない() {
        XCTAssertTrue(UpdateState.checking.isBusy)
        XCTAssertTrue(UpdateState.installing.isBusy)
        XCTAssertFalse(UpdateState.idle.isBusy)
        XCTAssertFalse(UpdateState.upToDate.isBusy)
    }

    func testダウンロードURLはリポジトリと一致する() {
        XCTAssertEqual(Updater.repository, "sugasaki/truemem")
        XCTAssertEqual(Updater.assetName, "TrueMem.zip")
        XCTAssertEqual(
            Updater.releaseURL.absoluteString,
            "https://github.com/sugasaki/truemem/releases/latest")
    }
}
