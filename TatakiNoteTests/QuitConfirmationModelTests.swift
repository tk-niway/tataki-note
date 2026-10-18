import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class TerminateCounter {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
struct QuitConfirmationModelTests {
    private func withModel(
        confirmsQuit: Bool = true,
        _ body: (QuitConfirmationModel, TemporaryDefaults, TerminateCounter) throws -> Void
    ) throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.confirmsQuit = confirmsQuit
        let counter = TerminateCounter()
        let model = QuitConfirmationModel(settings: settings, terminate: { counter.record() })
        try body(model, defaults, counter)
    }

    private func pressQuitKey(
        _ model: QuitConfirmationModel,
        isRecordingShortcut: Bool = false,
        isPanelCommitKey: Bool = false,
        isModalRunning: Bool = false
    ) -> QuitKeyAction {
        model.handleQuitKey(
            isRecordingShortcut: isRecordingShortcut,
            isPanelCommitKey: isPanelCommitKey,
            isModalRunning: isModalRunning
        )
    }

    private func requestTermination(
        _ model: QuitConfirmationModel,
        isQuitKeyEvent: Bool = true,
        isQuitAppleEvent: Bool = false,
        isRecordingShortcut: Bool = false,
        isPanelCommitKey: Bool = false,
        isModalRunning: Bool = false
    ) -> QuitTerminationReply {
        model.handleTerminationRequest(
            isQuitKeyEvent: isQuitKeyEvent,
            isQuitAppleEvent: isQuitAppleEvent,
            isRecordingShortcut: isRecordingShortcut,
            isPanelCommitKey: isPanelCommitKey,
            isModalRunning: isModalRunning
        )
    }

    @Test("AC-30: 終了の頼みのときのイベントが ⌘Q で確認がオンなら、終了をやめて確かめ中になり、チェックが外れ、終了の処理は呼ばない")
    func terminationRequestByQuitKeyStartsConfirming() throws {
        try withModel { model, _, counter in
            model.suppressesFuture = true

            #expect(requestTermination(model) == .cancelAndConfirm)

            #expect(model.isConfirming)
            #expect(!model.suppressesFuture)
            #expect(counter.count == 0)
        }
    }

    @Test("AC-30: 終了の頼みのときのイベントが ⌘Q でも確認がオフなら、確かめずに終了を通す(終了の処理は呼ばない)")
    func terminationRequestByQuitKeyTerminatesWhenSettingIsOff() throws {
        try withModel(confirmsQuit: false) { model, _, counter in
            #expect(requestTermination(model) == .terminate)

            #expect(!model.isConfirming)
            #expect(counter.count == 0)
        }
    }

    @Test("AC-30: 確かめ中の ⌘Q の終了の頼みは、終了をやめ、確かめ中のまま")
    func terminationRequestByQuitKeyWhileConfirmingCancels() throws {
        try withModel { model, _, counter in
            _ = requestTermination(model)
            model.suppressesFuture = true

            #expect(requestTermination(model) == .cancel)

            #expect(model.isConfirming)
            #expect(model.suppressesFuture)
            #expect(counter.count == 0)
        }
    }

    @Test("AC-30: モーダル中・記録中・パネルの確定キーの ⌘Q の終了の頼みは、終了をやめ、確かめ中にならない")
    func guardedTerminationRequestCancelsWithoutConfirming() throws {
        try withModel { model, _, counter in
            #expect(requestTermination(model, isModalRunning: true) == .cancel)
            #expect(requestTermination(model, isRecordingShortcut: true) == .cancel)
            #expect(requestTermination(model, isPanelCommitKey: true) == .cancel)

            #expect(!model.isConfirming)
            #expect(counter.count == 0)
        }
    }

    @Test("AC-30: ⌘Q でない終了の頼み(クリック・↩・イベントなし)は、確認がオンでも確かめ中でも終了を通す")
    func terminationRequestWithoutQuitKeyTerminates() throws {
        try withModel { model, _, counter in
            #expect(requestTermination(model, isQuitKeyEvent: false) == .terminate)
            #expect(!model.isConfirming)

            _ = requestTermination(model)

            #expect(requestTermination(model, isQuitKeyEvent: false) == .terminate)
            #expect(model.isConfirming)
            #expect(counter.count == 0)
        }
    }

    @Test("AC-30: 終了の Apple Event(Dock のメニュー・ログアウト)は、前の ⌘Q のイベントが残っていても確かめず終了を通す")
    func quitAppleEventTerminatesEvenWhileConfirming() throws {
        try withModel { model, _, counter in
            #expect(requestTermination(model, isQuitAppleEvent: true) == .terminate)
            #expect(!model.isConfirming)

            _ = requestTermination(model)

            #expect(requestTermination(model, isQuitAppleEvent: true) == .terminate)
            #expect(counter.count == 0)
        }
    }

    @Test("AC-30: 終了の頼みで確かめ中になったあと、「終了」で1回だけ終了し、「キャンセル」では終了しない")
    func confirmingFromTerminationRequestEndsLikeQuitKey() throws {
        try withModel { model, _, counter in
            _ = requestTermination(model)
            model.cancel()

            #expect(!model.isConfirming)
            #expect(counter.count == 0)

            _ = requestTermination(model)
            model.quit()

            #expect(counter.count == 1)
            #expect(!model.isConfirming)
        }
    }

    @Test("AC-16: 設定がオンなら ⌘Q で確かめ中になり、まだ終了しない")
    func quitKeyStartsConfirming() throws {
        try withModel { model, _, counter in
            #expect(pressQuitKey(model) == .confirm)

            #expect(model.isConfirming)
            #expect(counter.count == 0)
        }
    }

    @Test("AC-16: 設定がオフなら ⌘Q で確かめずに1回だけ終了する")
    func quitKeyQuitsWhenSettingIsOff() throws {
        try withModel(confirmsQuit: false) { model, _, counter in
            #expect(pressQuitKey(model) == .quit)

            #expect(!model.isConfirming)
            #expect(counter.count == 1)
        }
    }

    @Test("AC-16: 「終了」を選ぶと1回だけ終了し、確かめ中が解ける")
    func quitTerminatesOnce() throws {
        try withModel { model, _, counter in
            _ = pressQuitKey(model)
            model.quit()

            #expect(counter.count == 1)
            #expect(!model.isConfirming)

            model.quit()

            #expect(counter.count == 1)
        }
    }

    @Test("AC-16: 「キャンセル」では終了せず、確かめ中が解ける")
    func cancelDoesNotTerminate() throws {
        try withModel { model, _, counter in
            _ = pressQuitKey(model)
            model.cancel()

            #expect(counter.count == 0)
            #expect(!model.isConfirming)
        }
    }

    @Test("AC-16: 確かめ中でなければ、「終了」を呼んでも終了しない")
    func quitWithoutConfirmingDoesNothing() throws {
        try withModel { model, _, counter in
            model.suppressesFuture = true
            model.quit()

            #expect(counter.count == 0)
        }
    }

    @Test("AC-16: 「今後は確かめない」をチェックして「終了」を選ぶと、確かめの設定がオフになって保存される")
    func suppressAndQuitTurnsOffConfirmation() throws {
        try withModel { model, defaults, counter in
            _ = pressQuitKey(model)
            model.suppressesFuture = true
            model.quit()

            #expect(counter.count == 1)
            #expect(!defaults.makeSettings().confirmsQuit)
        }
    }

    @Test("AC-16: チェックせずに「終了」を選んでも、確かめの設定はオンのまま")
    func quitWithoutCheckKeepsConfirmation() throws {
        try withModel { model, defaults, _ in
            _ = pressQuitKey(model)
            model.quit()

            #expect(defaults.makeSettings().confirmsQuit)
        }
    }

    @Test("AC-16: 「今後は確かめない」をチェックして「キャンセル」を選んでも、設定は変わらない")
    func suppressAndCancelKeepsConfirmation() throws {
        try withModel { model, defaults, counter in
            _ = pressQuitKey(model)
            model.suppressesFuture = true
            model.cancel()

            #expect(counter.count == 0)
            #expect(defaults.makeSettings().confirmsQuit)
        }
    }

    @Test("AC-16: 次に確かめるときは、前のチェックが外れている")
    func checkIsClearedWhenConfirmingAgain() throws {
        try withModel { model, _, _ in
            _ = pressQuitKey(model)
            model.suppressesFuture = true
            model.cancel()

            #expect(!model.suppressesFuture)

            _ = pressQuitKey(model)
            model.suppressesFuture = true
            model.cancel()
            _ = pressQuitKey(model)

            #expect(!model.suppressesFuture)
        }
    }

    @Test("AC-16: 確かめ中の ⌘Q は捨てて、終了も確かめ直しもしない")
    func quitKeyWhileConfirmingIsIgnored() throws {
        try withModel { model, _, counter in
            _ = pressQuitKey(model)
            model.suppressesFuture = true

            #expect(pressQuitKey(model) == .ignore)

            #expect(model.isConfirming)
            #expect(model.suppressesFuture)
            #expect(counter.count == 0)
        }
    }

    @Test("AC-16: 記録中・パネルの確定キー・モーダル中の ⌘Q では、確かめ中にならず終了もしない")
    func passThroughAndIgnoredKeysDoNothing() throws {
        try withModel { model, _, counter in
            #expect(pressQuitKey(model, isRecordingShortcut: true) == .passThrough)
            #expect(pressQuitKey(model, isPanelCommitKey: true) == .passThrough)
            #expect(pressQuitKey(model, isModalRunning: true) == .ignore)

            #expect(!model.isConfirming)
            #expect(counter.count == 0)
        }
        try withModel(confirmsQuit: false) { model, _, counter in
            #expect(pressQuitKey(model, isRecordingShortcut: true) == .passThrough)
            #expect(pressQuitKey(model, isPanelCommitKey: true) == .passThrough)
            #expect(pressQuitKey(model, isModalRunning: true) == .ignore)

            #expect(counter.count == 0)
        }
    }
}
