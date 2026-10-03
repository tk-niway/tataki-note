import Foundation
@testable import TatakiNote

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
