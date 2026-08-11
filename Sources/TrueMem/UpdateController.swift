import AppKit
import SwiftUI

/// 更新確認の進行状態。UI はこれだけを見る
enum UpdateState: Sendable, Equatable {
    case idle
    case checking
    case upToDate
    case available(Updater.ReleaseInfo)
    case failed(String)

    var message: String {
        switch self {
        case .idle: ""
        case .checking: "確認中…"
        case .upToDate: "最新版です"
        case .available: "新しいバージョンがあります"
        case .failed(let reason): reason
        }
    }
}

@Observable
@MainActor
final class UpdateController {
    static let automaticCheckDefaultsKey = "automaticUpdateChecks"

    private(set) var state: UpdateState = .idle

    var automaticChecksEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                automaticChecksEnabled, forKey: Self.automaticCheckDefaultsKey)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        // 未設定なら有効。register ではなく明示的に既定値を決める
        if defaults.object(forKey: Self.automaticCheckDefaultsKey) == nil {
            automaticChecksEnabled = true
        } else {
            automaticChecksEnabled = defaults.bool(forKey: Self.automaticCheckDefaultsKey)
        }
    }

    /// 起動時の自動確認。無効化されている場合と、更新が無い場合は何も表示しない
    func checkAtLaunchIfEnabled() {
        guard automaticChecksEnabled else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard state != .checking else { return }
        state = .checking
        Task {
            let result = await Self.fetchLatest()
            switch result {
            case .success(let release):
                if Updater.isUpdateAvailable(release) {
                    state = .available(release)
                    promptToInstall(release)
                } else {
                    state = .upToDate
                    if userInitiated {
                        Self.showInfo(
                            title: "最新版です",
                            message: "現在のバージョン (\(Self.currentVersionLabel)) が最新です。")
                    }
                }
            case .failure(let error):
                state = .failed(error.errorDescription ?? "更新を確認できませんでした")
                // 自動確認の失敗でダイアログを出すと、gh 未導入の環境で毎回邪魔になる
                if userInitiated {
                    Self.showError(
                        title: "更新を確認できませんでした",
                        message: [error.errorDescription, error.recoverySuggestion]
                            .compactMap { $0 }.joined(separator: "\n\n"))
                }
            }
        }
    }

    private func promptToInstall(_ release: Updater.ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "新しいバージョンがあります"
        alert.informativeText = """
            現在: \(Self.currentVersionLabel)
            最新: \(Updater.shortCommit(release.commit))

            ダウンロードしてインストールしますか?
            インストール後、TrueMem は自動的に再起動します。
            """
        alert.addButton(withTitle: "インストール")
        alert.addButton(withTitle: "後で")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            // 成功時はプロセスが終了するため、以降は実行されない
            try Updater.downloadAndInstall(release)
        } catch let error as Updater.UpdateError {
            state = .failed(error.errorDescription ?? "インストールに失敗しました")
            Self.showError(
                title: "インストールに失敗しました",
                message: [error.errorDescription, error.recoverySuggestion]
                    .compactMap { $0 }.joined(separator: "\n\n"))
        } catch {
            state = .failed(error.localizedDescription)
            Self.showError(title: "インストールに失敗しました", message: error.localizedDescription)
        }
    }

    /// gh の実行はブロッキングなので、メインスレッドを止めないよう別スレッドで行う
    private static func fetchLatest() async -> Result<Updater.ReleaseInfo, Updater.UpdateError> {
        await Task.detached {
            do {
                return .success(try Updater.fetchLatestRelease())
            } catch let error as Updater.UpdateError {
                return .failure(error)
            } catch {
                return .failure(Updater.UpdateError(error.localizedDescription))
            }
        }.value
    }

    /// Bundle の読み取りのみで状態を持たないため、CLI(非 MainActor)からも参照できる
    nonisolated static var currentVersionLabel: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "\(version) (\(Updater.shortCommit(Updater.currentCommit)))"
    }

    private static func showInfo(title: String, message: String) {
        showAlert(title: title, message: message, style: .informational)
    }

    private static func showError(title: String, message: String) {
        showAlert(title: title, message: message, style: .warning)
    }

    private static func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
