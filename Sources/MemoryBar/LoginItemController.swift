import Foundation
import Observation
import ServiceManagement

/// ログイン項目APIをテストから差し替えられるようにする最小の境界。
/// 状態の正本は UserDefaults ではなく、Service Management が返す実際の登録状態に置く。
@MainActor
struct LoginItemService {
    enum Status: Equatable {
        case enabled
        case requiresApproval
        case notRegistered
        case notFound
        case unknown
    }

    let status: () -> Status
    let register: () throws -> Void
    let unregister: () throws -> Void
    let openSystemSettings: () -> Void

    static let live = LoginItemService(
        status: {
            switch SMAppService.mainApp.status {
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            case .notRegistered: .notRegistered
            case .notFound: .notFound
            @unknown default: .unknown
            }
        },
        register: { try SMAppService.mainApp.register() },
        unregister: { try SMAppService.mainApp.unregister() },
        openSystemSettings: { SMAppService.openSystemSettingsLoginItems() })
}

/// 「ログイン時に開く」の表示状態と、初回だけ既定ONにする処理を管理する。
@Observable
@MainActor
final class LoginItemController {
    static let shared = LoginItemController()
    /// このアプリで一度ON/OFFを確定したことを示すキー。
    /// 単なる初期値を保存するのではなく、利用者がOFFにした設定を次回起動で戻さないために使う。
    static let configuredKey = "loginItemConfigured"

    private let service: LoginItemService
    private let defaults: UserDefaults
    private(set) var status: LoginItemService.Status
    private(set) var failureDetail: String?

    init(service: LoginItemService = .live, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        status = service.status()
    }

    /// 登録済みだがOS側の許可待ちの場合も、アプリ内で選んだ設定としてはONと表示する。
    /// 実際にはまだ起動しないことを statusMessage と設定画面への導線で明示する。
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool { status == .requiresApproval }

    var statusMessage: String? {
        if let failureDetail { return failureDetail }
        switch status {
        case .requiresApproval:
            return "登録済みですが、システム設定での許可が必要です。"
        case .unknown:
            return "ログイン項目の状態を確認できませんでした。"
        case .enabled, .notRegistered, .notFound:
            return nil
        }
    }

    /// 初回だけ既定ONを登録する。明示的にOFFへ切り替えた後は configuredKey が残るため、
    /// 次回起動で勝手に再登録しない。登録に失敗した場合は、.app からの次回起動で再試行する。
    func enableByDefaultIfNeeded() {
        refresh()
        guard !defaults.bool(forKey: Self.configuredKey) else { return }
        apply(enabled: true)
    }

    func setEnabled(_ enabled: Bool) {
        apply(enabled: enabled)
    }

    /// システム設定で利用者が変更した状態を、パネルを開いたときに取り込む。
    func refresh() {
        let previous = status
        status = service.status()
        if status != previous { failureDetail = nil }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }

    private func apply(enabled: Bool) {
        failureDetail = nil
        refresh()

        do {
            if enabled {
                switch status {
                case .enabled, .requiresApproval:
                    break
                // mainApp は初回登録前に .notFound を返すことがある。
                // 登録不能とは決めつけず、実際に register() を試す。
                case .notRegistered, .notFound:
                    try service.register()
                case .unknown:
                    throw LoginItemError("ログイン項目の状態を確認できません。")
                }
            } else {
                switch status {
                case .enabled, .requiresApproval:
                    try service.unregister()
                case .notRegistered, .notFound:
                    break
                case .unknown:
                    throw LoginItemError("ログイン項目の状態を確認できません。")
                }
            }
            finishChange(requestedEnabled: enabled)
        } catch {
            // APIがエラーを返しても、別経路で既に目的の状態になっている場合がある。
            // 最後に実状態を読み直してから失敗として扱う。
            status = service.status()
            if matches(requestedEnabled: enabled) {
                defaults.set(true, forKey: Self.configuredKey)
            } else {
                failureDetail = "変更できませんでした。\(error.localizedDescription)"
            }
        }
    }

    private func finishChange(requestedEnabled enabled: Bool) {
        status = service.status()
        if matches(requestedEnabled: enabled) {
            defaults.set(true, forKey: Self.configuredKey)
        } else {
            failureDetail =
                enabled
                ? "ログイン項目を登録できませんでした。"
                : "ログイン項目の登録を解除できませんでした。"
        }
    }

    private func matches(requestedEnabled enabled: Bool) -> Bool {
        if enabled { return status == .enabled || status == .requiresApproval }
        return status == .notRegistered || status == .notFound
    }

    private struct LoginItemError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
