import AppKit

/// システム設定の「プライバシーとセキュリティ」→「アクセシビリティ」を開く。
protocol AccessibilitySettingsOpening {
    func openAccessibilitySettings()
}

struct WorkspaceAccessibilitySettingsOpener: AccessibilitySettingsOpening {
    static let settingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    func openAccessibilitySettings() {
        guard let url = URL(string: Self.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }
}
