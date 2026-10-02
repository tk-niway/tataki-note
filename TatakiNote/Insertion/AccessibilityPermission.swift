import AppKit

/// アクセシビリティの許可(他のアプリにキーを送るのに要る)。
protocol AccessibilityPermissionChecking {
    var isTrusted: Bool { get }
    func requestSystemPrompt()
}

struct SystemAccessibilityPermission: AccessibilityPermissionChecking {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestSystemPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

/// 許可の有無を決め打ちで返す(UI テストで使う)。
struct OverriddenAccessibilityPermission: AccessibilityPermissionChecking {
    let isTrusted: Bool

    func requestSystemPrompt() {}
}
