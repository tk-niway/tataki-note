import Testing
@testable import TatakiNote

@MainActor
struct PanelModelTests {
    @Test("AC-2: 起動して最初のパネルは空で、閉じた状態から始まる")
    func initialStateIsEmptyAndDismissed() {
        let model = PanelModel()

        #expect(model.text.isEmpty)
        #expect(model.isPresented == false)
    }

    @Test("AC-1: 閉じても書きかけの文章は残り、次に開くと同じ文章がある")
    func draftSurvivesDismiss() {
        let model = PanelModel()
        model.present()
        model.text = "hello\nworld"

        model.dismiss()
        #expect(model.isPresented == false)
        #expect(model.text == "hello\nworld")

        model.present()
        #expect(model.isPresented == true)
        #expect(model.text == "hello\nworld")
    }

    @Test("AC-2: 開くたびにフォーカスの要求が進む")
    func focusRequestAdvancesOnEveryPresent() {
        let model = PanelModel()
        let initial = model.focusRequest

        model.present()
        let afterFirst = model.focusRequest
        #expect(afterFirst > initial)

        model.dismiss()
        #expect(model.focusRequest == afterFirst)

        model.present()
        #expect(model.focusRequest > afterFirst)
    }

    @Test("AC-17: 開いたままもう一度開くと、開いていたことを返し、フォーカスを取り直し、文章はそのまま")
    func presentWhileOpenRefocusesWithoutChangingText() {
        let model = PanelModel()

        #expect(model.present() == false)
        model.text = "hello\nworld"
        let focusBefore = model.focusRequest

        #expect(model.present() == true)
        #expect(model.isPresented == true)
        #expect(model.focusRequest > focusBefore)
        #expect(model.text == "hello\nworld")

        model.dismiss()
        #expect(model.present() == false)
    }

    @Test("AC-1: dismiss は何度呼んでも閉じた状態のままで、文章は残る")
    func dismissIsIdempotent() {
        let model = PanelModel()
        model.present()
        model.text = "draft"

        model.dismiss()
        model.dismiss()

        #expect(model.isPresented == false)
        #expect(model.text == "draft")
        #expect(model.present() == false)
    }

    // MARK: - 確定

    private let textEdit = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
    private let safari = InsertionTarget(processIdentifier: 202, bundleIdentifier: "com.apple.Safari", localizedName: "Safari")

    @Test("AC-5: 文章・権限・挿入先があれば、確定で文章を取り出して空にし、閉じる")
    func commitWithEverythingInsertsAndClears() {
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "hello\nworld"

        let plan = model.prepareCommit(isAccessibilityTrusted: true)

        #expect(plan == .insert(text: "hello\nworld", target: textEdit))
        #expect(model.text.isEmpty)
        #expect(model.isPresented == false)
    }

    @Test("AC-6: 文章が空なら、閉じるだけ")
    func commitEmptyTextDismissesOnly() {
        let model = PanelModel()
        model.present(target: textEdit)

        #expect(model.prepareCommit(isAccessibilityTrusted: true) == .dismissOnly)
        #expect(model.isPresented == false)
        #expect(model.text.isEmpty)
    }

    @Test("AC-7: 権限が無ければ、閉じて文章は下書きに残る")
    func commitWithoutPermissionKeepsDraft() {
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "draft"

        #expect(model.prepareCommit(isAccessibilityTrusted: false) == .permissionDenied)
        #expect(model.isPresented == false)
        #expect(model.text == "draft")
    }

    @Test("AC-8: 挿入先が記録できていなければ、閉じて文章は下書きに残る")
    func commitWithoutTargetKeepsDraft() {
        let model = PanelModel()
        model.present(target: nil)
        model.text = "draft"

        #expect(model.prepareCommit(isAccessibilityTrusted: true) == .noTarget)
        #expect(model.isPresented == false)
        #expect(model.text == "draft")
    }

    @Test("AC-9: 下書きへの戻しは、空なら戻し、書きかけがあれば上書きしない")
    func restoreDraftOnlyWhenEmpty() {
        let model = PanelModel()

        #expect(model.restoreDraft("committed") == true)
        #expect(model.text == "committed")

        model.text = "new"
        #expect(model.restoreDraft("committed") == false)
        #expect(model.text == "new")
    }

    @Test("AC-10: 挿入先は閉じた状態から開いたときに決まり、開いたまま開き直しても変わらない")
    func targetIsFixedWhileOpen() {
        let model = PanelModel()

        #expect(model.present(target: textEdit) == false)
        #expect(model.target == textEdit)

        #expect(model.present(target: safari) == true)
        #expect(model.target == textEdit)
        #expect(model.isPresented == true)

        model.dismiss()
        #expect(model.present(target: safari) == false)
        #expect(model.target == safari)
    }
}
