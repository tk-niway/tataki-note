import Foundation

/// 設定画面の View に表示する説明文。
enum SettingsHelpText {
    /// 「メニューバーにアイコンを表示」の下の説明文。
    static let showMenuBarIcon = String(
        localized: "オフの間は、パネルの「設定」のボタンか ⌘, でこの画面を開きます。終了は左下の「TatakiNote を終了」から。"
    )

    /// 「Dock にアイコンを表示」の下の説明文。
    static let showDockIcon = String(localized: "表示しないときも、Finder や Spotlight から開くとパネルが開きます。")

    /// 「⌘Q で終了前に確認」の下の説明文。
    static let confirmQuit = String(localized: "メニューの「終了」と「TatakiNote を終了」では確認しません。")

    /// 「履歴」の下の説明文。
    static func historyKept(limit: Int) -> String {
        String(localized: "最新 \(limit) 件までこの Mac に残ります。")
    }

    /// 履歴の上限を縮めるときの警告文。
    static func historyLimitWarning(limit: Int, removedCount: Int) -> String {
        String(localized: "\(limit) 件にすると、古い履歴が \(removedCount) 件消えます。この操作は元に戻せません。")
    }

    /// 「パネルを開く・閉じる」の下の説明文。
    static let hotkey = String(localized: "どのアプリからでも、このキーでパネルを開く・閉じるを切り替えます。")

    /// 「自動表示」の下の説明文。
    static let autoShowMode = String(localized: "入力欄を選ぶだけでパネルを開きます。")

    /// 「対象のアプリ」の下の説明文。
    static let autoShowApps = String(localized: "「＋ 追加」で起動中のアプリを、「その他…」でそれ以外を選べます。")

    /// 「挿入と送信」のまとまりの下の説明文。
    static let insertAndSendFooter = String(localized: "記録ボックスをクリックしてキーを押します。esc で取り消します。")

    /// 「モード」(新しい書きかけを始めるモード)の下の説明文。
    static let newDraftMode = String(
        localized: "新しい書きかけ(起動したとき・⌘N で新しくしたとき・挿入したあと)を、このモードで始めます。ノートでは挿入・送信せず、確定のキーは改行になります。今の書きかけのモードは、パネルで ⌘E を押して切り替えられます。"
    )

    /// 「帯に出す項目」のまとまりの下の説明文。
    static let statusItemsFooter = String(localized: "すべて外すと帯ごと消えます。")

    /// 「挿入先の入力欄を枠線で囲む」の下の説明文。
    static let insertionTargetOutline = String(localized: "パネルを開いている間、挿入先の入力欄を枠線で囲みます。")

    /// 「アクセシビリティの許可」の下の説明文。
    static let accessibilityPermission = String(localized: "文章を入力欄に挿入するのに必要です。")
}
