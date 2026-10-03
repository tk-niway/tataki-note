import Foundation
import Testing
@testable import TatakiNote

/// テストごとの一時的な UserDefaults(suite)。`remove()` で消す。
@MainActor
struct TemporaryDefaults {
    let name: String
    let defaults: UserDefaults

    init(name: String = UUID().uuidString) throws {
        self.name = name
        self.defaults = try #require(UserDefaults(suiteName: name))
    }

    func makeSettings() -> AppSettings {
        AppSettings(store: SettingsStore(defaults: defaults))
    }

    func remove() {
        defaults.removePersistentDomain(forName: name)
    }

    static func remove(named name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
}

/// 許可の確認とシステム設定を開く呼び出しの順を記録する。
@MainActor
final class PermissionCallLog {
    private(set) var calls: [String] = []

    func record(_ call: String) {
        calls.append(call)
    }
}

/// 許可の有無を切り替えられ、許可を求めた回数と呼ばれた順を記録する偽物。
@MainActor
final class PermissionStub: AccessibilityPermissionChecking {
    var isTrusted: Bool
    private(set) var promptRequestCount = 0
    private let log: PermissionCallLog?

    init(isTrusted: Bool, log: PermissionCallLog? = nil) {
        self.isTrusted = isTrusted
        self.log = log
    }

    func requestSystemPrompt() {
        promptRequestCount += 1
        log?.record("prompt")
    }
}

/// 条件が真になるまで、決めた回数・間隔で確かめる。最後に条件の値を返す。
@MainActor
@discardableResult
func waitUntil(
    attempts: Int,
    interval: Duration,
    beforeEachCheck: () -> Void = {},
    _ condition: () -> Bool
) async throws -> Bool {
    for _ in 0..<attempts {
        beforeEachCheck()
        if condition() {
            return true
        }
        try await Task.sleep(for: interval)
    }
    beforeEachCheck()
    return condition()
}

/// 条件が真になるか1秒たつまで、実行を譲りながら待つ。
@MainActor
func yieldUntil(_ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(1)
    while !condition() && ContinuousClock.now < deadline {
        await Task.yield()
    }
}

/// システム設定を開いた回数と呼ばれた順を記録する偽物。
@MainActor
final class SettingsOpenerStub: AccessibilitySettingsOpening {
    private(set) var openCount = 0
    private let log: PermissionCallLog?

    init(log: PermissionCallLog? = nil) {
        self.log = log
    }

    func openAccessibilitySettings() {
        openCount += 1
        log?.record("open")
    }
}
