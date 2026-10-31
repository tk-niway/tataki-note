import Foundation
import Observation

/// アプリが自分で覚えておく状態(チュートリアルを出したか・サイドバー・前回の書き出し先・アップデートの確認・移動の確認)。
@Observable final class AppState {
    /// 初回起動のチュートリアルを自動で出したか。
    var hasShownFirstLaunchTutorial: Bool {
        didSet { store.persist(\.hasShownFirstLaunchTutorial, of: self, as: SettingDefinitions.hasShownFirstLaunchTutorial) }
    }

    /// サイドバーを開いているか。
    var isSidebarOpen: Bool {
        didSet { store.persist(\.isSidebarOpen, of: self, as: SettingDefinitions.isSidebarOpen) }
    }

    /// サイドバーで表示している側。
    var sidebarTab: SidebarTab {
        didSet { store.persist(\.sidebarTab, of: self, as: SettingDefinitions.sidebarTab) }
    }

    /// 前回書き出したフォルダのパス。
    var lastExportDirectoryPath: String? {
        didSet { store.persist(\.lastExportDirectoryPath, of: self, as: SettingDefinitions.lastExportDirectoryPath) }
    }

    /// 前回アップデートの確認が済んだ日時。未確認なら nil。
    var lastUpdateCheckDate: Date? {
        didSet { store.persist(\.lastUpdateCheckDate, of: self, as: SettingDefinitions.lastUpdateCheckDate) }
    }

    /// 「アプリケーション」フォルダへの移動を聞かないか。
    var suppressesMoveToApplicationsPrompt: Bool {
        didSet {
            store.persist(
                \.suppressesMoveToApplicationsPrompt,
                of: self,
                as: SettingDefinitions.suppressesMoveToApplicationsPrompt
            )
        }
    }

    @ObservationIgnored private let store: SettingsStore

    /// 保存先から状態を読んで作る。何も保存しない。
    init(store: SettingsStore) {
        self.store = store
        self.hasShownFirstLaunchTutorial = store.value(SettingDefinitions.hasShownFirstLaunchTutorial)
        self.isSidebarOpen = store.value(SettingDefinitions.isSidebarOpen)
        self.sidebarTab = store.value(SettingDefinitions.sidebarTab)
        self.lastExportDirectoryPath = store.value(SettingDefinitions.lastExportDirectoryPath)
        self.lastUpdateCheckDate = store.value(SettingDefinitions.lastUpdateCheckDate)
        self.suppressesMoveToApplicationsPrompt = store.value(SettingDefinitions.suppressesMoveToApplicationsPrompt)
    }
}
