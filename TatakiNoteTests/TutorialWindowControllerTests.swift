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

    // MARK: - AC-11

    @Test("AC-11: 窓がキーでアプリがアクティブなときだけ、自分自身が挿入先になる")
    func practiceTargetRequiresKeyWindowAndActiveApp() {
        #expect(TutorialWindowController.practiceTarget(isWindowKey: true, isAppActive: true, own: own) == own)
        #expect(TutorialWindowController.practiceTarget(isWindowKey: true, isAppActive: false, own: own) == nil)
        #expect(TutorialWindowController.practiceTarget(isWindowKey: false, isAppActive: true, own: own) == nil)
        #expect(TutorialWindowController.practiceTarget(isWindowKey: false, isAppActive: false, own: own) == nil)
    }

    @Test("AC-11: 窓が無いときは挿入先を上書きしない")
    func practiceTargetIsNilWithoutWindow() throws {
        try withController { controller, _ in
            #expect(controller.practiceTarget() == nil)
        }
    }

    // MARK: - AC-25

    @Test("AC-25: 窓を開くと窓が見え、練習用の入力欄にフォーカスが要求される")
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

    @Test("AC-25: 見えていない窓を開くと手順がリセットされ、見えている窓を開いても手順は保たれる")
    func showResetsOnlyWhenWindowIsNotVisible() throws {
        try withController { controller, _ in
            controller.show()
            controller.model.panelDidChange(isPresented: true, target: own, text: "")
            #expect(controller.model.currentStep == .writeWithNewline)

            controller.show()
            #expect(controller.model.currentStep == .writeWithNewline)

            controller.close()
            controller.show()
            #expect(controller.model.currentStep == .openPanel)
        }
    }

    @Test("AC-25: 窓が見えているとき、自分自身への挿入の要求で窓を前に出して入力欄にフォーカスを戻す")
    func insertionRequestForOwnTargetFocusesWindow() throws {
        try withController { controller, recorder in
            controller.show()
            let window = try #require(controller.window)
            controller.model.panelDidChange(isPresented: true, target: own, text: "")
            controller.model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            #expect(controller.model.currentStep == .insert)
            let focusRequests = controller.model.practiceFocusRequest

            controller.handleInsertionRequested(text: "a\nb", target: own)

            #expect(recorder.windows == [window])
            #expect(controller.model.practiceFocusRequest == focusRequests + 1)
            controller.model.practiceText = "a\nb"
            #expect(controller.model.currentStep == .nextSteps)
        }
    }

    @Test("AC-25: 他のアプリへの挿入の要求では、何も変わらない")
    func insertionRequestForOtherTargetDoesNothing() throws {
        try withController { controller, recorder in
            controller.show()
            controller.model.panelDidChange(isPresented: true, target: own, text: "")
            controller.model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            let focusRequests = controller.model.practiceFocusRequest

            controller.handleInsertionRequested(text: "a\nb", target: other)

            #expect(recorder.windows.isEmpty)
            #expect(controller.model.practiceFocusRequest == focusRequests)
            controller.model.practiceText = "a\nb"
            #expect(controller.model.currentStep == .insert)
        }
    }

    @Test("AC-25: 窓を閉じた後の挿入の要求では、何も変わらない")
    func insertionRequestAfterCloseDoesNothing() throws {
        try withController { controller, recorder in
            controller.show()
            controller.model.panelDidChange(isPresented: true, target: own, text: "")
            controller.model.panelDidChange(isPresented: true, target: own, text: "a\nb")
            controller.close()
            let focusRequests = controller.model.practiceFocusRequest

            controller.handleInsertionRequested(text: "a\nb", target: own)

            #expect(recorder.windows.isEmpty)
            #expect(controller.model.practiceFocusRequest == focusRequests)
            controller.model.practiceText = "a\nb"
            #expect(controller.model.currentStep == .insert)
        }
    }
}
