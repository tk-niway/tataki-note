import Observation
import Testing
@testable import TatakiNote

@MainActor
struct PanelModelTargetPendingTests {
    private let editor = MonitorFixture.editor
    private let browser = MonitorFixture.browser

    private func pendingModel() -> PanelModel {
        let model = PanelModel()
        model.present(target: nil, pendingLookupApp: editor)
        return model
    }

    @Test("AC-6: 調べているアプリを指定して開いたときだけ、待ちの印と調べているアプリが入る")
    func pendingStartsOnlyWithLookupApp() {
        let pending = pendingModel()
        #expect(pending.isTargetPending)
        #expect(pending.pendingLookupApp == editor)
        #expect(pending.target == nil)
        #expect(pending.targetOrPendingApp == editor)

        let settled = PanelModel()
        settled.present(target: browser)
        #expect(!settled.isTargetPending)
        #expect(settled.pendingLookupApp == nil)
        #expect(settled.targetOrPendingApp == browser)

        let none = PanelModel()
        none.present(target: nil)
        #expect(!none.isTargetPending)
        #expect(none.pendingLookupApp == nil)
        #expect(none.targetOrPendingApp == nil)
    }

    @Test("AC-6: 調べの終わりで待ちの印も調べているアプリも消え、挿入先が入る")
    func finishTargetLookupClearsBoth() {
        let model = pendingModel()

        model.finishTargetLookup(editor)

        #expect(!model.isTargetPending)
        #expect(model.pendingLookupApp == nil)
        #expect(model.target == editor)
    }

    @Test("AC-6: 調べの終わりが挿入先なしでも、印と調べているアプリは消える")
    func finishTargetLookupWithNoTargetClearsBoth() {
        let model = pendingModel()

        model.finishTargetLookup(nil)

        #expect(!model.isTargetPending)
        #expect(model.pendingLookupApp == nil)
        #expect(model.target == nil)
        #expect(model.targetOrPendingApp == nil)
    }

    @Test("AC-6: 閉じているときの調べの終わりは何も書き換えない")
    func finishTargetLookupWhileDismissedDoesNothing() {
        let model = pendingModel()
        model.dismiss()

        model.finishTargetLookup(editor)

        #expect(model.target == nil)
        #expect(model.pendingLookupApp == editor)
    }

    @Test("AC-6: 挿入先の入れ替えで印も調べているアプリも消える(挿入先なしへの入れ替えを含む)")
    func updateTargetClearsBoth() {
        let toApp = pendingModel()
        toApp.updateTarget(browser)
        #expect(!toApp.isTargetPending)
        #expect(toApp.pendingLookupApp == nil)
        #expect(toApp.target == browser)

        let toNil = pendingModel()
        toNil.updateTarget(nil)
        #expect(!toNil.isTargetPending)
        #expect(toNil.pendingLookupApp == nil)
        #expect(toNil.target == nil)
    }

    @Test("AC-6: 「挿入先なし」の合図で印は消え、調べているアプリは残る")
    func signalNoTargetClearsOnlyPendingFlag() {
        let model = pendingModel()

        model.signalNoTarget()

        #expect(!model.isTargetPending)
        #expect(model.pendingLookupApp == editor)
        #expect(model.noTargetAlertCount == 1)
    }

    @Test("AC-6: 閉じると印は消え、調べているアプリは残る")
    func dismissClearsOnlyPendingFlag() {
        let model = pendingModel()

        model.dismiss()

        #expect(!model.isTargetPending)
        #expect(model.pendingLookupApp == editor)
        #expect(model.targetOrPendingApp == editor)
    }

    @Test("AC-6: 許可なしの確定で閉じるときも印は消える")
    func permissionDeniedCommitClearsPendingFlag() {
        let model = pendingModel()
        model.text = "x"

        let plan = model.prepareCommit(isAccessibilityTrusted: false)

        #expect(plan == .permissionDenied)
        #expect(!model.isPresented)
        #expect(!model.isTargetPending)
        #expect(model.pendingLookupApp == editor)
    }

    @Test("AC-6: 待ちの間の確定は挿入先なしで、閉じずに印が消える")
    func commitWhilePendingIsNoTarget() {
        let model = pendingModel()
        model.text = "x"

        let plan = model.prepareCommit(isAccessibilityTrusted: true)

        #expect(plan == .noTarget)
        #expect(model.isPresented)
        #expect(!model.isTargetPending)
    }

    @Test("AC-6: 挿入先なしで開き直すと、前の回の調べているアプリも消える")
    func reopeningWithoutLookupAppClearsPreviousLookupApp() {
        let model = pendingModel()
        model.dismiss()
        #expect(model.pendingLookupApp == editor)

        model.present(target: nil)

        #expect(model.pendingLookupApp == nil)
        #expect(!model.isTargetPending)
    }

    @Test("AC-6: 印が立っていないときの挿入先の入れ替えは、印も調べているアプリも書き換えない")
    func updateTargetWithoutPendingDoesNotWriteFlags() {
        let model = PanelModel()
        model.present(target: editor)
        var changed = false

        withObservationTracking {
            _ = model.isTargetPending
            _ = model.pendingLookupApp
        } onChange: {
            changed = true
        }
        model.updateTarget(editor)
        model.updateTarget(nil)
        model.updateTarget(nil)
        model.signalNoTarget()
        model.finishTargetLookup(nil)

        #expect(!changed)
    }
}
