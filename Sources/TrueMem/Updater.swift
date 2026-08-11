import Foundation

/// GitHub Releases からの更新確認・適用。
///
/// リポジトリが private のため認証が要るが、**アプリにトークンを持たせない**。
/// 認証済みの `gh` CLI に委譲することで、資格情報の管理を GitHub CLI 側に任せる。
enum Updater {
    static let repository = "sugasaki/truemem"
    static let releaseTag = "latest"
    static let assetName = "TrueMem.zip"

    /// 更新元のリリースページ(手動確認用)
    static var releaseURL: URL {
        URL(string: "https://github.com/\(repository)/releases/\(releaseTag)")!
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
        // ターミナルから起動された場合は PATH も尊重する
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/gh" }
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
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TMSourceCommit") as? String,
            value != "unknown", !value.isEmpty
        else { return nil }
        return value
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

    /// 更新の要否。ビルド元コミットが不明な場合は誤って更新を促さない
    static func isUpdateAvailable(_ release: ReleaseInfo) -> Bool {
        guard let current = currentCommit else { return false }
        return !isSameCommit(current, release.commit)
    }

    /// 一方が短縮SHAでも比較できるようにする
    static func isSameCommit(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.lowercased()
        let b = rhs.lowercased()
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    static func shortCommit(_ commit: String?) -> String {
        guard let commit, !commit.isEmpty else { return "unknown" }
        return String(commit.prefix(7))
    }

    // MARK: - 更新の適用

    /// 新版をダウンロードして展開し、入れ替えスクリプトを起動する。
    /// 自分自身を置き換えるため、実際の差し替えは別プロセスに任せてアプリは終了する。
    static func downloadAndInstall(_ release: ReleaseInfo) throws -> Never {
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

        let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("truemem-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let download = try run(
            gh,
            [
                "release", "download", releaseTag,
                "--repo", repository,
                "--pattern", assetName,
                "--dir", workDir.path,
            ])
        guard download.isSuccess else {
            try? FileManager.default.removeItem(at: workDir)
            throw UpdateError(
                "更新のダウンロードに失敗しました。", recovery: ghFailureRecovery(download.output))
        }

        // ditto は macOS 標準で、.app のメタデータを保ったまま展開できる
        let unpackDir = workDir.appendingPathComponent("unpacked")
        let unpack = try run(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            ["-x", "-k", workDir.appendingPathComponent(assetName).path, unpackDir.path])
        guard unpack.isSuccess else {
            try? FileManager.default.removeItem(at: workDir)
            throw UpdateError("更新パッケージを展開できませんでした。\n\(unpack.output)")
        }

        let newAppURL = unpackDir.appendingPathComponent(appURL.lastPathComponent)
        guard FileManager.default.fileExists(atPath: newAppURL.path) else {
            try? FileManager.default.removeItem(at: workDir)
            throw UpdateError("展開結果に \(appURL.lastPathComponent) が含まれていません。")
        }

        try launchInstaller(appURL: appURL, newAppURL: newAppURL, workDir: workDir)
        exit(0)
    }

    /// アプリ終了を待ってから差し替え、再起動するスクリプトを起動する
    private static func launchInstaller(appURL: URL, newAppURL: URL, workDir: URL) throws {
        let scriptURL = workDir.appendingPathComponent("install.sh")
        // 引数はスクリプト側で "$1" 等として受け取り、パスに空白があっても壊れないようにする
        let script = """
            #!/bin/bash
            set -euo pipefail
            APP_PATH="$1"
            NEW_APP_PATH="$2"
            WORK_DIR="$3"
            PARENT_PID="$4"

            # 旧プロセスの終了を待つ(最大10秒)
            for _ in $(seq 1 100); do
                /bin/kill -0 "$PARENT_PID" 2>/dev/null || break
                /bin/sleep 0.1
            done

            /usr/bin/ditto "$NEW_APP_PATH" "$APP_PATH"
            # gh 経由のダウンロードには付かないが、念のため検疫属性を除去する
            /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true
            /usr/bin/open "$APP_PATH"
            /bin/rm -rf "$WORK_DIR"
            """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path, appURL.path, newAppURL.path, workDir.path,
            String(ProcessInfo.processInfo.processIdentifier),
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
        try process.run()
        // 先に読み切ってから待つ(パイプが埋まるとデッドロックするため)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? "")
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
