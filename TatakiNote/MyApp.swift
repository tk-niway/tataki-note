import SwiftUI

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let settings = appDelegate.settings
        let isMenuBarIconShown = settings.isMenuBarIconShown

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
