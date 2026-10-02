import Foundation


extension PanelScreen {
    var displayName: String {
        switch self {
        case .mouse:
            String(localized: "マウスのある画面")
        case .targetWindow:
            String(localized: "挿入先のウィンドウがある画面")
        case .main:
            String(localized: "メインの画面")
        case .nearFocusedField:
            String(localized: "入力欄の近く")
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
            String(localized: "確定キー")
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
        case .editor:
            String(localized: "エディタ設定")
        case .appInfo:
            String(localized: "アプリ情報")
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .editor:
            "textformat"
        case .appInfo:
            "info.circle"
        }
    }
}
