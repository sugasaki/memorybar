import Foundation
import XCTest

@testable import MemoryBar

@MainActor
final class LoginItemControllerTests: XCTestCase {
    @MainActor
    private final class StubService {
        var status: LoginItemService.Status
        var registerError: Error?
        var unregisterError: Error?
        var registerCalls = 0
        var unregisterCalls = 0
        var openSettingsCalls = 0

        init(status: LoginItemService.Status) {
            self.status = status
        }

        var service: LoginItemService {
            LoginItemService(
                status: { self.status },
                register: {
                    self.registerCalls += 1
                    if let error = self.registerError { throw error }
                    self.status = .enabled
                },
                unregister: {
                    self.unregisterCalls += 1
                    if let error = self.unregisterError { throw error }
                    self.status = .notRegistered
                },
                openSystemSettings: { self.openSettingsCalls += 1 })
        }
    }

    private struct StubError: LocalizedError {
        var errorDescription: String? { "テスト用エラー" }
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "LoginItemControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    func test初回未登録を示すnotFoundからログイン項目を有効にする() {
        // 実機では mainApp の初回登録前に .notFound が返る。
        // これを登録不能と決めつけると、v0.5.17 のようにONへ切り替えられない。
        let stub = StubService(status: .notFound)
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = LoginItemController(service: stub.service, defaults: defaults)

        XCTAssertNil(controller.statusMessage)
        controller.enableByDefaultIfNeeded()

        XCTAssertEqual(stub.registerCalls, 1)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: LoginItemController.configuredKey))
    }

    func test明示的に設定済みなら次回起動で勝手に有効化しない() {
        let stub = StubService(status: .notRegistered)
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: LoginItemController.configuredKey)
        let controller = LoginItemController(service: stub.service, defaults: defaults)

        controller.enableByDefaultIfNeeded()

        XCTAssertEqual(stub.registerCalls, 0)
        XCTAssertFalse(controller.isEnabled)
    }

    func test設定からログイン項目を無効化できる() {
        let stub = StubService(status: .enabled)
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = LoginItemController(service: stub.service, defaults: defaults)

        controller.setEnabled(false)

        XCTAssertEqual(stub.unregisterCalls, 1)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: LoginItemController.configuredKey))
    }

    func test登録失敗時は有効と表示せず次回起動で再試行できる() {
        let stub = StubService(status: .notFound)
        stub.registerError = StubError()
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = LoginItemController(service: stub.service, defaults: defaults)

        controller.enableByDefaultIfNeeded()

        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: LoginItemController.configuredKey))
        XCTAssertTrue(controller.statusMessage?.contains("テスト用エラー") ?? false)
    }

    func test未登録を示すnotFoundで無効化してもエラーにしない() {
        let stub = StubService(status: .notFound)
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = LoginItemController(service: stub.service, defaults: defaults)

        controller.setEnabled(false)

        XCTAssertEqual(stub.unregisterCalls, 0)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.statusMessage)
        XCTAssertTrue(defaults.bool(forKey: LoginItemController.configuredKey))
    }

    func test許可待ちは登録済みとして表示しシステム設定を開ける() {
        let stub = StubService(status: .requiresApproval)
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = LoginItemController(service: stub.service, defaults: defaults)

        controller.enableByDefaultIfNeeded()
        controller.openSystemSettings()

        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(controller.requiresApproval)
        XCTAssertNotNil(controller.statusMessage)
        XCTAssertEqual(stub.openSettingsCalls, 1)
        XCTAssertTrue(defaults.bool(forKey: LoginItemController.configuredKey))
    }

    func test解除失敗時は実際の有効状態を保って理由を表示する() {
        let stub = StubService(status: .enabled)
        stub.unregisterError = StubError()
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = LoginItemController(service: stub.service, defaults: defaults)

        controller.setEnabled(false)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(controller.statusMessage?.contains("テスト用エラー") ?? false)
    }
}
