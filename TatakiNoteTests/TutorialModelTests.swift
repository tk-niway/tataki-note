import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct TutorialModelTests {
    private static let ownPid: pid_t = 4242
    private let own = InsertionTarget(processIdentifier: TutorialModelTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let other = InsertionTarget(processIdentifier: pid_t.max - 1, bundleIdentifier: "com.example.Other", localizedName: "Other")
    private let hotkey = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])

    private final class HotkeyBox {
        var value: PanelShortcut?

        init(_ value: PanelShortcut?) {
            self.value = value
        }
    }

    private func withModel(
        hotkey: PanelShortcut?? = nil,
        _ body: (TutorialModel, AppSettings, HotkeyBox) throws -> Void
    ) throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.commitKey = nil
        settings.commitAndSendKey = nil
        let box = HotkeyBox(hotkey ?? self.hotkey)
        let model = TutorialModel(ownProcessIdentifier: Self.ownPid, settings: settings, hotkey: { box.value })
        try body(model, settings, box)
    }

    private func moveToWriteStep(_ model: TutorialModel, text: String = "") {
        model.panelDidChange(isPresented: true, target: own, text: text)
    }

    private func moveToInsertStep(_ model: TutorialModel) {
        moveToWriteStep(model)
        model.panelDidChange(isPresented: true, target: own, text: "a\nb")
    }

    private func moveToNextStepsStep(_ model: TutorialModel) {
        moveToInsertStep(model)
        model.insertionRequested(text: "a\nb", target: own, sendsAfterInsert: false)
        model.practiceText = "a\nb"
    }

    // MARK: - 手順1(AC-14)

    @Test("AC-14: 自分自身が挿入先のパネルが開くと手順1が完了して手順2に進む")
    func openingPanelForOwnTargetCompletesStepOne() throws {
        try withModel { model, _, _ in
            #expect(model.currentStep == .openPanel)
            #expect(!model.isCompleted(.openPanel))

            model.panelDidChange(isPresented: true, target: own, text: "")

            #expect(model.currentStep == .writeWithNewline)
            #expect(model.isCompleted(.openPanel))
            #expect(!model.isCompleted(.writeWithNewline))
            #expect(!model.isShowingOtherTargetWarning)
        }
    }

    @Test("AC-14: 他のアプリが挿入先のパネルが開いても進まず、注意が出る")
    func openingPanelForOtherTargetShowsWarning() throws {
        try withModel { model, _, _ in
            model.panelDidChange(isPresented: true, target: other, text: "")

            #expect(model.currentStep == .openPanel)
            #expect(!model.isCompleted(.openPanel))
            #expect(model.isShowingOtherTargetWarning)
        }
    }

    @Test("AC-14: 自分自身が挿入先のパネルが開くと、挿入先の注意が消える")
    func ownTargetClearsWarning() throws {
        try withModel { model, _, _ in
            model.panelDidChange(isPresented: true, target: other, text: "")
            #expect(model.isShowingOtherTargetWarning)

            model.panelDidChange(isPresented: true, target: own, text: "")

            #expect(!model.isShowingOtherTargetWarning)
            #expect(model.currentStep == .writeWithNewline)
        }
    }

    @Test("AC-14: パネルが閉じている通知や挿入先が無い通知では進まず、注意も出ない")
    func closedPanelOrMissingTargetDoesNothing() throws {
        try withModel { model, _, _ in
            model.panelDidChange(isPresented: false, target: own, text: "")
            model.panelDidChange(isPresented: true, target: nil, text: "")

            #expect(model.currentStep == .openPanel)
            #expect(!model.isShowingOtherTargetWarning)
        }
    }

    @Test("AC-14: 手順2・3の間も他のアプリが挿入先のパネルが開くと注意が出るが、手順4では出ない")
    func warningShowsDuringStepsTwoAndThreeOnly() throws {
        try withModel { model, _, _ in
            moveToWriteStep(model)
            model.panelDidChange(isPresented: true, target: other, text: "")
            #expect(model.currentStep == .writeWithNewline)
            #expect(model.isShowingOtherTargetWarning)

            model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            #expect(model.currentStep == .insert)
            #expect(!model.isShowingOtherTargetWarning)
            model.panelDidChange(isPresented: true, target: other, text: "a\nb")
            #expect(model.currentStep == .insert)
            #expect(model.isShowingOtherTargetWarning)

            model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            model.insertionRequested(text: "a\nb", target: own, sendsAfterInsert: false)
            model.practiceText = "a\nb"
            #expect(model.currentStep == .nextSteps)
            #expect(!model.isShowingOtherTargetWarning)

            model.panelDidChange(isPresented: true, target: other, text: "")
            #expect(!model.isShowingOtherTargetWarning)
        }
    }

    // MARK: - 手順2(AC-15)

    @Test("AC-15: 手順2に入った後にパネルの文章の改行が増えると手順3に進む")
    func addingNewlineCompletesStepTwo() throws {
        try withModel { model, _, _ in
            moveToWriteStep(model)

            model.panelDidChange(isPresented: true, target: own, text: "abc\ndef")

            #expect(model.currentStep == .insert)
            #expect(model.isCompleted(.writeWithNewline))
        }
    }

    @Test("AC-15: 改行の無い入力では手順2が進まない")
    func typingWithoutNewlineDoesNotComplete() throws {
        try withModel { model, _, _ in
            moveToWriteStep(model)

            model.panelDidChange(isPresented: true, target: own, text: "abc")
            model.panelDidChange(isPresented: true, target: own, text: "abcdef")

            #expect(model.currentStep == .writeWithNewline)
            #expect(!model.isCompleted(.writeWithNewline))
        }
    }

    @Test("AC-15: 手順2に入る前からあった改行では進まず、そこから増えると進む")
    func newlinesBeforeStepTwoDoNotCount() throws {
        try withModel { model, _, _ in
            model.panelDidChange(isPresented: true, target: own, text: "draft\nwith\nlines")
            #expect(model.currentStep == .writeWithNewline)

            model.panelDidChange(isPresented: true, target: own, text: "draft\nwith\nlines")
            model.panelDidChange(isPresented: true, target: own, text: "draft\nwith\nlines!")
            #expect(model.currentStep == .writeWithNewline)

            model.panelDidChange(isPresented: true, target: own, text: "draft\nwith\nlines\n")
            #expect(model.currentStep == .insert)
        }
    }

    @Test("AC-15: 他のアプリが挿入先のパネルの改行では手順2が進まない")
    func newlineForOtherTargetDoesNotComplete() throws {
        try withModel { model, _, _ in
            moveToWriteStep(model)

            model.panelDidChange(isPresented: true, target: other, text: "abc\ndef")

            #expect(model.currentStep == .writeWithNewline)
        }
    }

    // MARK: - 手順3(AC-16)

    @Test("AC-16: 自分自身への挿入を要求した文章が練習用の入力欄に入ると手順4に進む")
    func requestedInsertionCompletesStepThree() throws {
        try withModel { model, _, _ in
            moveToInsertStep(model)

            model.insertionRequested(text: "abc\ndef", target: own, sendsAfterInsert: false)
            #expect(model.currentStep == .insert)
            model.practiceText = "abc\ndef"

            #expect(model.currentStep == .nextSteps)
            #expect(model.isCompleted(.insert))
        }
    }

    @Test("AC-16: 練習用の入力欄に直接書いただけでは手順3が進まない")
    func typingDirectlyDoesNotCompleteStepThree() throws {
        try withModel { model, _, _ in
            moveToInsertStep(model)

            model.practiceText = "abc\ndef"
            model.insertionRequested(text: "xyz", target: own, sendsAfterInsert: false)
            model.practiceText = "abc\ndefg"

            #expect(model.currentStep == .insert)
        }
    }

    @Test("AC-16: 手順1・2の間に挿入を要求した文章が入っても手順は進まない")
    func insertionBeforeStepThreeDoesNotAdvance() throws {
        try withModel { model, _, _ in
            model.insertionRequested(text: "early", target: own, sendsAfterInsert: false)
            model.practiceText = "early"
            #expect(model.currentStep == .openPanel)

            moveToWriteStep(model)
            model.insertionRequested(text: "early two", target: own, sendsAfterInsert: false)
            model.practiceText = "early early two"
            #expect(model.currentStep == .writeWithNewline)

            model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            #expect(model.currentStep == .insert)
            model.practiceText = "early early two!"
            #expect(model.currentStep == .insert)
        }
    }

    @Test("AC-16: 他のアプリへの挿入の要求では手順3が進まない")
    func insertionForOtherTargetIsIgnored() throws {
        try withModel { model, _, _ in
            moveToInsertStep(model)

            model.insertionRequested(text: "abc", target: other, sendsAfterInsert: false)
            model.practiceText = "abc"

            #expect(model.currentStep == .insert)
        }
    }

    @Test("AC-16: 要求の前から入力欄にあった同じ文章では進まず、増えたときに進む")
    func existingTextDoesNotCompleteStepThree() throws {
        try withModel { model, _, _ in
            moveToInsertStep(model)
            model.practiceText = "abc"

            model.insertionRequested(text: "abc", target: own, sendsAfterInsert: false)
            model.practiceText = "abc "
            #expect(model.currentStep == .insert)

            model.practiceText = "abc abc"
            #expect(model.currentStep == .nextSteps)
        }
    }

    @Test("AC-16: 空の文章の挿入の要求は覚えない")
    func emptyInsertionIsIgnored() throws {
        try withModel { model, _, _ in
            moveToInsertStep(model)

            model.insertionRequested(text: "", target: own, sendsAfterInsert: false)
            model.practiceText = "abc"

            #expect(model.currentStep == .insert)
        }
    }

    // MARK: - キーの表示(AC-17)

    @Test("AC-17: 手順1の文に今のホットキーの表示が入る")
    func openPanelInstructionContainsHotkey() throws {
        try withModel { model, _, _ in
            #expect(model.hotkeyText == hotkey.displayText)
            #expect(model.openPanelInstruction.contains(hotkey.displayText))
            #expect(model.openPanelInstruction.contains("クリック"))
        }
    }

    @Test("AC-17: ホットキーが未設定なら、設定の「一般」とメニューバーで開くよう案内する")
    func openPanelInstructionWithoutHotkey() throws {
        try withModel(hotkey: .some(nil)) { model, _, _ in
            #expect(model.hotkeyText == nil)
            #expect(model.openPanelInstruction.contains("ホットキーが設定されていません"))
            #expect(model.openPanelInstruction.contains("設定の「一般」"))
            #expect(model.openPanelInstruction.contains("パネルを開く"))
        }
    }

    @Test("AC-17: ホットキーを変えて読み直すと手順1の文も変わる")
    func refreshKeysUpdatesHotkeyText() throws {
        try withModel { model, _, box in
            let before = model.openPanelInstruction
            let changed = PanelShortcut(keyCode: 40, modifiers: [.command, .control])
            box.value = changed

            #expect(model.openPanelInstruction == before)
            model.refreshKeys()

            #expect(model.hotkeyText == changed.displayText)
            #expect(model.openPanelInstruction != before)
            #expect(model.openPanelInstruction.contains(changed.displayText))

            box.value = nil
            model.refreshKeys()
            #expect(model.hotkeyText == nil)
        }
    }

    @Test("AC-17: 手順3の文に今の確定キーの表示が入り、設定で変えると文も変わる")
    func insertInstructionFollowsCommitKey() throws {
        try withModel { model, settings, _ in
            settings.commitKey = .commandReturn
            let first = model.insertInstruction
            #expect(model.commitKeyText == PanelShortcut.commandReturn.displayText)
            #expect(first.contains(PanelShortcut.commandReturn.displayText))

            settings.commitKey = .commandShiftReturn
            #expect(model.commitKeyText == PanelShortcut.commandShiftReturn.displayText)
            #expect(model.insertInstruction.contains(PanelShortcut.commandShiftReturn.displayText))
            #expect(model.insertInstruction != first)
        }
    }

    @Test("AC-17: 確定キーが未設定なら、設定の「一般」で設定するよう案内する")
    func insertInstructionWithoutCommitKey() throws {
        try withModel { model, settings, _ in
            settings.commitKey = nil

            #expect(model.commitKeyText == nil)
            #expect(model.insertInstruction.contains("確定キーが設定されていません"))
            #expect(model.insertInstruction.contains("設定の「一般」"))
        }
    }

    // MARK: - スキップ(AC-18)

    @Test("AC-18: スキップするとスキップの案内の状態になる")
    func skipShowsNotice() throws {
        try withModel { model, _, _ in
            #expect(!model.isShowingSkipNotice)

            model.skip()

            #expect(model.isShowingSkipNotice)
        }
    }

    // MARK: - 開き直し(AC-19)

    @Test("AC-19: リセットすると手順1・練習用の入力欄が空・案内と注意なしに戻る")
    func resetReturnsToInitialState() throws {
        try withModel { model, _, _ in
            moveToNextStepsStep(model)
            model.practiceText = "something typed"
            model.skip()
            model.panelDidChange(isPresented: true, target: other, text: "")
            #expect(model.currentStep == .nextSteps)

            model.reset()

            #expect(model.currentStep == .openPanel)
            #expect(model.practiceText.isEmpty)
            #expect(!model.isShowingSkipNotice)
            #expect(!model.isShowingOtherTargetWarning)
            #expect(TutorialStep.allCases.allSatisfy { !model.isCompleted($0) })
        }
    }

    @Test("AC-19: リセットすると、覚えていた改行の数と挿入の要求を捨てる")
    func resetDiscardsRememberedState() throws {
        try withModel { model, _, _ in
            moveToInsertStep(model)
            model.insertionRequested(text: "abc", target: own, sendsAfterInsert: false)

            model.reset()
            moveToInsertStep(model)
            model.practiceText = "abc"

            #expect(model.currentStep == .insert)
        }
    }

    @Test("AC-19: 途中でリセットしても、保存される設定の値は変わらない")
    func resetDoesNotChangeStoredSettings() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.commitKey = .commandReturn
        settings.hasShownFirstLaunchTutorial = true
        let model = TutorialModel(ownProcessIdentifier: Self.ownPid, settings: settings, hotkey: { nil })

        model.panelDidChange(isPresented: true, target: own, text: "")
        model.skip()
        model.reset()

        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.hasShownFirstLaunchTutorial)
        #expect(reloaded.commitKey == .commandReturn)
        #expect(settings.hasShownFirstLaunchTutorial)
    }

    @Test("AC-19: 練習用の入力欄へのフォーカスの要求は、要求のたびに増える")
    func practiceFocusRequestIncreases() throws {
        try withModel { model, _, _ in
            let before = model.practiceFocusRequest

            model.requestPracticeFocus()
            model.requestPracticeFocus()

            #expect(model.practiceFocusRequest == before + 2)
        }
    }

    // MARK: - 手順4(AC-23)

    @Test("AC-23: 手順4では「完了」を出し、手順1〜3では「スキップ」を出す")
    func finishButtonShowsOnlyOnNextSteps() throws {
        try withModel { model, _, _ in
            #expect(!model.showsFinishButton)
            moveToWriteStep(model)
            #expect(!model.showsFinishButton)
            model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            #expect(model.currentStep == .insert)
            #expect(!model.showsFinishButton)

            model.insertionRequested(text: "a\nb", target: own, sendsAfterInsert: false)
            model.practiceText = "a\nb"

            #expect(model.currentStep == .nextSteps)
            #expect(model.showsFinishButton)
        }
    }

    @Test("AC-23: 確定+送信の紹介の文に今の確定+送信キーの表示が入る")
    func commitAndSendIntroductionContainsKey() throws {
        try withModel { model, settings, _ in
            settings.commitAndSendKey = .commandReturn
            #expect(model.commitAndSendKeyText == PanelShortcut.commandReturn.displayText)
            #expect(model.commitAndSendIntroduction.contains(PanelShortcut.commandReturn.displayText))
            #expect(model.commitAndSendIntroduction.contains("送信"))

            settings.commitAndSendKey = .commandShiftReturn
            #expect(model.commitAndSendIntroduction.contains(PanelShortcut.commandShiftReturn.displayText))
        }
    }

    @Test("AC-23: 確定+送信キーが未設定なら、設定の「一般」で設定できると紹介する")
    func commitAndSendIntroductionWithoutKey() throws {
        try withModel { model, settings, _ in
            settings.commitAndSendKey = nil

            #expect(model.commitAndSendKeyText == nil)
            #expect(model.commitAndSendIntroduction.contains("設定の「一般」"))
            #expect(model.commitAndSendIntroduction.contains("送信"))
        }
    }
}
