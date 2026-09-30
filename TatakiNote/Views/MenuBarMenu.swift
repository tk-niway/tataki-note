import AppKit
import KeyboardShortcuts
import SwiftUI

/// @note p0-616
struct MenuBarMenu: View {
    let onOpenPanel: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Button("パネルを開く", action: onOpenPanel)
            // @note p0-617
            .globalKeyboardShortcut(.togglePanel)
            .accessibilityIdentifier("menu.openPanel")
        // @note p0-618
        Button("設定", action: onOpenSettings)
            .keyboardShortcut(",")
            .accessibilityIdentifier("menu.settings")
        Divider()
        Button("終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .accessibilityIdentifier("menu.quit")
    }
}
