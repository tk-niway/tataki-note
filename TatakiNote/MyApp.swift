import SwiftUI

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let settings = appDelegate.settings
        let updates = appDelegate.updates

        MenuBarExtra(
            isInserted: Binding(
                get: { settings.isMenuBarIconShown },
                set: { settings.isMenuBarIconShown = $0 }
            )
        ) {
            MenuBarMenu(
                updates: updates,
                onOpenPanel: { appDelegate.panelController.open() },
                onOpenSettings: { appDelegate.settingsWindow.show() }
            )
        } label: {
            MenuBarIconLabel(updates: updates)
        }
        .menuBarExtraStyle(.menu)
    }
}
