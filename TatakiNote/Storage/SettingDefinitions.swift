import Foundation

/// 保存する設定と状態の定義の表。保存のキーはここにだけ書く。
enum SettingDefinitions {
    // MARK: - 利用者が選ぶ設定

    static let commitKey = panelShortcut(
        "commitShortcut",
        legacyKey: "commitKey",
        otherLegacyKey: "commitAndSendKey",
        default: PanelShortcut.defaultCommitKey,
        legacyDefault: PanelShortcut.legacyDefaultCommitKey
    )

    static let commitAndSendKey = panelShortcut(
        "commitAndSendShortcut",
        legacyKey: "commitAndSendKey",
        otherLegacyKey: "commitKey",
        default: PanelShortcut.defaultCommitAndSendKey,
        legacyDefault: PanelShortcut.legacyDefaultCommitAndSendKey
    )

    static let panelScreen: SettingDefinition<PanelScreen> = .stringEnum("panelScreen", default: .defaultValue)

    static let autoShowMode: SettingDefinition<AutoShowMode> = .stringEnum("autoShowMode", default: .defaultValue)

    static let autoShowApps = SettingDefinition<[AutoShowApp]>(
        key: "autoShowApps",
        read: { storage in
            guard let data = storage.data(forKey: "autoShowApps") else { return [] }
            let apps = (try? JSONDecoder().decode([AutoShowApp].self, from: data)) ?? []
            return AutoShowApp.normalized(apps)
        },
        write: { apps, storage in
            guard let data = try? JSONEncoder().encode(apps) else { return }
            storage.set(data, forKey: "autoShowApps")
        },
        normalize: AutoShowApp.normalized
    )

    static let theme: SettingDefinition<AppTheme> = .stringEnum("appTheme", default: .defaultValue)

    static let panelFontName: SettingDefinition<String?> = .nonEmptyString("panelFontName", emptyBecomesNil: true)

    static let panelFontFamilyName: SettingDefinition<String?> = .nonEmptyString(
        "panelFontFamilyName",
        emptyBecomesNil: true
    )

    static let panelFontSize: SettingDefinition<Double> = .clampedNumber(
        "panelFontSize",
        default: PanelTextStyle.defaultFontSize,
        clamp: PanelTextStyle.clampedFontSize
    )

    static let panelOpacity: SettingDefinition<Double> = .clampedNumber(
        "panelOpacity",
        default: PanelTextStyle.defaultOpacity,
        clamp: PanelTextStyle.clampedOpacity
    )

    static let hiddenPanelStatusItems = SettingDefinition<Set<PanelStatusItem>>(
        key: "hiddenPanelStatusItems",
        read: { storage in
            guard let values = storage.array(forKey: "hiddenPanelStatusItems") else { return [] }
            return Set(values.compactMap { ($0 as? String).flatMap(PanelStatusItem.init(rawValue:)) })
        },
        write: { items, storage in
            let rawValues = PanelStatusItem.allCases.filter { items.contains($0) }.map(\.rawValue)
            storage.set(rawValues, forKey: "hiddenPanelStatusItems")
        }
    )

    static let isMenuBarIconShown: SettingDefinition<Bool> = .invertedBoolean("hidesMenuBarIcon", default: true)

    static let panelDefaultWidth: SettingDefinition<Double> = .numberInRange(
        "panelDefaultWidth",
        range: PanelMetrics.defaultWidthRange,
        default: Double(PanelMetrics.defaultSize.width),
        clamp: PanelMetrics.clampedDefaultWidth
    )

    static let panelDefaultHeight: SettingDefinition<Double> = .numberInRange(
        "panelDefaultHeight",
        range: PanelMetrics.defaultHeightRange,
        default: Double(PanelMetrics.defaultSize.height),
        clamp: PanelMetrics.clampedDefaultHeight
    )

    static let animationMode: SettingDefinition<AnimationMode> = .stringEnum("animationMode", default: .defaultValue)

