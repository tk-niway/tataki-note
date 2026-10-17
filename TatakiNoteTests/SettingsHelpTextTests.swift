import Testing
@testable import TatakiNote

struct SettingsHelpTextTests {
    @Test("AC-4: 「メニューバーのアイコンを隠す」の説明文は短い文")
    func hideMenuBarIcon() {
        #expect(SettingsHelpText.hideMenuBarIcon == "隠している間は、TatakiNote をもう一度開くとこの画面が開きます。終了は左下の「TatakiNote を終了」から。")
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

    @Test("AC-6: 「アニメーション」の説明文は、「システム」が視差効果を減らす設定に従うことを書いた決まった文")
    func animationMode() {
        #expect(SettingsHelpText.animationMode == "パネルの開閉や保存の演出など、TatakiNote の動きをまとめて切り替えます。「システム」では、macOS のシステム設定の「アクセシビリティ」→「ディスプレイ」→「視差効果を減らす」に従います。")
        #expect(SettingsHelpText.animationMode.contains("視差効果を減らす"))
    }

    @Test("AC-5: アイコンを隠したときの終了の案内が残る")
    func hideMenuBarIconKeepsQuitGuidance() {
        #expect(SettingsHelpText.hideMenuBarIcon.contains("TatakiNote を終了"))
    }
}
