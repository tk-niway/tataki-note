import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct TutorialModelInsertModeTests {
    private static let ownPid: pid_t = 4242
    private let own = InsertionTarget(processIdentifier: TutorialModelInsertModeTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let other = InsertionTarget(processIdentifier: pid_t.max - 1, bundleIdentifier: "com.example.Other", localizedName: "Other")
    private let hotkey = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])

    private func withModel(
        newDraftMode: DraftMode = .insert,
        _ body: (TutorialModel) throws -> Void
    ) throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.newDraftMode = newDraftMode
        let hotkeyValue = hotkey
        let model = TutorialModel(ownProcessIdentifier: Self.ownPid, settings: settings, hotkey: { hotkeyValue })
        try body(model)
    }

    @MainActor
    private final class ControllerFixture {
        let defaults: TemporaryDefaults
        let settings: AppSettings
        let panelModel = PanelModel()
        let session: DraftSession
        let controller: TutorialWindowController

        init(newDraftMode: DraftMode) throws {
            let defaults = try TemporaryDefaults()
            let settings = defaults.makeSettings()
            settings.newDraftMode = newDraftMode
            self.defaults = defaults
            self.settings = settings
            session = DraftSession(
                panel: panelModel,
                library: DraftLibrary(store: .inMemory),
                ownProcessIdentifier: TutorialModelInsertModeTests.ownPid,
                newDraftMode: { settings.newDraftMode }
            )
            controller = TutorialWindowController(
                settings: settings,
                panelModel: panelModel,
                draftSession: session,
                ownProcessIdentifier: TutorialModelInsertModeTests.ownPid,
                focusWindow: { _ in }
            )
        }

        var model: TutorialModel { controller.model }

        func tearDown() {
            controller.close()
            defaults.remove()
        }
    }

    // MARK: - AC-22 手順

    @Test("AC-22: 手順はいつも「パネルを開く」「改行して書く」「送る」「次の一歩」の4つで、番号は1〜4", arguments: DraftMode.allCases)
    func stepsAreAlwaysTheFourInsertSteps(setting: DraftMode) throws {
        try withModel(newDraftMode: setting) { model in
            #expect(model.steps == [.openPanel, .writeWithNewline, .send, .nextSteps])
            #expect(model.stepNumber(.openPanel) == 1)
            #expect(model.stepNumber(.writeWithNewline) == 2)
            #expect(model.stepNumber(.send) == 3)
            #expect(model.stepNumber(.nextSteps) == 4)
            #expect(TutorialStep.allCases == model.steps)
        }
    }

    @Test("AC-22: 手順の進み方はインサートと同じ(自分が挿入先で開く → 改行を入れる)", arguments: DraftMode.allCases)
    func stepsAdvanceAsInsertFlow(setting: DraftMode) throws {
        try withModel(newDraftMode: setting) { model in
            model.panelDidChange(isPresented: true, target: own, text: "")
            #expect(model.currentStep == .writeWithNewline)

            model.panelDidChange(isPresented: true, target: own, text: "a")
            #expect(model.currentStep == .writeWithNewline)

            model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            #expect(model.currentStep == .send)
            #expect(model.isCompleted(.openPanel))
            #expect(model.isCompleted(.writeWithNewline))
            #expect(!model.isCompleted(.send))
            #expect(!model.isCompleted(.nextSteps))
        }
    }

    @Test("AC-22: 挿入先が無いパネルでは進まず、別のアプリが挿入先なら注意が出る")
    func needsOwnTarget() throws {
        try withModel { model in
            model.panelDidChange(isPresented: true, target: nil, text: "")
            #expect(model.currentStep == .openPanel)
            #expect(!model.isShowingOtherTargetWarning)

            model.panelDidChange(isPresented: true, target: other, text: "")
            #expect(model.currentStep == .openPanel)
            #expect(model.isShowingOtherTargetWarning)
        }
    }

    @Test("AC-22: パネルが閉じている通知では手順が進まない")
    func closedPanelDoesNotAdvance() throws {
        try withModel { model in
            model.panelDidChange(isPresented: false, target: own, text: "")

            #expect(model.currentStep == .openPanel)
        }
    }

    @Test("AC-22: 冒頭の文はインサートの文で、練習用のチャットを案内する")
    func introductionIsTheInsertText() {
        #expect(TutorialModel.introduction.contains("練習用のチャット"))
        #expect(!TutorialModel.introduction.contains("保存するまで"))
    }

    @Test("AC-22: 手順1の文は、練習用のチャットのクリックを求めてホットキーを示す", arguments: DraftMode.allCases)
    func openPanelInstructionAsksToClickPracticeChat(setting: DraftMode) throws {
        try withModel(newDraftMode: setting) { model in
            let text = model.openPanelInstruction
            #expect(text.contains("練習用のチャットの入力欄をクリック"))
            #expect(text.contains(hotkey.displayText))
        }
    }

    @Test("AC-22: 窓を開いたあとに下書きを保存しても、手順は進まない")
    func savingDraftDoesNotAdvanceSteps() async throws {
        let fixture = try ControllerFixture(newDraftMode: .insert)
        defer { fixture.tearDown() }
        fixture.controller.show()

        fixture.panelModel.text = "メモ"
        fixture.session.saveCurrent()
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.session.lastSaveEvent != nil)
        #expect(fixture.model.currentStep == .openPanel)
    }

    @Test("AC-22: 設定が「ノート」でも、窓を開いてパネルを開くと手順2に進む")
    func windowAdvancesWithNoteSetting() async throws {
        let fixture = try ControllerFixture(newDraftMode: .note)
        defer { fixture.tearDown() }
        fixture.controller.show()
        #expect(fixture.model.currentStep == .openPanel)

        fixture.panelModel.present(target: own)
        await yieldUntil { fixture.model.currentStep == .writeWithNewline }

        #expect(fixture.model.currentStep == .writeWithNewline)
    }

    @Test("AC-22: 窓を開いたまま新しい書きかけのモードを変えても、手順は始め直さない")
    func changingSettingDoesNotRestartTutorial() async throws {
        let fixture = try ControllerFixture(newDraftMode: .insert)
        defer { fixture.tearDown() }
        fixture.controller.show()
        fixture.panelModel.present(target: own)
        await yieldUntil { fixture.model.currentStep == .writeWithNewline }
        fixture.model.practiceText = "書きかけ"

        fixture.settings.newDraftMode = .note
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.model.currentStep == .writeWithNewline)
        #expect(fixture.model.practiceText == "書きかけ")
    }

    // MARK: - AC-23 チュートリアルを開いている間のインサート

    @Test("AC-23: 見えていなかった窓を開くと、今の書きかけがインサートになる")
    func showSwitchesCurrentDraftToInsert() async throws {
        let fixture = try ControllerFixture(newDraftMode: .note)
        defer { fixture.tearDown() }
        #expect(fixture.session.mode == .note)

        fixture.controller.show()

        #expect(fixture.session.mode == .insert)
        #expect(fixture.session.isInsertModeForced)
    }

    @Test("AC-23: 開いている間は、新しい書きかけ(⌘N)が設定に関わらずインサートで始まる")
    func newDraftWhileOpenStartsInInsert() async throws {
        let fixture = try ControllerFixture(newDraftMode: .note)
        defer { fixture.tearDown() }
        fixture.controller.show()
        fixture.session.toggleMode()
        #expect(fixture.session.mode == .note)

        fixture.session.request(.newScratch)

        #expect(fixture.session.mode == .insert)
    }

    @Test("AC-23: 開いている間は、挿入できた後の新しい書きかけもインサートで始まる")
    func newDraftAfterInsertionWhileOpenStartsInInsert() async throws {
        let fixture = try ControllerFixture(newDraftMode: .note)
        defer { fixture.tearDown() }
        fixture.controller.show()
        fixture.panelModel.present(target: other)
        fixture.panelModel.text = "send"
        fixture.session.toggleMode()
        #expect(fixture.session.mode == .note)

        let plan = fixture.session.prepareCommit {
            fixture.panelModel.prepareCommit(isAccessibilityTrusted: true)
        }
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(fixture.session.mode == .insert)
    }

    @Test("AC-23: 開いている間も ⌘E 相当の切り替えはできる")
    func togglingIsAllowedWhileOpen() async throws {
        let fixture = try ControllerFixture(newDraftMode: .note)
        defer { fixture.tearDown() }
        fixture.controller.show()
        #expect(fixture.session.mode == .insert)

        fixture.session.toggleMode()
        #expect(fixture.session.mode == .note)

        fixture.session.toggleMode()
        #expect(fixture.session.mode == .insert)

        fixture.session.toggleMode()
        fixture.session.switchToInsert()
        #expect(fixture.session.mode == .insert)
    }

    @Test("AC-23: 窓を閉じると、新しい書きかけは設定どおりに戻り、今の書きかけのモードは変わらない")
    func closeRestoresSettingForNewDrafts() async throws {
        let fixture = try ControllerFixture(newDraftMode: .note)
        defer { fixture.tearDown() }
        fixture.controller.show()
        #expect(fixture.session.mode == .insert)

        fixture.controller.close()

        #expect(!fixture.session.isInsertModeForced)
        #expect(fixture.session.mode == .insert)

        fixture.session.request(.newScratch)
        #expect(fixture.session.mode == .note)
    }

    @Test("AC-23: 見えている窓を開き直しても、今の書きかけのモードは変えない")
    func showingVisibleWindowKeepsMode() async throws {
        let fixture = try ControllerFixture(newDraftMode: .insert)
        defer { fixture.tearDown() }
        fixture.controller.show()
        fixture.session.toggleMode()
        #expect(fixture.session.mode == .note)

        fixture.controller.show()

        #expect(fixture.session.mode == .note)
        #expect(fixture.session.isInsertModeForced)
    }

    @Test("AC-23: 閉じた後にもう一度開くと、また今の書きかけがインサートになる")
    func reopeningAfterCloseSwitchesToInsertAgain() async throws {
        let fixture = try ControllerFixture(newDraftMode: .insert)
        defer { fixture.tearDown() }
        fixture.controller.show()
        fixture.controller.close()
        fixture.session.toggleMode()
        #expect(fixture.session.mode == .note)

        fixture.controller.show()

        #expect(fixture.session.mode == .insert)
        #expect(fixture.session.isInsertModeForced)
    }

    @Test("AC-23: DraftSession の開始・終了は、強制の印だけを切り替える")
    func beginAndEndToggleForcedFlag() {
        let panel = PanelModel()
        let session = DraftSession(panel: panel, library: DraftLibrary(store: .inMemory), newDraftMode: { .note })
        #expect(session.mode == .note)
        #expect(!session.isInsertModeForced)

        session.beginInsertModeForTutorial()
        #expect(session.mode == .insert)
        #expect(session.isInsertModeForced)

        session.endInsertModeForTutorial()
        #expect(!session.isInsertModeForced)
        #expect(session.mode == .insert)
    }
}
