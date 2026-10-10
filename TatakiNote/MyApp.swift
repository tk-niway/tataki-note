import SwiftUI

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let settings = appDelegate.settings

        MenuBarExtra(
            "TatakiNote",
            image: MenuBarIcon.assetName,
            isInserted: Binding(
                get: { settings.isMenuBarIconShown },
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