    static let isInsertionTargetOutlineShown: SettingDefinition<Bool> = .boolean(
        "insertionTargetOutlineShown",
        default: true
    )

    static let showsDockIcon: SettingDefinition<Bool> = .boolean("showsDockIcon", default: true)

    static let confirmsQuit: SettingDefinition<Bool> = .boolean("confirmsQuit", default: true)

    static let historyLimit = SettingDefinition<Int>(
        key: "historyLimit",
        read: { storage in
            guard let value = StoredValue.number(in: storage, forKey: "historyLimit")?.doubleValue,
                  value.isFinite
            else { return HistoryLimit.defaultValue }
            let lower = Double(HistoryLimit.range.lowerBound)
            let upper = Double(HistoryLimit.range.upperBound)
            return Int(min(max(value, lower), upper))
        },
        write: { limit, storage in storage.set(limit, forKey: "historyLimit") },
        normalize: HistoryLimit.clamped
    )

    static let historyRetention: SettingDefinition<HistoryRetention> = .stringEnum(
        "historyRetention",
        default: .defaultValue
    )

    static let newDraftMode: SettingDefinition<DraftMode> = .stringEnum("newDraftMode", default: .insert)

    static let checksForUpdatesAutomatically: SettingDefinition<Bool> = .boolean(
        "checksForUpdatesAutomatically",
        default: true
    )

    // MARK: - アプリが覚えておく状態

    static let hasShownFirstLaunchTutorial: SettingDefinition<Bool> = .boolean(
        "hasShownFirstLaunchTutorial",
        default: false
    )

    static let isSidebarOpen: SettingDefinition<Bool> = .boolean("sidebarIsOpen", default: false)

    static let sidebarTab: SettingDefinition<SidebarTab> = .stringEnum("sidebarTab", default: .drafts)

    static let lastExportDirectoryPath: SettingDefinition<String?> = .nonEmptyString(
        "lastExportDirectory",
        emptyBecomesNil: false
    )

    static let lastUpdateCheckDate = SettingDefinition<Date?>(
        key: "lastUpdateCheckDate",
        read: { storage in
            guard let seconds = StoredValue.number(in: storage, forKey: "lastUpdateCheckDate")?.doubleValue,
                  seconds.isFinite
            else { return nil }
            return Date(timeIntervalSince1970: seconds)
        },
        write: { date, storage in
            guard let date, date.timeIntervalSince1970.isFinite else {
                storage.removeObject(forKey: "lastUpdateCheckDate")
                return
            }
            storage.set(date.timeIntervalSince1970, forKey: "lastUpdateCheckDate")
        }
    )

    static let suppressesMoveToApplicationsPrompt: SettingDefinition<Bool> = .boolean(
        "suppressesMoveToApplicationsPrompt",
        default: false
    )

    // MARK: - 確定キー

    private static func panelShortcut(
        _ key: String,
        legacyKey: String,
        otherLegacyKey: String,
        default defaultValue: PanelShortcut?,
        legacyDefault: PanelShortcut?
    ) -> SettingDefinition<PanelShortcut?> {
        SettingDefinition(
            key: key,
            read: { storage in
                let hasLegacyKeys = storage.object(forKey: legacyKey) != nil
                    || storage.object(forKey: otherLegacyKey) != nil
                let fallback = hasLegacyKeys ? legacyDefault : defaultValue
                if let stored = storage.object(forKey: key) {
                    guard let array = stored as? [Any] else { return fallback }
                    return array.isEmpty ? nil : (PanelShortcut(storedValue: array) ?? fallback)
                }
                if let legacy = storage.string(forKey: legacyKey) {
                    guard let actionKey = PanelActionKey(rawValue: legacy) else { return fallback }
                    return actionKey.shortcut
                }
                return fallback
            },
            write: { shortcut, storage in storage.set(shortcut?.storedValue ?? [], forKey: key) }
        )
    }
}
