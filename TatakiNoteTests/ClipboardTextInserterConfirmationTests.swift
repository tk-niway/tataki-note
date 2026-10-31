import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct ClipboardTextInserterConfirmationTests {
    private let target = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
    private let shortTimeout: Duration = .milliseconds(200)
    private let longTimeout: Duration = .seconds(60)

    private func makeInserter(
        pasteboard: NSPasteboard,
        poster: PasteShortcutPosterStub,
        focusInspector: FocusInspectorStub,
        submitSender: SubmitKeySenderStub,
        snapshotter: PasteboardSnapshotting,
        submitDelay: Duration,
        ownProcessIdentifier: pid_t,
        confirmationTimeout: Duration
    ) -> ClipboardTextInserter {
        let targetProcessIdentifier = target.processIdentifier
        return ClipboardTextInserter(
            pasteboard: pasteboard,
            activator: ActivatorStub(result: true),
            poster: poster,
            focusInspector: focusInspector,
            submitSender: submitSender,
            submitDelay: submitDelay,
            settleDelay: .zero,
            restoreDelay: .zero,
            ownProcessIdentifier: ownProcessIdentifier,
            snapshotter: snapshotter,
            frontmostApp: FrontmostApplicationStub { targetProcessIdentifier },
            confirmationTimeout: confirmationTimeout,
            confirmationPollInterval: .milliseconds(5)
        )
    }

    @MainActor
    private struct Rig {
        let pasteboard: NSPasteboard
        let log: InsertionEventLog
        let poster: PasteShortcutPosterStub
        let focusInspector: FocusInspectorStub
        let submitSender: SubmitKeySenderStub
        let snapshotter: RecordingSnapshotter
        let original: PasteboardSnapshot
        let inserter: ClipboardTextInserter

        var orderedEvents: [String] {
            log.events.filter { ["read", "paste", "enter", "restore"].contains($0) }
        }
    }

    private func makeRig(
        values: [String?],
        state: FocusedTextInputState = .textInput,
        isSecureTextField: Bool = false,
        submitDelay: Duration = .zero,
        ownProcessIdentifier: pid_t = 1,
        confirmationTimeout: Duration? = nil
    ) -> Rig {
        let pasteboard = PasteboardFixture.makePasteboard()
        PasteboardFixture.writeRichContents(to: pasteboard)
        let original = PasteboardSnapshot.capture(from: pasteboard)
        let log = InsertionEventLog()
        let poster = PasteShortcutPosterStub(pasteboard: pasteboard)
        poster.onPost = { log.add("paste") }
        let focusInspector = FocusInspectorStub(state: state, isSecureTextField: isSecureTextField)
        focusInspector.values = values
        focusInspector.onReadValue = { log.add("read") }
        let submitSender = SubmitKeySenderStub(pasteboard: pasteboard)
        submitSender.onSend = { log.add("enter") }
        let snapshotter = RecordingSnapshotter(pasteboard: pasteboard, log: log)
        let inserter = makeInserter(
            pasteboard: pasteboard,
            poster: poster,
            focusInspector: focusInspector,
            submitSender: submitSender,
            snapshotter: snapshotter,
            submitDelay: submitDelay,
            ownProcessIdentifier: ownProcessIdentifier,
            confirmationTimeout: confirmationTimeout ?? longTimeout
        )
        return Rig(
            pasteboard: pasteboard,
            log: log,
            poster: poster,
            focusInspector: focusInspector,
            submitSender: submitSender,
            snapshotter: snapshotter,
            original: original,
            inserter: inserter
        )
    }

    @Test("AC-2: 文章が入ったのを確かめてから Enter を1回送り、その後にクリップボードを元に戻す")
    func sendsEnterAfterConfirmationThenRestores() async {
        let rig = makeRig(values: ["", "", "hello"])
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert("hello", into: target, shouldSendAfterInsert: true)

        #expect(result == .inserted)
        #expect(rig.submitSender.records.count == 1)
        #expect(rig.orderedEvents == ["read", "paste", "read", "read", "enter", "restore"])
        #expect(PasteboardSnapshot.capture(from: rig.pasteboard) == rig.original)
    }

    @Test("AC-2: 確定+挿入では確かめた後も Enter を送らず、クリップボードを元に戻す")
    func doesNotSendEnterWhenOnlyInserting() async {
        let rig = makeRig(values: ["", "hello"])
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert("hello", into: target, shouldSendAfterInsert: false)

        #expect(result == .inserted)
        #expect(rig.submitSender.records.isEmpty)
        #expect(rig.orderedEvents == ["read", "paste", "read", "restore"])
        #expect(PasteboardSnapshot.capture(from: rig.pasteboard) == rig.original)
    }

    @Test("AC-3: 中身が変わらない・前にコピーしていた内容が入った・読み直せないときは、Enter を送らず元に戻して確かめられなかった結果にする")
    func reportsPasteNotConfirmedWithoutEnter() async {
        let cases: [[String?]] = [
            ["", ""],
            ["", "previously copied"],
            ["", nil],
        ]
        for values in cases {
            for shouldSendAfterInsert in [true, false] {
                let rig = makeRig(values: values, confirmationTimeout: shortTimeout)
                defer { rig.pasteboard.releaseGlobally() }

                let result = await rig.inserter.insert(
                    "hello",
                    into: target,
                    shouldSendAfterInsert: shouldSendAfterInsert
                )

                #expect(result == .pasteNotConfirmed)
                #expect(rig.submitSender.records.isEmpty)
                #expect(rig.snapshotter.restoreResults == [true])
                #expect(PasteboardSnapshot.capture(from: rig.pasteboard) == rig.original)
            }
        }
    }

    @Test("AC-4: 待つ時間の上限の既定は1秒")
    func defaultConfirmationTimeoutIsOneSecond() {
        #expect(ClipboardTextInserter.defaultConfirmationTimeout == .seconds(1))
    }

    @Test("AC-4: 確かめるまでクリップボードを戻さず、確かめられなければ上限まで待ってから戻す")
    func restoresOnlyAfterConfirmationOrTimeout() async {
        let delayed = makeRig(values: ["", "", "", "", "hello"])
        defer { delayed.pasteboard.releaseGlobally() }

        let delayedResult = await delayed.inserter.insert("hello", into: target, shouldSendAfterInsert: true)

        #expect(delayedResult == .inserted)
        let events = delayed.orderedEvents
        #expect(events.filter { $0 == "read" }.count == 5)
        #expect(events.last == "restore")
        #expect(events.firstIndex(of: "restore") == events.count - 1)
        #expect(events.firstIndex(of: "enter") == events.count - 2)

        let missed = makeRig(values: ["", ""], confirmationTimeout: shortTimeout)
        defer { missed.pasteboard.releaseGlobally() }
        var pastedAt: ContinuousClock.Instant?
        missed.poster.onPost = {
            missed.log.add("paste")
            pastedAt = ContinuousClock.now
        }

        let missedResult = await missed.inserter.insert("hello", into: target, shouldSendAfterInsert: true)
        let finishedAt = ContinuousClock.now

        #expect(missedResult == .pasteNotConfirmed)
        #expect(pastedAt.map { finishedAt - $0 >= shortTimeout } == true)
    }

    @Test("AC-4: すぐ確かめられても、Enter は ⌘V から決めた間隔より前には送らない")
    func waitsForSubmitDelayBeforeEnter() async {
        let submitDelay: Duration = .milliseconds(80)
        let rig = makeRig(values: ["", "hello"], submitDelay: submitDelay)
        defer { rig.pasteboard.releaseGlobally() }
        var pastedAt: ContinuousClock.Instant?
        var enterAt: ContinuousClock.Instant?
        rig.poster.onPost = {
            rig.log.add("paste")
            pastedAt = ContinuousClock.now
        }
        rig.submitSender.onSend = {
            rig.log.add("enter")
            enterAt = ContinuousClock.now
        }

        let result = await rig.inserter.insert("hello", into: target, shouldSendAfterInsert: true)

        #expect(result == .inserted)
        if let pastedAt, let enterAt {
            #expect(enterAt - pastedAt >= submitDelay)
        } else {
            Issue.record("⌘V か Enter が記録されていない")
        }
    }

    @Test("AC-5: 確かめる対象かの表")
    func shouldConfirmPasteTable() {
        let textInput = FocusedInputInspection(state: .textInput, isSecureTextField: false)
        let secure = FocusedInputInspection(state: .textInput, isSecureTextField: true)
        let notTextInput = FocusedInputInspection(state: .notTextInput, isSecureTextField: false)

        #expect(ClipboardTextInserter.shouldConfirmPaste(isOwnTarget: false, inspection: textInput))
        #expect(!ClipboardTextInserter.shouldConfirmPaste(isOwnTarget: true, inspection: nil))
        #expect(!ClipboardTextInserter.shouldConfirmPaste(isOwnTarget: true, inspection: textInput))
        #expect(!ClipboardTextInserter.shouldConfirmPaste(isOwnTarget: false, inspection: secure))
        #expect(!ClipboardTextInserter.shouldConfirmPaste(isOwnTarget: false, inspection: notTextInput))
        #expect(!ClipboardTextInserter.shouldConfirmPaste(isOwnTarget: false, inspection: nil))
    }

    @Test("AC-5: 入力欄の中身が読めなければ、確かめず今と同じ順序で挿入する")
    func insertsWithoutConfirmationWhenValueIsUnreadable() async {
        let rig = makeRig(values: [])
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert("hello", into: target, shouldSendAfterInsert: true)

        #expect(result == .inserted)
        #expect(rig.focusInspector.valueReadCount == 1)
        #expect(rig.orderedEvents == ["read", "paste", "enter", "restore"])
        #expect(PasteboardSnapshot.capture(from: rig.pasteboard) == rig.original)
    }

    @Test("AC-5: パスワード欄では中身を読まず、今と同じ順序で挿入して専用の結果にする")
    func insertsWithoutReadingSecureField() async {
        let rig = makeRig(values: ["", "hello"], isSecureTextField: true)
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert("hello", into: target, shouldSendAfterInsert: true)

        #expect(result == .insertedIntoSecureField)
        #expect(rig.focusInspector.valueReadCount == 0)
        #expect(rig.orderedEvents == ["paste", "enter", "restore"])
        #expect(PasteboardSnapshot.capture(from: rig.pasteboard) == rig.original)
    }

    @Test("AC-5: TatakiNote 自身へは入力欄を調べず中身も読まず、今と同じ順序で挿入する")
    func insertsWithoutReadingOwnApp() async {
        let rig = makeRig(values: ["", "hello"], ownProcessIdentifier: target.processIdentifier)
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert("hello", into: target, shouldSendAfterInsert: true)

        #expect(result == .inserted)
        #expect(rig.focusInspector.targets.isEmpty)
        #expect(rig.focusInspector.valueReadCount == 0)
        #expect(rig.orderedEvents == ["paste", "enter", "restore"])
    }

    @Test("AC-5: 空白と改行だけの文章は確かめず、今と同じ順序で挿入する")
    func insertsWithoutConfirmationForWhitespaceOnlyText() async {
        let rig = makeRig(values: ["existing", "existing"])
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert(" \n\t", into: target, shouldSendAfterInsert: true)

        #expect(result == .inserted)
        #expect(rig.focusInspector.valueReadCount == 1)
        #expect(rig.orderedEvents == ["read", "paste", "enter", "restore"])
        #expect(PasteboardSnapshot.capture(from: rig.pasteboard) == rig.original)
    }

    @Test("AC-7: 確かめている間に他のアプリがコピーした内容を、確かめられた後も元の内容で上書きしない")
    func keepsForeignCopyWhenConfirmed() async {
        let rig = makeRig(values: ["", "", "hello"])
        defer { rig.pasteboard.releaseGlobally() }
        let pasteboard = rig.pasteboard
        let focusInspector = rig.focusInspector
        rig.focusInspector.onReadValue = {
            rig.log.add("read")
            if focusInspector.valueReadCount == 2 {
                pasteboard.clearContents()
                pasteboard.setString("copied by someone else", forType: .string)
            }
        }

        let result = await rig.inserter.insert("hello", into: target, shouldSendAfterInsert: true)

        #expect(result == .inserted)
        #expect(rig.snapshotter.restoreResults == [false])
        #expect(rig.pasteboard.string(forType: .string) == "copied by someone else")
    }

    @Test("AC-7: 確かめている間に他のアプリがコピーした内容を、確かめられなかった後も元の内容で上書きしない")
    func keepsForeignCopyWhenNotConfirmed() async {
        let rig = makeRig(values: ["", ""], confirmationTimeout: shortTimeout)
        defer { rig.pasteboard.releaseGlobally() }
        let pasteboard = rig.pasteboard
        let focusInspector = rig.focusInspector
        rig.focusInspector.onReadValue = {
            rig.log.add("read")
            if focusInspector.valueReadCount == 2 {
                pasteboard.clearContents()
                pasteboard.setString("copied by someone else", forType: .string)
            }
        }

        let result = await rig.inserter.insert("hello", into: target, shouldSendAfterInsert: true)

        #expect(result == .pasteNotConfirmed)
        #expect(rig.snapshotter.restoreResults == [false])
        #expect(rig.pasteboard.string(forType: .string) == "copied by someone else")
    }

    @Test("AC-8: 確かめる挿入の途中で次の確定が来ても、前の挿入が戻し終えてから次が始まり、最後に元の内容へ戻る")
    func queuesNextInsertionUntilPreviousRestores() async {
        let rig = makeRig(values: ["", "", "first", "first", "firstsecond"])
        defer { rig.pasteboard.releaseGlobally() }
        let inserter = rig.inserter
        let target = target

        let first = Task { await inserter.insert("first", into: target, shouldSendAfterInsert: true) }
        let second = Task { await inserter.insert("second", into: target, shouldSendAfterInsert: true) }
        let firstResult = await first.value
        let secondResult = await second.value

        #expect(firstResult == .inserted)
        #expect(secondResult == .inserted)
        let events = rig.orderedEvents
        #expect(events.filter { $0 == "paste" }.count == 2)
        if let firstRestore = events.firstIndex(of: "restore"), let secondPaste = events.lastIndex(of: "paste") {
            #expect(firstRestore < secondPaste)
        } else {
            Issue.record("restore か paste が記録されていない")
        }
        #expect(events.last == "restore")
        #expect(rig.snapshotter.restoreResults == [true, true])
        #expect(PasteboardSnapshot.capture(from: rig.pasteboard) == rig.original)
    }
}
