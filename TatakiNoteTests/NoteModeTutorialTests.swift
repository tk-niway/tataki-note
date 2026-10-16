import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct NoteModeTutorialTests {
    private static let ownPid: pid_t = 4242
    private let own = InsertionTarget(processIdentifier: NoteModeTutorialTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let other = InsertionTarget(processIdentifier: pid_t.max - 1, bundleIdentifier: "com.example.Other", localizedName: "Other")
    private let hotkey = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])

    private func withModel(
        mode: AppMode,
        hotkey: PanelShortcut?? = nil,
        _ body: (TutorialModel, AppSettings) throws -> Void
    ) throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.selectAppMode(mode, hotkey: nil)
        let hotkeyValue: PanelShortcut? = hotkey ?? self.hotkey
        let model = TutorialModel(ownProcessIdentifier: Self.ownPid, settings: settings, hotkey: { hotkeyValue })
        try body(model, settings)
    }

    @MainActor
    private final class ControllerFixture {
        let defaults: TemporaryDefaults
        let settings: AppSettings
        let panelModel = PanelModel()
        let session: DraftSession
        let controller: TutorialWindowController

        init(mode: AppMode) throws {
            defaults = try TemporaryDefaults()
            settings = defaults.makeSettings()
            settings.selectAppMode(mode, hotkey: nil)
            session = DraftSession(panel: panelModel, library: DraftLibrary(store: .inMemory))
            controller = TutorialWindowController(
                settings: settings,
                panelModel: panelModel,
                draftSession: session,
                ownProcessIdentifier: NoteModeTutorialTests.ownPid,
                focusWindow: { _ in }
            )
        }

        var model: TutorialModel { controller.model }

        func tearDown() {
            controller.close()
            defaults.remove()
        }
    }

    // MARK: - AC-18 進み方(モデル)

    @Test("AC-18: ノートモードでは挿入先が無くてもパネルが開くと手順「書いて保存する」に進み、注意は出ない")
    func openingPanelWithoutTargetAdvancesToSaveDraft() throws {
        try withModel(mode: .note) { model, _ in
            #expect(model.currentStep == .openPanel)

            model.panelDidChange(isPresented: true, target: nil, text: "")

            #expect(model.currentStep == .saveDraft)
            #expect(model.isCompleted(.openPanel))
            #expect(!model.isCompleted(.saveDraft))
            #expect(!model.isShowingOtherTargetWarning)
        }
    }

    @Test("AC-18: ノートモードでは別のアプリが挿入先でも手順が進み、別のアプリの注意は出ない")
    func otherTargetDoesNotShowWarningInNoteMode() throws {
        try withModel(mode: .note) { model, _ in
            model.panelDidChange(isPresented: true, target: other, text: "")

            #expect(model.currentStep == .saveDraft)
            #expect(!model.isShowingOtherTargetWarning)
        }
    }

    @Test("AC-18: ノートモードでパネルが閉じている通知では手順が進まない")
    func closedPanelDoesNotAdvanceInNoteMode() throws {
        try withModel(mode: .note) { model, _ in
            model.panelDidChange(isPresented: false, target: nil, text: "")

            #expect(model.currentStep == .openPanel)
        }
    }

    @Test("AC-18: ノートモードでは文章を書いても改行を入れても手順「書いて保存する」から進まない")
    func typingDoesNotLeaveSaveDraftStep() throws {
        try withModel(mode: .note) { model, _ in
            model.panelDidChange(isPresented: true, target: nil, text: "")
            model.panelDidChange(isPresented: true, target: nil, text: "1行目\n2行目")

            #expect(model.currentStep == .saveDraft)
        }
    }

    @Test("AC-18: 手順「書いて保存する」で下書きに保存されると「次の一歩」に進む")
    func draftSaveAdvancesToNextSteps() throws {
        try withModel(mode: .note) { model, _ in
            model.panelDidChange(isPresented: true, target: nil, text: "")

            model.draftDidSave()

            #expect(model.currentStep == .nextSteps)
            #expect(model.isCompleted(.openPanel))
            #expect(model.isCompleted(.saveDraft))
            #expect(model.showsFinishButton)
        }
    }

    @Test("AC-18: 手順「書いて保存する」より前の保存では進まない")
    func saveBeforeSaveDraftStepDoesNotAdvance() throws {
        try withModel(mode: .note) { model, _ in
            model.draftDidSave()

            #expect(model.currentStep == .openPanel)
            #expect(!model.isCompleted(.openPanel))
        }
    }

    @Test("AC-18: 「次の一歩」に進んだあとの保存や、パネルの通知では手順が戻らず進まない")
    func nextStepsStaysAfterFurtherEvents() throws {
        try withModel(mode: .note) { model, _ in
            model.panelDidChange(isPresented: true, target: nil, text: "")
            model.draftDidSave()

            model.draftDidSave()
            model.panelDidChange(isPresented: true, target: nil, text: "もう一度")

            #expect(model.currentStep == .nextSteps)
        }
    }

    @Test("AC-18: インサートモードでは保存しても手順が進まず、進み方は今と同じ")
    func insertModeIgnoresDraftSave() throws {
        try withModel(mode: .insert) { model, _ in
            model.draftDidSave()
            #expect(model.currentStep == .openPanel)

            model.panelDidChange(isPresented: true, target: own, text: "")
            #expect(model.currentStep == .writeWithNewline)

            model.draftDidSave()
            #expect(model.currentStep == .writeWithNewline)

            model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            #expect(model.currentStep == .send)

            model.draftDidSave()
            #expect(model.currentStep == .send)
        }
    }

    @Test("AC-18: インサートモードでは挿入先が無いパネルでは進まず、別のアプリの注意が出る")
    func insertModeStillNeedsOwnTarget() throws {
        try withModel(mode: .insert) { model, _ in
            model.panelDidChange(isPresented: true, target: nil, text: "")
            #expect(model.currentStep == .openPanel)

            model.panelDidChange(isPresented: true, target: other, text: "")
            #expect(model.currentStep == .openPanel)
            #expect(model.isShowingOtherTargetWarning)
        }
    }

    // MARK: - AC-18 保存の配線(窓)

    @Test("AC-18: ノートモードのチュートリアルを開いてパネルを開くと、挿入先なしでも手順「書いて保存する」に進む")
    func windowAdvancesWhenPanelOpensWithoutTarget() async throws {
        let fixture = try ControllerFixture(mode: .note)
        defer { fixture.tearDown() }
        fixture.controller.show()
        #expect(fixture.model.currentStep == .openPanel)

        fixture.panelModel.present(target: nil)
        await yieldUntil { fixture.model.currentStep == .saveDraft }

        #expect(fixture.model.currentStep == .saveDraft)
        #expect(!fixture.model.isShowingOtherTargetWarning)
    }

    @Test("AC-18: 手順「書いて保存する」で下書きに保存すると「次の一歩」に進む(⌘S・保存のアイコン)")
    func windowAdvancesWhenDraftIsSaved() async throws {
        let fixture = try ControllerFixture(mode: .note)
        defer { fixture.tearDown() }
        fixture.controller.show()
        fixture.panelModel.present(target: nil)
        await yieldUntil { fixture.model.currentStep == .saveDraft }
        #expect(fixture.model.currentStep == .saveDraft)

        fixture.panelModel.text = "メモ"
        fixture.session.saveCurrent()
        await yieldUntil { fixture.model.currentStep == .nextSteps }

        #expect(fixture.model.currentStep == .nextSteps)
    }

    @Test("AC-18: 文章が空で保存されなかったときは進まない")
    func windowDoesNotAdvanceWhenNothingIsSaved() async throws {
        let fixture = try ControllerFixture(mode: .note)
        defer { fixture.tearDown() }
        fixture.controller.show()
        fixture.panelModel.present(target: nil)
        await yieldUntil { fixture.model.currentStep == .saveDraft }
        #expect(fixture.model.currentStep == .saveDraft)

        fixture.session.saveCurrent()
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.session.lastSaveEvent == nil)
        #expect(fixture.model.currentStep == .saveDraft)
    }

    @Test("AC-18: 手順「書いて保存する」になる前の保存では進まない")
    func windowIgnoresSaveBeforeSaveDraftStep() async throws {
        let fixture = try ControllerFixture(mode: .note)
        defer { fixture.tearDown() }
        fixture.controller.show()
        fixture.panelModel.text = "先に書いた文章"
        fixture.session.saveCurrent()
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.session.lastSaveEvent != nil)
        #expect(fixture.model.currentStep == .openPanel)

        fixture.panelModel.present(target: nil)
        await yieldUntil { fixture.model.currentStep == .saveDraft }
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.model.currentStep == .saveDraft)
    }

    @Test("AC-18: チュートリアルを開く前の保存は数えない")
    func windowIgnoresSaveBeforeOpening() async throws {
        let fixture = try ControllerFixture(mode: .note)
        defer { fixture.tearDown() }
        fixture.panelModel.text = "窓を開く前の文章"
        fixture.session.saveCurrent()

        fixture.controller.show()
        fixture.panelModel.present(target: nil)
        await yieldUntil { fixture.model.currentStep == .saveDraft }
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.model.currentStep == .saveDraft)
    }

    @Test("AC-18: インサートモードのチュートリアルでは、保存しても手順が進まない")
    func windowInsertModeIgnoresSave() async throws {
        let fixture = try ControllerFixture(mode: .insert)
        defer { fixture.tearDown() }
        fixture.controller.show()

        fixture.panelModel.text = "メモ"
        fixture.session.saveCurrent()
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.session.lastSaveEvent != nil)
        #expect(fixture.model.currentStep == .openPanel)
    }

    // MARK: - AC-26 手順と文

    @Test("AC-26: ノートモードの手順は「パネルを開く」「書いて保存する」「次の一歩」の3つで、番号は1〜3")
    func noteModeStepsAndNumbers() throws {
        try withModel(mode: .note) { model, _ in
            #expect(model.steps == [.openPanel, .saveDraft, .nextSteps])
            #expect(model.stepNumber(.openPanel) == 1)
            #expect(model.stepNumber(.saveDraft) == 2)
            #expect(model.stepNumber(.nextSteps) == 3)
            #expect(model.stepNumber(.writeWithNewline) == nil)
            #expect(model.stepNumber(.send) == nil)
        }
    }

    @Test("AC-26: インサートモードの手順・番号・完了は今と同じ")
    func insertModeStepsAndNumbers() throws {
        try withModel(mode: .insert) { model, _ in
            #expect(model.steps == [.openPanel, .writeWithNewline, .send, .nextSteps])
            #expect(model.stepNumber(.openPanel) == 1)
            #expect(model.stepNumber(.writeWithNewline) == 2)
            #expect(model.stepNumber(.send) == 3)
            #expect(model.stepNumber(.nextSteps) == 4)
            #expect(model.stepNumber(.saveDraft) == nil)

            model.panelDidChange(isPresented: true, target: own, text: "")
            model.panelDidChange(isPresented: true, target: own, text: "a\nb")

            #expect(model.currentStep == .send)
            #expect(model.isCompleted(.openPanel))
            #expect(model.isCompleted(.writeWithNewline))
            #expect(!model.isCompleted(.send))
            #expect(!model.isCompleted(.nextSteps))
            #expect(!model.isCompleted(.saveDraft))
        }
    }

    @Test("AC-26: ノートモードでは並びに無い手順は完了にならない")
    func stepsOutsideNoteModeOrderAreNeverCompleted() throws {
        try withModel(mode: .note) { model, _ in
            model.panelDidChange(isPresented: true, target: nil, text: "")
            model.draftDidSave()

            #expect(model.isCompleted(.openPanel))
            #expect(model.isCompleted(.saveDraft))
            #expect(!model.isCompleted(.nextSteps))
            #expect(!model.isCompleted(.writeWithNewline))
            #expect(!model.isCompleted(.send))
        }
    }

    @Test("AC-26: 今の手順が並びに無い間(切り替えた直後)はどの手順も完了にならない")
    func nothingIsCompletedWhileCurrentStepIsOutsideOrder() throws {
        try withModel(mode: .insert) { model, settings in
            model.panelDidChange(isPresented: true, target: own, text: "")
            #expect(model.currentStep == .writeWithNewline)

            settings.selectAppMode(.note, hotkey: nil)

            #expect(model.stepNumber(model.currentStep) == nil)
            #expect(TutorialStep.allCases.allSatisfy { !model.isCompleted($0) })
        }
    }

    @Test("AC-26: ノートモードの冒頭の文は、パネルを開いて保存するまでを試す案内で、インサートモードの文とは違う")
    func noteModeIntroduction() throws {
        try withModel(mode: .note) { model, _ in
            #expect(model.introductionText == TutorialModel.noteModeIntroduction)
            #expect(model.introductionText != TutorialModel.introduction)
            #expect(model.introductionText.contains("パネルを開いて保存するまで"))
            #expect(!model.introductionText.contains("練習用のチャット"))
        }
        try withModel(mode: .insert) { model, _ in
            #expect(model.introductionText == TutorialModel.introduction)
        }
    }

    @Test("AC-26: ノートモードの手順1の文は練習用のチャットのクリックを求めず、ホットキーを示す")
    func noteModeOpenPanelInstruction() throws {
        try withModel(mode: .note) { model, _ in
            let text = model.openPanelInstruction
            #expect(text.contains(hotkey.displayText))
            #expect(!text.contains("練習用のチャット"))
            #expect(!text.contains("クリック"))
        }
    }

    @Test("AC-26: ホットキーが無いときの手順1の文は、ノートモードでもインサートモードと同じ")
    func openPanelInstructionWithoutHotkeyMatchesInsertMode() throws {
        var insertParts: [TutorialTextPart] = []
        try withModel(mode: .insert, hotkey: .some(nil)) { model, _ in
            insertParts = model.openPanelInstructionParts
        }
        try withModel(mode: .note, hotkey: .some(nil)) { model, _ in
            #expect(model.openPanelInstructionParts == insertParts)
            #expect(model.openPanelInstruction.contains("ホットキーが設定されていません"))
        }
    }

    @Test("AC-26: インサートモードの手順1の文は今と同じ(練習用のチャットのクリックを求める)")
    func insertModeOpenPanelInstructionUnchanged() throws {
        try withModel(mode: .insert) { model, _ in
            let text = model.openPanelInstruction
            #expect(text.contains("練習用のチャットの入力欄をクリック"))
            #expect(text.contains(hotkey.displayText))
        }
    }

    @Test("AC-26: 手順「書いて保存する」の文は ⌘S と保存のアイコンを示す")
    func saveDraftInstructionMentionsShortcutAndIcon() throws {
        try withModel(mode: .note) { model, _ in
            let text = model.saveDraftInstruction
            #expect(text.contains("⌘S"))
            #expect(text.contains("下書きに保存"))
            #expect(text.contains("アイコン"))
        }
    }

    @Test("AC-26: ノートモードでは練習用のチャットを出さず、インサートモードでは出す")
    func practiceChatVisibility() throws {
        try withModel(mode: .note) { model, _ in
            #expect(!model.showsPracticeChat)
        }
        try withModel(mode: .insert) { model, _ in
            #expect(model.showsPracticeChat)
        }
    }

    // MARK: - AC-27 モードの切り替え

    @Test("AC-27: モードが変わると手順1から始め直し、練習用のチャットと入力欄も元に戻る")
    func appModeDidChangeResetsEverything() throws {
        try withModel(mode: .insert) { model, _ in
            model.panelDidChange(isPresented: true, target: own, text: "")
            model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            model.practiceText = "書きかけ"
            model.sendPracticeMessage("hello")
            model.practiceText = "もう一度"
            model.skip()
            #expect(model.currentStep == .send)
            #expect(model.chat != PracticeChat())

            model.appModeDidChange()

            #expect(model.currentStep == .openPanel)
            #expect(model.chat == PracticeChat())
            #expect(model.practiceText.isEmpty)
            #expect(!model.isShowingSkipNotice)
            #expect(!model.isShowingOtherTargetWarning)
        }
    }

    @Test("AC-27: チュートリアルを開いたままノートモードにすると、ノートモードの手順1から始め直す")
    func switchingToNoteModeRestartsTutorial() async throws {
        let fixture = try ControllerFixture(mode: .insert)
        defer { fixture.tearDown() }
        let own = InsertionTarget(processIdentifier: Self.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
        fixture.controller.show()
        fixture.panelModel.present(target: own)
        await yieldUntil { fixture.model.currentStep == .writeWithNewline }
        fixture.model.practiceText = "書きかけ"
        fixture.model.sendPracticeMessage("hello")
        fixture.model.practiceText = "もう一度"
        #expect(fixture.model.currentStep == .writeWithNewline)

        fixture.settings.selectAppMode(.note, hotkey: nil)
        await yieldUntil { fixture.model.currentStep == .openPanel }

        #expect(fixture.model.currentStep == .openPanel)
        #expect(fixture.model.steps == [.openPanel, .saveDraft, .nextSteps])
        #expect(fixture.model.chat == PracticeChat())
        #expect(fixture.model.practiceText.isEmpty)
        #expect(!fixture.model.showsPracticeChat)
    }

    @Test("AC-27: チュートリアルを開いたままインサートモードに戻すと、インサートモードの手順1から始め直す")
    func switchingToInsertModeRestartsTutorial() async throws {
        let fixture = try ControllerFixture(mode: .note)
        defer { fixture.tearDown() }
        fixture.controller.show()
        fixture.panelModel.present(target: nil)
        await yieldUntil { fixture.model.currentStep == .saveDraft }
        #expect(fixture.model.currentStep == .saveDraft)

        fixture.settings.selectAppMode(.insert, hotkey: nil)
        await yieldUntil { fixture.model.currentStep == .openPanel }

        #expect(fixture.model.currentStep == .openPanel)
        #expect(fixture.model.steps == [.openPanel, .writeWithNewline, .send, .nextSteps])
        #expect(fixture.model.chat == PracticeChat())
        #expect(fixture.model.showsPracticeChat)
    }

    @Test("AC-27: 窓を閉じたあとのモードの切り替えは追わない")
    func closedWindowDoesNotFollowModeChange() async throws {
        let fixture = try ControllerFixture(mode: .note)
        defer { fixture.tearDown() }
        fixture.controller.show()
        fixture.panelModel.present(target: nil)
        await yieldUntil { fixture.model.currentStep == .saveDraft }
        #expect(fixture.model.currentStep == .saveDraft)

        fixture.controller.close()
        fixture.settings.selectAppMode(.insert, hotkey: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.model.currentStep == .saveDraft)
    }
}
