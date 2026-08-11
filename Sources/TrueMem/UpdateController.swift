import AppKit
import SwiftUI

/// 更新確認の進行状態。UI はこれだけを見る
enum UpdateState: Sendable, Equatable {
    case idle
    case checking
    case installing
    case upToDate
    case available(Updater.ReleaseInfo)
    case checkFailed(String)
    /// インストールの失敗。再試行できるよう対象のリリースを保持する
    case installFailed(Updater.ReleaseInfo, String)

    var message: String {
        switch self {
        case .idle: ""
        case .checking: "確認中…"
        case .installing: "インストール中…"
        case .upToDate: "最新版です"
        case .available: "新しいバージョンがあります"
        case .checkFailed: "確認できませんでした"
        case .installFailed: "インストールに失敗しました"
        }
    }

    /// 実行中は操作を受け付けない
    var isBusy: Bool { self == .checking || self == .installing }

    /// インストール可能な対象。失敗後も再試行できるようにする
    var availableRelease: Updater.ReleaseInfo? {
        switch self {
        case .available(let release), .installFailed(let release, _): release
        default: nil
        }
    }

    var failureDetail: String? {
        switch self {
        case .checkFailed(let detail), .installFailed(_, let detail): detail
        default: nil
        }
    }
}

@Observable
@MainActor
final class UpdateController {
    /// アプリ起動時の確認を確実に一度だけ行うため、単一のインスタンスを共有する
    static let shared = UpdateController()

    static let automaticCheckDefaultsKey = "automaticUpdateChecks"

    typealias FetchHandler = @Sendable () async -> Result<Updater.ReleaseInfo, Updater.UpdateError>
    typealias InstallHandler = @Sendable (Updater.ReleaseInfo) async -> Updater.UpdateError?
    typealias OfferPolicy = @Sendable (Updater.ReleaseInfo) -> Bool

    /// 更新として提示する条件。資産の無いリリースは押しても失敗するだけなので提示しない
    nonisolated static let defaultOfferPolicy: OfferPolicy = { release in
        Updater.isUpdateAvailable(release) && release.hasAsset
    }

    private(set) var state: UpdateState = .idle
    private var hasCheckedAtLaunch = false
    // 「確認しただけでインストールされない」ことをテストで固定するための差し込み口
    private let fetchHandler: FetchHandler
    private let installHandler: InstallHandler
    private let shouldOffer: OfferPolicy

    var automaticChecksEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                automaticChecksEnabled, forKey: Self.automaticCheckDefaultsKey)
        }
    }

    init(
        fetch: @escaping FetchHandler = { await UpdateController.fetchLatest() },
        install: @escaping InstallHandler = { await UpdateController.performInstall($0) },
        shouldOffer: @escaping OfferPolicy = UpdateController.defaultOfferPolicy
    ) {
        self.fetchHandler = fetch
        self.installHandler = install
        self.shouldOffer = shouldOffer
        let defaults = UserDefaults.standard
        // 未設定なら有効。register ではなく明示的に既定値を決める
        if defaults.object(forKey: Self.automaticCheckDefaultsKey) == nil {
            automaticChecksEnabled = true
        } else {
            automaticChecksEnabled = defaults.bool(forKey: Self.automaticCheckDefaultsKey)
        }
    }

    /// 起動時の自動確認。**確認するだけで、インストールはしない**
    func checkAtLaunchIfEnabled() {
        guard !hasCheckedAtLaunch else { return }
        hasCheckedAtLaunch = true
        guard automaticChecksEnabled else { return }
        check()
    }

    /// 更新の有無を調べて状態に反映する。
    /// 結果はメニューパネルに表示し、モーダルダイアログは使わない。
    /// メニューバー常駐アプリでは `NSAlert.runModal()` が操作を待たずに戻ることがあり、
    /// 同意の確認手段として信頼できないため（Issue #22）
    func check() {
        guard !state.isBusy else { return }
        state = .checking
        Task {
            switch await fetchHandler() {
            case .success(let release):
                state = shouldOffer(release) ? .available(release) : .upToDate
            case .failure(let error):
                state = .checkFailed(Self.detail(of: error))
            }
        }
    }

    /// 実際のインストール。**パネル上のボタンが押されたときにのみ呼ぶ**（この操作が同意そのもの）
    func installAvailableUpdate() {
        guard let release = state.availableRelease else { return }
        state = .installing
        Task {
            // 成功するとプロセスが終了するため、戻ってくるのは失敗したときだけ
            if let error = await installHandler(release) {
                state = .installFailed(release, Self.detail(of: error))
            }
        }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(Updater.releaseURL)
    }

    /// gh の実行とダウンロードはブロッキングなので、メインスレッドを止めないよう別スレッドで行う
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

    private static func performInstall(_ release: Updater.ReleaseInfo) async -> Updater.UpdateError?
    {
        await Task.detached {
            do {
                try Updater.downloadAndInstall(release)
                return nil
            } catch let error as Updater.UpdateError {
                return error
            } catch {
                return Updater.UpdateError(error.localizedDescription)
            }
        }.value
    }

    private static func detail(of error: Updater.UpdateError) -> String {
        [error.errorDescription, error.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Bundle の読み取りのみで状態を持たないため、CLI(非 MainActor)からも参照できる
    nonisolated static var currentVersionLabel: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "\(version) (\(Updater.shortCommit(Updater.currentCommit)))"
    }
}
