import Foundation
@testable import TatakiNote

extension AppSettings {
    /// メニューバーのアイコンを隠すか(`isMenuBarIconShown` の逆)。
    var hidesMenuBarIcon: Bool {
        get { !isMenuBarIconShown }
        set { isMenuBarIconShown = !newValue }
    }

    /// `state.hasShownFirstLaunchTutorial` への転送。
    var hasShownFirstLaunchTutorial: Bool {
        get { state.hasShownFirstLaunchTutorial }
        set { state.hasShownFirstLaunchTutorial = newValue }
    }

    /// `state.isSidebarOpen` への転送。
    var isSidebarOpen: Bool {
        get { state.isSidebarOpen }
        set { state.isSidebarOpen = newValue }
    }

    /// `state.sidebarTab` への転送。
    var sidebarTab: SidebarTab {
        get { state.sidebarTab }
        set { state.sidebarTab = newValue }
    }

    /// `state.lastExportDirectoryPath` への転送。
    var lastExportDirectoryPath: String? {
        get { state.lastExportDirectoryPath }
        set { state.lastExportDirectoryPath = newValue }
    }

    /// `state.lastUpdateCheckDate` への転送。
    var lastUpdateCheckDate: Date? {
        get { state.lastUpdateCheckDate }
        set { state.lastUpdateCheckDate = newValue }
    }

    /// `state.suppressesMoveToApplicationsPrompt` への転送。
    var suppressesMoveToApplicationsPrompt: Bool {
        get { state.suppressesMoveToApplicationsPrompt }
        set { state.suppressesMoveToApplicationsPrompt = newValue }
    }
}
