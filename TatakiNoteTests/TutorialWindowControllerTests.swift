import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct TutorialWindowControllerTests {
    private static let ownPid = ProcessInfo.processInfo.processIdentifier
    private let own = InsertionTarget(processIdentifier: TutorialWindowControllerTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let other = InsertionTarget(processIdentifier: pid_t.max - 1, bundleIdentifier: "com.example.Other", localizedName: "Other")

    private final class FocusRecorder {
        var windows: [NSWindow] = []
    }

    private func withController(
        _ body: (TutorialWindowController, FocusRecorder) throws -> Void
    ) throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        let recorder = FocusRecorder()
        let controller = TutorialWindowController(
            settings: settings,
            panelModel: PanelModel(),
            ownProcessIdentifier: Self.ownPid,
            focusWindow: { recorder.windows.append($0) }
        )
        defer { controller.close() }
        try body(controller, recorder)
    }

    // MARK: - 挿入先の上書き(AC-22)

    @Test("AC-22: 窓がキーでアプリがアクティブなときだけ、自分自身が挿入先になる")
    func practiceTargetRequiresKeyWindowAndActiveApp() {
        #expect(TutorialWindowController.practiceTarget(isWindowKey: true, isAppActive: true, own: own) == own)
        #expect(TutorialWindowController.practiceTarget(isWindowKey: true, isAppActive: false, own: own) == nil)
        #expect(TutorialWindowController.practiceTarget(isWindowKey: false, isAppActive: true, own: own) == nil)
        #expect(TutorialWindowController.practiceTarget(isWindowKey: false, isAppActive: false, own: own) == nil)
    }

    @Test("AC-22: 窓が無いときは挿入先を上書きしない")
    func practiceTargetIsNilWithoutWindow() throws {
        try withController { controller, _ in
            #expect(controller.practiceTarget() == nil)
        }
    }

    // MARK: - 窓を開く(AC-20)

    @Test("窓を開くと窓が見え、練習用のチャットの入力欄にフォーカスが要求される")
    func showMakesWindowVisibleAndRequestsFocus() throws {
        try withController { controller, _ in
            let before = controller.model.practiceFocusRequest
            controller.show()
            let window = try #require(controller.window)
            #expect(window.identifier?.rawValue == "tutorial")
            #expect(window.isVisible)
            #expect(controller.model.practiceFocusRequest > before)
        }
    }

    @Test("AC-20: 見えていない窓を開くと手順とチャットが元に戻り、見えている窓を開いても手順とチャットは保たれる")
    func showResetsOnlyWhenWindowIsNotVisible() throws {
        try withController { controller, _ in
            controller.show()
            controller.model.panelDidChange(isPresented: true, target: own, text: "")
            controller.model.sendPracticeMessage("hello")
            #expect(controller.model.currentStep == .writeWithNewline)
            #expect(controller.model.chat.messages.count == 3)

            controller.show()
            #expect(controller.model.currentStep == .writeWithNewline)
            #expect(controller.model.chat.messages.count == 3)

            controller.close()
            controller.show()
            #expect(controller.model.currentStep == .openPanel)
            #expect(controller.model.chat == PracticeChat())
            #expect(controller.model.practiceText.isEmpty)
        }
    }

    // MARK: - 挿入の要求(AC-14, AC-22)

    @Test("AC-22: 窓が見えているとき、自分自身への挿入の要求で窓を前に出して入力欄にフォーカスを戻す")
    func insertionRequestForOwnTargetFocusesWindow() throws {
        try withController { controller, recorder in
            controller.show()
            let window = try #require(controller.window)
            controller.model.panelDidChange(isPresented: true, target: own, text: "")
            controller.model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            #expect(controller.model.currentStep == .send)
            let focusRequests = controller.model.practiceFocusRequest

            controller.handleInsertionRequested(text: "a\nb", target: own, sendsAfterInsert: false)

            #expect(recorder.windows == [window])
            #expect(controller.model.practiceFocusRequest == focusRequests + 1)
        }
    }

    @Test("AC-14: 窓に届いた「送信もするか」が、送ったときの経路の見分けに使われる")
    func sendsAfterInsertDecidesRoute() throws {
        try withController { controller, _ in
            controller.show()
            controller.model.panelDidChange(isPresented: true, target: own, text: "")
            controller.model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            #expect(controller.model.currentStep == .send)

            controller.handleInsertionRequested(text: "a\nb", target: own, sendsAfterInsert: true)
            controller.model.sendPracticeMessage("a\nb")

            #expect(controller.model.currentStep == .nextSteps)
            #expect(controller.model.chat.messages.last?.kind == .reply(.commitAndSend))

            controller.close()
            controller.show()
            controller.model.panelDidChange(isPresented: true, target: own, text: "")
            controller.model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            #expect(controller.model.currentStep == .send)

            controller.handleInsertionRequested(text: "a\nb", target: own, sendsAfterInsert: false)
            #expect(controller.model.currentStep == .send)
            controller.model.sendPracticeMessage("a\nb")

            #expect(controller.model.currentStep == .nextSteps)
            #expect(controller.model.chat.messages.last?.kind == .reply(.commitThenReturn))
        }
    }

    @Test("AC-22: 他のアプリへの挿入の要求では、何も変わらず、その後の送信は直接の送信になる")
    func insertionRequestForOtherTargetDoesNothing() throws {
        try withController { controller, recorder in
            controller.show()
            controller.model.panelDidChange(isPresented: true, target: own, text: "")
            controller.model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            let focusRequests = controller.model.practiceFocusRequest

            controller.handleInsertionRequested(text: "a\nb", target: other, sendsAfterInsert: true)

            #expect(recorder.windows.isEmpty)
            #expect(controller.model.practiceFocusRequest == focusRequests)
            controller.model.sendPracticeMessage("a\nb")
            #expect(controller.model.currentStep == .send)
            #expect(controller.model.chat.messages.last?.kind == .reply(.direct))
        }
    }

    @Test("AC-22: 窓を閉じた後の挿入の要求では、何も変わらず、その後の送信は直接の送信になる")
    func insertionRequestAfterCloseDoesNothing() throws {
        try withController { controller, recorder in
            controller.show()
            controller.model.panelDidChange(isPresented: true, target: own, text: "")
            controller.model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            controller.close()
            let focusRequests = controller.model.practiceFocusRequest

            controller.handleInsertionRequested(text: "a\nb", target: own, sendsAfterInsert: true)

            #expect(recorder.windows.isEmpty)
            #expect(controller.model.practiceFocusRequest == focusRequests)
            controller.model.sendPracticeMessage("a\nb")
            #expect(controller.model.currentStep == .send)
            #expect(controller.model.chat.messages.last?.kind == .reply(.direct))
        }
    }
}
