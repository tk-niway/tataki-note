import Foundation
import Observation

/// 更新の知らせ方。
enum UpdatePresentation {
    /// 裏の確認で見つけた更新をすぐ窓で出すか。
    static let showsBackgroundUpdateImmediately = false
    /// 控えめな知らせを使うか。
    static let supportsGentleReminders = true

    /// Dock のアイコンに付ける文字。新しい版があれば "1"、無ければ nil。
    static func dockBadgeLabel(isUpdatePending: Bool) -> String? {
        isUpdatePending ? "1" : nil
    }
}

/// 更新の確認の状態と、知らせの印。
@Observable final class UpdateModel {
    /// 裏の確認で見つけ、まだ利用者が見ていない版。
    private(set) var pendingVersion: String?
    private(set) var canCheckForUpdates: Bool
    private(set) var isOnline = false

    /// 利用者がまだ見ていない新しい版があるか。
    var isUpdatePending: Bool { pendingVersion != nil }

    /// 自動で確かめるか。オンにしたらその場で判定する。
    var isAutomaticCheckEnabled: Bool {
        get { settings.checksForUpdatesAutomatically }
        set {
            settings.checksForUpdatesAutomatically = newValue
            if newValue { evaluate() }
        }
    }

    /// 印を出す設定の区分。
    var badgedSettingsSections: Set<SettingsSection> {
        isUpdatePending ? [.appInfo] : []
    }

    /// メニューバーのメニューに出す新しい版の項目の題。無ければ nil。
    var menuTitleForPendingUpdate: String? {
        pendingVersion.map { String(localized: "新しい版があります(\($0))") }
    }

    /// 設定の「情報」に出す新しい版の説明。無ければ nil。
    var settingsStatusText: String? {
        pendingVersion.map { String(localized: "新しい版 \($0) があります") }
    }

    /// 更新の入れ替えで開き直す直前に呼ぶ。
    @ObservationIgnored var onWillRelaunch: (() -> Void)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let updater: UpdaterDriving
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    /// 何もしない更新の仕組みで作る。
    static func inert(settings: AppSettings) -> UpdateModel {
        UpdateModel(settings: settings, updater: InertUpdater())
    }

    init(settings: AppSettings, updater: UpdaterDriving, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.updater = updater
        self.now = now
        self.canCheckForUpdates = updater.canCheckForUpdates
        updater.onEvent = { [weak self] event in self?.handle(event) }
        updater.onCanCheckChange = { [weak self] canCheck in self?.canCheckForUpdates = canCheck }
    }

    deinit {
        tickTask?.cancel()
    }

    /// 更新の仕組みを始め、1時間ごとの判定を始める。
    func start() {
        updater.start()
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: UpdateCheckSchedule.tickInterval)
                guard !Task.isCancelled, let self else { return }
                self.evaluate()
            }
        }
        evaluate()
    }

    /// ネットワークの状態が変わったことを受ける。オンラインに戻ったときに判定する。
    func networkDidChange(isOnline: Bool) {
        let wasOnline = self.isOnline
        self.isOnline = isOnline
        if isOnline && !wasOnline { evaluate() }
    }

    /// 裏で確かめる条件がそろっていれば、裏の確認を始める。
    func evaluate() {
        let shouldCheck = UpdateCheckSchedule.shouldCheckInBackground(
            isAutomaticCheckEnabled: settings.checksForUpdatesAutomatically,
            isOnline: isOnline,
            isSessionInProgress: updater.isSessionInProgress || isUpdatePending,
            lastCheckDate: settings.lastUpdateCheckDate,
            now: now()
        )
        if shouldCheck { updater.checkInBackground() }
    }

    /// 見つけた新しい版の窓を出す。
    func showPendingUpdate() {
        updater.checkByUser()
    }

    /// 利用者の操作でアップデートを確かめる。
    func checkByUser() {
        updater.checkByUser()
    }

    /// 更新の仕組みからの出来事を受ける。
    func handle(_ event: UpdaterEvent) {
        switch event {
        case .foundInBackground(let version):
            pendingVersion = version
        case .checkCompleted:
            settings.lastUpdateCheckDate = now()
        case .checkFailed:
            break
        case .userAttended, .sessionFinished:
            pendingVersion = nil
        case .willRelaunch:
            onWillRelaunch?()
        }
    }
}
