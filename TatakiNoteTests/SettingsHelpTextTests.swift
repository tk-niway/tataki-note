import Testing
@testable import TatakiNote

struct SettingsHelpTextTests {
    @Test("AC-26: 「メニューバーにアイコンを表示」の説明文は、設定の開き方を案内し、もう一度開くとこの画面が開くとは言わない")
    func showMenuBarIcon() {
        #expect(SettingsHelpText.showMenuBarIcon == "オフの間は、パネルの「設定」のボタンか ⌘, でこの画面を開きます。終了は左下の「TatakiNote を終了」から。")
        #expect(!SettingsHelpText.showMenuBarIcon.contains("もう一度開くとこの画面が開きます"))
    }

    @Test("AC-26: 「Dock にアイコンを表示」と「⌘Q で終了前に確認」の説明文は決めた全文")
    func dockIconAndConfirmQuit() {
        #expect(SettingsHelpText.showDockIcon == "表示しないときも、Finder や Spotlight から開くとパネルが開きます。")
        #expect(SettingsHelpText.confirmQuit == "メニューの「終了」と「TatakiNote を終了」では確認しません。")
    }

    @Test("AC-4: 「履歴」の説明文は残す件数を含む短い文")
    func historyKept() {
        #expect(SettingsHelpText.historyKept(limit: 50) == "最新 50 件までこの Mac に残ります。")
        #expect(SettingsHelpText.historyKept(limit: HistoryLimit.defaultValue) == "最新 \(HistoryLimit.defaultValue) 件までこの Mac に残ります。")
    }

    @Test("AC-4: ホットキー・自動表示・対象のアプリの説明文は短い文")
    func hotkeyAndAutoShow() {
        #expect(SettingsHelpText.hotkey == "どのアプリからでも、このキーでパネルを開く・閉じるを切り替えます。")
        #expect(SettingsHelpText.autoShowMode == "入力欄を選ぶだけでパネルを開きます。")
        #expect(SettingsHelpText.autoShowApps == "「＋ 追加」で起動中のアプリを、「その他…」でそれ以外を選べます。")
    }

    @Test("AC-4: 「挿入と送信」のまとまりの下の説明文は短い文")
    func insertAndSendFooter() {
        #expect(SettingsHelpText.insertAndSendFooter == "記録ボックスをクリックしてキーを押します。esc で取り消します。")
    }

    @Test("AC-31: 「モード」の説明文は決めた全文")
    func newDraftMode() {
        #expect(SettingsHelpText.newDraftMode == "新しい書きかけ(起動したとき・⌘N で新しくしたとき・挿入したあと)を、このモードで始めます。ノートでは挿入・送信せず、確定のキーは改行になります。今の書きかけのモードは、パネルで ⌘E を押して切り替えられます。")
    }

    @Test("AC-4: 「パネル」と「情報」の説明文は短い文")
    func panelAndInfo() {
        #expect(SettingsHelpText.statusItemsFooter == "すべて外すと帯ごと消えます。")
        #expect(SettingsHelpText.insertionTargetOutline == "パネルを開いている間、挿入先の入力欄を枠線で囲みます。")
        #expect(SettingsHelpText.accessibilityPermission == "文章を入力欄に挿入するのに必要です。")
    }

    @Test("AC-5: アイコンを表示しないときの終了の案内が残る")
    func showMenuBarIconKeepsQuitGuidance() {
        #expect(SettingsHelpText.showMenuBarIcon.contains("TatakiNote を終了"))
    }
}
