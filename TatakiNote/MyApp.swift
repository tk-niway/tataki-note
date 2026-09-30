import SwiftUI

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // @note p0-465
        let settings = appDelegate.settings
        // @note p0-466
        let isMenuBarIconShown = settings.isMenuBarIconShown

        // @note p0-467
        MenuBarExtra(
            "TatakiNote",
            image: "MenuBarIcon",
            isInserted: Binding(
                get: { isMenuBarIconShown },
                set: { settings.isMenuBarIconShown = $0 }
            )
        ) {
            MenuBarMenu(
                onOpenPanel: { appDelegate.panelController.open() },
                onOpenSettings: { appDelegate.settingsWindow.show() }
            )
        }
        .menuBarExtraStyle(.menu)
    }
}
