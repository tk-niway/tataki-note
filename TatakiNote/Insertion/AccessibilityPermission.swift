import AppKit

/// @note p0-26
protocol AccessibilityPermissionChecking {
    var isTrusted: Bool { get }
    /// @note p0-27
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

/// @note p0-28
struct OverriddenAccessibilityPermission: AccessibilityPermissionChecking {
    let isTrusted: Bool

    /// @note p0-29
    func requestSystemPrompt() {}
}
