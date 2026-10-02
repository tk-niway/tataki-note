import AppKit
import KeyboardShortcuts
import SwiftUI

/// メニューバーのアイコンのメニュー。
struct MenuBarMenu: View {
    let onOpenPanel: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Button("パネルを開く", action: onOpenPanel)
            .globalKeyboardShortcut(.togglePanel)
            .accessibilityIdentifier("menu.openPanel")
        Button("設定", action: onOpenSettings)
            .keyboardShortcut(",")
            .accessibilityIdentifier("menu.settings")
        Divider()
        Button("終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .accessibilityIdentifier("menu.quit")
    }
}
