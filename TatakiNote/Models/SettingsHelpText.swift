import Foundation

/// 設定画面の View に表示する説明文。
enum SettingsHelpText {
    /// 「メニューバーのアイコンを隠す」の下の説明文。
    static let hideMenuBarIcon = String(
        localized: "隠している間は、TatakiNote をもう一度開くとこの画面が開きます。終了は左下の「TatakiNote を終了」から。"
    )

    /// 「履歴」の下の説明文。
    static func historyKept(limit: Int) -> String {
        String(localized: "最新 \(limit) 件までこの Mac に残ります。")
    }

    /// 「パネルを開く・閉じる」の下の説明文。
    static let hotkey = String(localized: "どのアプリからでも、このキーでパネルを開く・閉じるを切り替えます。")

    /// 「自動表示」の下の説明文。
    static let autoShowMode = String(localized: "入力欄を選ぶだけでパネルを開きます。")

    /// 「対象のアプリ」の下の説明文。
    static let autoShowApps = String(localized: "「＋ 追加」で起動中のアプリを、「その他…」でそれ以外を選べます。")

    /// 「挿入と送信」のまとまりの下の説明文。
    static let insertAndSendFooter = String(localized: "記録ボックスをクリックしてキーを押します。esc で取り消します。")

    /// 「帯に出す項目」のまとまりの下の説明文。
    static let statusItemsFooter = String(localized: "すべて外すと帯ごと消えます。")

    /// 「挿入先の入力欄を枠線で囲む」の下の説明文。
    static let insertionTargetOutline = String(localized: "パネルを開いている間、挿入先の入力欄を枠線で囲みます。")

    /// 「アクセシビリティの許可」の下の説明文。
    static let accessibilityPermission = String(localized: "文章を入力欄に挿入するのに必要です。")
}
