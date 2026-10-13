import Foundation


extension PanelScreen {
    var displayName: String {
        switch self {
        case .mouse:
            String(localized: "マウスの近く")
        case .targetWindow:
            String(localized: "挿入先のウィンドウがある画面")
        case .main:
            String(localized: "メインの画面")
        case .nearFocusedField:
            String(localized: "入力欄の近く")
        }
    }

    /// 選択肢ごとの説明。
    var optionDescription: String {
        switch self {
        case .nearFocusedField:
            String(localized: "挿入先のアプリで選ばれている入力欄の近くに出します。入力欄の位置が分からないときは、挿入先のウィンドウがある画面の中央に出します。")
        case .targetWindow:
            String(localized: "挿入先のウィンドウがある画面の中央に出します。挿入先のウィンドウが分からないときは、マウスのある画面に出します。")
        case .mouse:
            String(localized: "マウスポインタのすぐ下に出します。")
        case .main:
            String(localized: "システム設定の「ディスプレイ」でメインディスプレイにしている画面の中央に出します。")
        }
    }

    /// 選択肢の説明の前に付ける、共通の一文。
    static let settingLead = String(localized: "パネルを新しく開くときに出す位置です。")

    /// 選んでいる選択肢について出す説明文。
    static func settingDescription(selected: PanelScreen) -> String {
        settingLead + selected.optionDescription
    }

    /// 選べるか(ノートモードの「入力欄の近く」だけ選べない)。
    func isSelectable(isNoteMode: Bool) -> Bool {
        !(isNoteMode && self == .nearFocusedField)
    }
}

extension AppMode {
    var displayName: String {
        switch self {
        case .insert:
            String(localized: "インサートモード")
        case .note:
            String(localized: "ノートモード")
        }
    }
}

extension AppTheme {
    var displayName: String {
        switch self {
        case .system:
            String(localized: "システム")
        case .light:
            String(localized: "ライト")
        case .dark:
            String(localized: "ダーク")
        }
    }
}

extension PanelStatusItem {
    var displayName: String {
        switch self {
        case .lineBreak:
            String(localized: "改行")
        case .close:
            String(localized: "閉じる")
        case .commit:
            String(localized: "確定+挿入キー")
        case .commitAndSend:
            String(localized: "確定+送信キー")
        case .characterCount:
            String(localized: "文字数")
        case .lineCount:
            String(localized: "行数")
        }
    }
}

extension AutoShowMode {
    var displayName: String {
        switch self {
        case .off:
            String(localized: "オフ")
        case .allApps:
            String(localized: "全アプリ")
        case .selectedApps:
            String(localized: "選んだアプリのみ")
        }
    }
}

extension SettingsSection {
    var displayName: String {
        switch self {
        case .general:
            String(localized: "一般")
        case .keys:
            String(localized: "ホットキーとキー操作")
        case .panel:
            String(localized: "パネル")
        case .appInfo:
            String(localized: "情報")
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .keys:
            "keyboard"
        case .panel:
            "macwindow"
        case .appInfo:
            "info.circle"
        }
    }
}
