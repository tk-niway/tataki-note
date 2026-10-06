import SwiftUI

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let settings = appDelegate.settings
        let isMenuBarIconInserted = appDelegate.insertionFailureBubble.isMenuBarIconInserted(
            isIconShownSetting: settings.isMenuBarIconShown
        )

        MenuBarExtra(
            "TatakiNote",
            image: "MenuBarIcon",
            isInserted: Binding(
                get: { isMenuBarIconInserted },
                set: { appDelegate.insertionFailureBubbleController.menuBarIconInsertionDidChange(to: $0, settings: settings) }
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
