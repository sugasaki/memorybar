import Foundation

/// GitHub Releases からの更新確認・適用。
///
/// リポジトリが public なので**認証は要らない**。API もアセットも素の HTTPS で取れる。
/// アプリにトークンを持たせないのは変わらないが、そのために `gh` CLI へ委譲していた
/// 経路は廃した(gh が入っていないマシンでは更新できなかったため: Issue #75)。
enum Updater {
    static let repository = "sugasaki/memorybar"
    static let releaseTag = "latest"
    static let assetName = "MemoryBar.zip"
    /// 応答待ちの上限。無応答のまま状態が固まるのを防ぐ
    static let requestTimeout: TimeInterval = 60
    /// 外部コマンド(展開に使う ditto)の待ち上限
    static let commandTimeout: TimeInterval = 60

    /// 更新元のリリースページ(自動更新が失敗したときの手動導線)
    static var releaseURL: URL {
        URL(string: "https://github.com/\(repository)/releases/\(releaseTag)")!
    }

    /// リリース情報の取得先。未認証でも読める(公開リポジトリのため)
    static var releaseAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/tags/\(releaseTag)")!
    }

    /// 差し替え処理のログ。アプリ終了後に別プロセスが書くため、作業ディレクトリの外に置く
    static var installLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MemoryBar-update.log")
    }

    struct ReleaseInfo: Sendable, Equatable {
        /// リリースが指すコミット(このアプリのビルド元コミットと比較する)
        let commit: String
        let publishedAt: String
        let assetNames: [String]
        /// 資産のダウンロード先。名前から URL を組み立てず、API が返したものを使う
        let assetURL: URL?

        init(commit: String, publishedAt: String, assetNames: [String], assetURL: URL? = nil) {
            self.commit = commit
            self.publishedAt = publishedAt
            self.assetNames = assetNames
            self.assetURL = assetURL
        }

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

    // MARK: - 更新確認

    /// Info.plist に埋め込まれた生の値。`<sha>-dirty` のこともあるため表示専用
    static var rawCommit: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "MBSourceCommit") as? String
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// このアプリのビルド元コミット。比較に使えるSHAでなければ nil
    /// (未コミットの変更を含むビルドは `-dirty` が付くためここで弾かれる)
    static var currentCommit: String? {
        rawCommit.flatMap(normalizedCommit)
    }

    static func fetchLatestRelease() throws -> ReleaseInfo {
        let (data, response) = try fetch(releaseAPIURL)
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            throw UpdateError(
                "リリース情報を取得できませんでした。",
                recovery: httpFailureRecovery(response as? HTTPURLResponse))
        }
        return try parseRelease(data)
    }

    /// GitHub の Releases API の応答から必要な項目だけ取り出す
    static func parseRelease(_ data: Data) throws -> ReleaseInfo {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadURL: URL

                enum CodingKeys: String, CodingKey {
                    case name
                    case browserDownloadURL = "browser_download_url"
                }
            }
            let targetCommitish: String
            let publishedAt: String
            let assets: [Asset]

            enum CodingKeys: String, CodingKey {
                case targetCommitish = "target_commitish"
                case publishedAt = "published_at"
                case assets
            }
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw UpdateError("リリース情報の形式を解釈できませんでした。")
        }
        return ReleaseInfo(
            commit: payload.targetCommitish,
            publishedAt: payload.publishedAt,
            assetNames: payload.assets.map(\.name),
            assetURL: payload.assets.first { $0.name == assetName }?.browserDownloadURL)
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
        guard release.hasAsset, let assetURL = release.assetURL else {
            throw UpdateError("最新リリースに \(assetName) が見つかりませんでした。")
        }
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            throw UpdateError(
                ".app バンドルとして起動していないため自動更新できません。",
                recovery: "scripts/make-app.sh で生成した MemoryBar.app から起動してください。")
        }
        // Gatekeeper は検疫属性付きアプリを読み取り専用の場所へ隔離して起動する。
        // その状態では差し替えても次回起動に反映されない
        guard !appURL.path.contains("/AppTranslocation/") else {
            throw UpdateError(
                "アプリが隔離された場所から実行されているため更新できません。",
                recovery: "MemoryBar.app を /Applications へ移動してから再度お試しください。")
        }

        let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("memorybar-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        // どの経路で失敗しても作業ディレクトリを残さない
        var installerLaunched = false
        defer {
            if !installerLaunched { try? FileManager.default.removeItem(at: workDir) }
        }

        let archiveURL = workDir.appendingPathComponent(assetName)
        try downloadAsset(from: assetURL, to: archiveURL)

        // ditto は macOS 標準で、.app のメタデータを保ったまま展開できる
        let unpackDir = workDir.appendingPathComponent("unpacked")
        let unpack = try run(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            ["-x", "-k", archiveURL.path, unpackDir.path])
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

    /// 差し替え前に、取得したバンドルが本当に「別ビルドの MemoryBar」かを確認する。
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
                "ダウンロードしたバンドルが MemoryBar ではありません(\(newIdentifier ?? "不明"))。")
        }

        let newCommit = (info["MBSourceCommit"] as? String).flatMap(normalizedCommit)
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
            echo "=== MemoryBar update $(/bin/date) ==="

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
            # ダウンロード経路によっては検疫属性が付き、次回起動が隔離扱いになる
            /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true
            /bin/rm -rf "$BACKUP_PATH"
            BACKUP_PATH=""
            echo "更新しました: $APP_PATH"

            # ここから先の失敗は差し替え済みなので、戻さず前進させる
            # (trap を残すと再起動の失敗でロールバック扱いになり誤解を招く)
            trap - ERR
            if ! /usr/bin/open "$APP_PATH"; then
                echo "再起動に失敗しました。手動で MemoryBar を起動してください。"
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

    // MARK: - 取得

    /// 同期で取得する。呼び出し元(UpdateController / CLI)が既に別スレッドにいるため、
    /// ここを async にすると呼び出し側の構造を広く変えることになる
    private static func fetch(_ url: URL) throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        // GitHub の API は Accept でバージョンを固定できる。
        // 指定しないと将来の既定版が変わったときに黙って壊れうる
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MemoryBar", forHTTPHeaderField: "User-Agent")
        // 前回の応答が残っていると、公開直後の更新に気づけない
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let outcome = Outcome<(Data, URLResponse)>()
        let done = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let data, let response {
                outcome.set(.success((data, response)))
            } else {
                outcome.set(.failure(error ?? UpdateError("応答がありませんでした。")))
            }
            done.signal()
        }
        task.resume()
        // タイムアウトは URLRequest 側で効くが、待ち側にも上限を置いて固まらせない
        guard done.wait(timeout: .now() + requestTimeout + 5) == .success else {
            // 諦めた後も走り続けると、再試行のたびに通信が積み上がる
            task.cancel()
            throw UpdateError("\(Int(requestTimeout)) 秒以内に応答がありませんでした。")
        }
        switch outcome.take() {
        case .success(let value): return value
        case .failure(let error): throw networkError(error)
        case nil: throw UpdateError("応答がありませんでした。")
        }
    }

    /// 資産をファイルへ落とす。数MBあるためメモリに全部載せない
    private static func downloadAsset(from url: URL, to destination: URL) throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.setValue("MemoryBar", forHTTPHeaderField: "User-Agent")

        struct Downloaded { let staged: URL; let response: HTTPURLResponse? }
        let outcome = Outcome<Downloaded>()
        let done = DispatchSemaphore(value: 0)
        let task = URLSession.shared.downloadTask(with: request) { tempURL, urlResponse, error in
            defer { done.signal() }
            let http = urlResponse as? HTTPURLResponse
            guard let tempURL else {
                outcome.set(
                    .failure(
                        error
                            ?? UpdateError(
                                "更新のダウンロードに失敗しました。",
                                recovery: httpFailureRecovery(http))))
                return
            }
            // 完了ハンドラを抜けると消えるため、ここで退避する
            let staged = destination.appendingPathExtension("part")
            do {
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.moveItem(at: tempURL, to: staged)
                outcome.set(.success(Downloaded(staged: staged, response: http)))
            } catch {
                outcome.set(.failure(error))
            }
        }
        task.resume()
        guard done.wait(timeout: .now() + requestTimeout + 5) == .success else {
            task.cancel()
            throw UpdateError("\(Int(requestTimeout)) 秒以内にダウンロードが終わりませんでした。")
        }
        let downloaded: Downloaded
        switch outcome.take() {
        case .success(let value): downloaded = value
        case .failure(let error): throw networkError(error)
        case nil: throw UpdateError("更新のダウンロードに失敗しました。")
        }
        // 4xx/5xx でも本文がファイルとして落ちてくるため、状態行を必ず確かめる
        guard downloaded.response?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: downloaded.staged)
            throw UpdateError(
                "更新のダウンロードに失敗しました。",
                recovery: httpFailureRecovery(downloaded.response))
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: downloaded.staged, to: destination)
    }

    /// 完了ハンドラとの受け渡し。セマフォで待ち合わせるので同時に触ることはないが、
    /// コンパイラには見えないため錠を持たせて明示する
    private final class Outcome<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Result<Value, Error>?

        func set(_ value: Result<Value, Error>) {
            lock.lock()
            defer { lock.unlock() }
            stored = value
        }

        /// 取り出したら手放す。名前どおり一度きりにして、
        /// 受け取った Data を用が済んだ後も抱え込まないようにする
        func take() -> Result<Value, Error>? {
            lock.lock()
            defer { lock.unlock() }
            let value = stored
            stored = nil
            return value
        }
    }

    /// 通信の失敗を、利用者が対処を判断できる文言にする
    static func networkError(_ error: Error) -> UpdateError {
        if let error = error as? UpdateError { return error }
        let urlError = error as? URLError
        switch urlError?.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed:
            return UpdateError(
                "GitHub に接続できませんでした。", recovery: "ネットワークの状態を確認して、もう一度お試しください。")
        case .timedOut:
            return UpdateError(
                "接続がタイムアウトしました。", recovery: "しばらく待ってから、もう一度お試しください。")
        default:
            return UpdateError(error.localizedDescription)
        }
    }

    /// HTTP の応答から対処を導く
    static func httpFailureRecovery(_ response: HTTPURLResponse?) -> String {
        guard let status = response?.statusCode else {
            return "GitHub からの応答を確認できませんでした。"
        }
        switch status {
        case 404:
            return "まだ \(releaseTag) リリースが公開されていない可能性があります。"
        case 403, 429:
            // 未認証のアクセスは 60回/時 に制限される。自動確認は6時間おきなので
            // 通常は当たらないが、同じ回線から何度も試すと当たりうる
            return "GitHub の利用制限に達した可能性があります。しばらく待ってから、もう一度お試しください。"
        default:
            return "GitHub が \(status) を返しました。しばらく待ってから、もう一度お試しください。"
        }
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

}
