import AppKit
import KeyboardShortcuts
import SwiftUI

/// メニューバーのアイコンのメニュー。
struct MenuBarMenu: View {
    let updates: UpdateModel
    let onOpenPanel: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        if let title = updates.menuTitleForPendingUpdate {
            Button(title) { updates.showPendingUpdate() }
                .accessibilityIdentifier("menu.updateAvailable")
            Divider()
        }
        Button("パネルを開く", action: onOpenPanel)
            .globalKeyboardShortcut(.togglePanel)
            .accessibilityIdentifier("menu.openPanel")
        Button("設定", action: onOpenSettings)
            .keyboardShortcut(",")
            .accessibilityIdentifier("menu.settings")
        Button("アップデートを確認…") { updates.checkByUser() }
            .disabled(!updates.canCheckForUpdates)
            .accessibilityIdentifier("menu.checkForUpdates")
        Divider()
        Button("終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .accessibilityIdentifier("menu.quit")
    }
}
