import Foundation

/// GitHub Releases からの更新確認・適用。
///
/// リポジトリが private のため認証が要るが、**アプリにトークンを持たせない**。
/// 認証済みの `gh` CLI に委譲することで、資格情報の管理を GitHub CLI 側に任せる。
enum Updater {
    static let repository = "sugasaki/truemem"
    static let releaseTag = "latest"
    static let assetName = "TrueMem.zip"
    /// gh の応答待ちの上限。無応答のまま状態が固まるのを防ぐ
    static let commandTimeout: TimeInterval = 60

    /// 更新元のリリースページ(自動更新が失敗したときの手動導線)
    static var releaseURL: URL {
        URL(string: "https://github.com/\(repository)/releases/\(releaseTag)")!
    }

    /// 差し替え処理のログ。アプリ終了後に別プロセスが書くため、作業ディレクトリの外に置く
    static var installLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/TrueMem-update.log")
    }

    struct ReleaseInfo: Sendable, Equatable {
        /// リリースが指すコミット(このアプリのビルド元コミットと比較する)
        let commit: String
        let publishedAt: String
        let assetNames: [String]

        var hasAsset: Bool { assetNames.contains(Updater.assetName) }
    }

    struct UpdateError: LocalizedError {
        let errorDescription: String?
        let recoverySuggestion: String?

        init(_ description: String, recovery: String? = nil) {
            self.errorDescription = description
            self.recoverySuggestion = recovery
        }
    }

    // MARK: - gh CLI の探索

    /// GUI から起動した .app は PATH を継承しないため、既知の場所を明示的に探す。
    /// (Finder 起動時の PATH は /usr/bin:/bin:/usr/sbin:/sbin のみで gh は含まれない)
    static func locateGH() -> URL? {
        var candidates = [
            "/opt/homebrew/bin/gh",  // Apple Silicon の Homebrew
            "/usr/local/bin/gh",  // Intel の Homebrew
            "/opt/local/bin/gh",  // MacPorts
        ]
        // ターミナルから起動された場合は PATH も尊重する。
        // 相対パス由来の候補は cwd 次第で別物を実行しうるため除外する
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":")
                .filter { $0.hasPrefix("/") }
                .map { "\($0)/gh" }
        }
        return candidates.lazy
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
            .first
            .map { URL(fileURLWithPath: $0) }
    }

    private static func requireGH() throws -> URL {
        guard let gh = locateGH() else {
            throw UpdateError(
                "GitHub CLI (gh) が見つかりません。",
                recovery: "`brew install gh` でインストールし、`gh auth login` で認証してください。")
        }
        return gh
    }

    // MARK: - 更新確認

    /// このアプリのビルド元コミット(`make-app.sh` が Info.plist に埋め込む)
    static var currentCommit: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TMSourceCommit") as? String
        else { return nil }
        return normalizedCommit(value)
    }

    static func fetchLatestRelease() throws -> ReleaseInfo {
        let gh = try requireGH()
        let result = try run(
            gh,
            [
                "release", "view", releaseTag,
                "--repo", repository,
                "--json", "targetCommitish,publishedAt,assets",
            ])
        guard result.isSuccess else {
            throw UpdateError(
                "リリース情報を取得できませんでした。",
                recovery: ghFailureRecovery(result.output))
        }

        struct Payload: Decodable {
            struct Asset: Decodable { let name: String }
            let targetCommitish: String
            let publishedAt: String
            let assets: [Asset]
        }
        guard let data = result.output.data(using: .utf8),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            throw UpdateError("リリース情報の形式を解釈できませんでした。")
        }
        return ReleaseInfo(
            commit: payload.targetCommitish,
            publishedAt: payload.publishedAt,
            assetNames: payload.assets.map(\.name))
    }

    /// 更新の要否。
    /// 自分のビルド元コミットが不明な場合と、リリース側がコミットSHAでない場合
    /// (`targetCommitish` はブランチ名を返すことがある)は、更新を促さない。
    /// 判定不能なまま促すと、同じビルドの更新を延々と繰り返すことになるため。
    static func isUpdateAvailable(_ release: ReleaseInfo) -> Bool {
        guard let current = currentCommit,
            let latest = normalizedCommit(release.commit)
        else { return false }
        return !isSameCommit(current, latest)
    }

    /// 一方が短縮SHAでも比較できるようにする。
    /// SHA として妥当でない文字列(ブランチ名など)は比較対象にしない
    static func isSameCommit(_ lhs: String, _ rhs: String) -> Bool {
        guard let a = normalizedCommit(lhs), let b = normalizedCommit(rhs) else { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    /// コミットSHAとして妥当なら小文字化して返す。短縮SHAの最小長(7)を下回るものは弾く
    static func normalizedCommit(_ value: String) -> String? {
        let lowered = value.lowercased()
        guard lowered.count >= 7, lowered.allSatisfy(\.isHexDigit) else { return nil }
        return lowered
    }

    static func shortCommit(_ commit: String?) -> String {
        guard let commit, !commit.isEmpty else { return "unknown" }
        return String(commit.prefix(7))
    }

    // MARK: - 更新の適用

    /// 新版をダウンロードして展開・検証し、入れ替えスクリプトを起動してアプリを終了する。
    /// 自分自身を置き換えるため、実際の差し替えは別プロセスに任せる。
    static func downloadAndInstall(_ release: ReleaseInfo) throws {
        guard release.hasAsset else {
            throw UpdateError("最新リリースに \(assetName) が見つかりませんでした。")
        }
        let gh = try requireGH()
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            throw UpdateError(
                ".app バンドルとして起動していないため自動更新できません。",
                recovery: "scripts/make-app.sh で生成した TrueMem.app から起動してください。")
        }
        // Gatekeeper は検疫属性付きアプリを読み取り専用の場所へ隔離して起動する。
        // その状態では差し替えても次回起動に反映されない
        guard !appURL.path.contains("/AppTranslocation/") else {
            throw UpdateError(
                "アプリが隔離された場所から実行されているため更新できません。",
                recovery: "TrueMem.app を /Applications へ移動してから再度お試しください。")
        }

        let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("truemem-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        // どの経路で失敗しても作業ディレクトリを残さない
        var installerLaunched = false
        defer {
            if !installerLaunched { try? FileManager.default.removeItem(at: workDir) }
        }

        let download = try run(
            gh,
            [
                "release", "download", releaseTag,
                "--repo", repository,
                "--pattern", assetName,
                "--dir", workDir.path,
            ])
        guard download.isSuccess else {
            throw UpdateError(
                "更新のダウンロードに失敗しました。", recovery: ghFailureRecovery(download.output))
        }

        // ditto は macOS 標準で、.app のメタデータを保ったまま展開できる
        let unpackDir = workDir.appendingPathComponent("unpacked")
        let unpack = try run(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            ["-x", "-k", workDir.appendingPathComponent(assetName).path, unpackDir.path])
        guard unpack.isSuccess else {
            throw UpdateError("更新パッケージを展開できませんでした。\n\(unpack.output)")
        }

        let newAppURL = try locateUnpackedApp(in: unpackDir)
        // 同意した版と、実際に降ってきた版が一致することを確かめる。
        // ダウンロードは常に latest を取るため、確認からインストールまでの間に
        // リリースが差し替わっていると別のビルドが入りうる
        try verifyReplacement(newAppURL: newAppURL, expectedCommit: release.commit)

        try launchInstaller(appURL: appURL, newAppURL: newAppURL, workDir: workDir)
        installerLaunched = true
        // 差し替え直前にトグルした設定が失われないよう、終了前に書き出す
        UserDefaults.standard.synchronize()
        exit(0)
    }

    /// 展開結果から .app を探す。アプリ名の変更に依存しないよう拡張子で探す
    private static func locateUnpackedApp(in unpackDir: URL) throws -> URL {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: unpackDir, includingPropertiesForKeys: nil)) ?? []
        guard let appURL = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError("展開結果に .app が含まれていませんでした。")
        }
        return appURL
    }

    /// 差し替え前に、取得したバンドルが本当に「別ビルドの TrueMem」かを確認する。
    /// GitHub の targetCommitish はタグが既存だと更新されない仕様があるため、
    /// リリースのメタデータだけを信じると同じビルドを延々と再インストールしうる
    private static func verifyReplacement(newAppURL: URL, expectedCommit: String) throws {
        let plistURL = newAppURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
            let info = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else {
            throw UpdateError("ダウンロードしたバンドルの Info.plist を読めませんでした。")
        }

        let newIdentifier = info["CFBundleIdentifier"] as? String
        guard newIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError(
                "ダウンロードしたバンドルが TrueMem ではありません(\(newIdentifier ?? "不明"))。")
        }

        let newCommit = (info["TMSourceCommit"] as? String).flatMap(normalizedCommit)
        if let newCommit, let current = currentCommit, isSameCommit(newCommit, current) {
            throw UpdateError(
                "配布されている版は現在と同じビルドでした。",
                recovery: "リリースがまだ更新されていない可能性があります。しばらく待って再度お試しください。")
        }
        // 同意した対象と違うものを黙って入れない
        if let newCommit, let expected = normalizedCommit(expectedCommit),
            !isSameCommit(newCommit, expected)
        {
            throw UpdateError(
                "確認した版 (\(shortCommit(expected))) と配布物 (\(shortCommit(newCommit))) が一致しません。",
                recovery: "その後にリリースが更新された可能性があります。もう一度「更新を確認」してください。")
        }
    }

    /// アプリ終了を待ってから差し替え、再起動するスクリプトを起動する。
    /// 失敗時は退避した旧バンドルへ戻し、必ずアプリを再起動する(黙って消えないようにする)
    private static func launchInstaller(appURL: URL, newAppURL: URL, workDir: URL) throws {
        let scriptURL = workDir.appendingPathComponent("install.sh")
        // 値はすべて引数として渡し、スクリプト本文へ文字列補間しない
        // (パスに空白・引用符・$ が含まれても壊れないようにするため)
        let script = """
            #!/bin/bash
            set -euo pipefail
            APP_PATH="$1"
            NEW_APP_PATH="$2"
            WORK_DIR="$3"
            PARENT_PID="$4"
            LOG_PATH="$5"

            /bin/mkdir -p "$(/usr/bin/dirname "$LOG_PATH")"
            exec >>"$LOG_PATH" 2>&1
            echo "=== TrueMem update $(/bin/date) ==="

            BACKUP_PATH=""
            rollback() {
                echo "更新に失敗しました。元のバージョンへ戻します。"
                if [ -n "$BACKUP_PATH" ] && [ -d "$BACKUP_PATH" ]; then
                    /bin/rm -rf "$APP_PATH"
                    /bin/mv "$BACKUP_PATH" "$APP_PATH"
                fi
                /usr/bin/open "$APP_PATH" || true
                exit 1
            }
            trap rollback ERR

            # 旧プロセスの終了を待つ(最大10秒)
            alive=1
            for _ in $(/usr/bin/seq 1 100); do
                if ! /bin/kill -0 "$PARENT_PID" 2>/dev/null; then
                    alive=0
                    break
                fi
                /bin/sleep 0.1
            done
            # 終了しないまま上書きすると、実行中のバンドルを壊したうえに
            # open が旧インスタンスを前面に出すだけで「更新済み」に見えてしまう
            if [ "$alive" -eq 1 ]; then
                echo "旧プロセスが終了しないため中止しました (pid=$PARENT_PID)"
                /usr/bin/open "$APP_PATH" || true
                exit 1
            fi

            # ditto はマージするため、旧版のファイルが残って署名シールが壊れる。
            # 退避してから展開し、置換になるようにする
            BACKUP_CANDIDATE="${APP_PATH}.old-$$"
            /bin/mv "$APP_PATH" "$BACKUP_CANDIDATE"
            BACKUP_PATH="$BACKUP_CANDIDATE"
            /usr/bin/ditto "$NEW_APP_PATH" "$APP_PATH"
            # gh 経由のダウンロードには付かないが、念のため検疫属性を除去する
            /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true
            /bin/rm -rf "$BACKUP_PATH"
            BACKUP_PATH=""
            echo "更新しました: $APP_PATH"

            # ここから先の失敗は差し替え済みなので、戻さず前進させる
            # (trap を残すと再起動の失敗でロールバック扱いになり誤解を招く)
            trap - ERR
            if ! /usr/bin/open "$APP_PATH"; then
                echo "再起動に失敗しました。手動で TrueMem を起動してください。"
            fi
            /bin/rm -rf "$WORK_DIR"
            """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path, appURL.path, newAppURL.path, workDir.path,
            String(ProcessInfo.processInfo.processIdentifier), installLogURL.path,
        ]
        try process.run()
    }

    // MARK: - プロセス実行

    private struct CommandResult {
        let status: Int32
        let output: String
        var isSuccess: Bool { status == 0 }
    }

    private static func run(_ executable: URL, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        // 親の stdin を継承すると、子プロセスが入力待ちで止まりうる
        process.standardInput = FileHandle.nullDevice
        try process.run()

        // 応答が無いまま状態が固まるのを防ぐ
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + commandTimeout, execute: timeout)

        // 先に読み切ってから待つ(パイプが埋まるとデッドロックするため)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let timedOut = timeout.isCancelled == false && process.terminationReason == .uncaughtSignal
        timeout.cancel()

        let output = String(data: data, encoding: .utf8) ?? ""
        return CommandResult(
            status: process.terminationStatus,
            output: timedOut ? "\(commandTimeout) 秒以内に応答がありませんでした。\n\(output)" : output)
    }

    /// gh の失敗理由を利用者が対処できる文言に変換する
    static func ghFailureRecovery(_ output: String) -> String {
        let lowered = output.lowercased()
        if lowered.contains("auth") || lowered.contains("logged in")
            || lowered.contains("authentication")
        {
            return "`gh auth login` で GitHub にログインしてください。"
        }
        if lowered.contains("release not found") || lowered.contains("not found") {
            return "まだ \(releaseTag) リリースが公開されていない可能性があります。"
        }
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "gh コマンドが失敗しました。" : detail
    }
}
