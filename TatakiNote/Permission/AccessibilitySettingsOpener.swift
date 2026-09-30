import AppKit

/// @note p0-518
protocol AccessibilitySettingsOpening {
    func openAccessibilitySettings()
}

struct WorkspaceAccessibilitySettingsOpener: AccessibilitySettingsOpening {
    static let settingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    func openAccessibilitySettings() {
        // @note p0-519
        guard let url = URL(string: Self.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }
}
