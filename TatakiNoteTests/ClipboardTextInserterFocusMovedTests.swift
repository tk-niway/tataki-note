import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct ClipboardTextInserterFocusMovedTests {
    private let target = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
    private let expectedField = AXUIElementCreateApplication(9001)
    private let movedField = AXUIElementCreateApplication(9002)

    @MainActor
    private struct Rig {
        let pasteboard: NSPasteboard
        let activator: ActivatorStub
        let poster: PasteShortcutPosterStub
        let focusInspector: FocusInspectorStub
        let submitSender: SubmitKeySenderStub
        let snapshotter: RecordingSnapshotter
        let original: PasteboardSnapshot
        let inserter: ClipboardTextInserter
    }

    private func makeRig(
        state: FocusedTextInputState = .textInput,
        focusedElements: [AXUIElement?],
        isActivated: Bool = true,
        ownProcessIdentifier: pid_t = 1
    ) -> Rig {
        let pasteboard = PasteboardFixture.makePasteboard()
        PasteboardFixture.writeRichContents(to: pasteboard)
        let original = PasteboardSnapshot.capture(from: pasteboard)
        let activator = ActivatorStub(result: isActivated)
        let poster = PasteShortcutPosterStub(pasteboard: pasteboard)
        let focusInspector = FocusInspectorStub(state: state)
        focusInspector.focusedElements = focusedElements
        focusInspector.values = ["", "hello"]
        let submitSender = SubmitKeySenderStub(pasteboard: pasteboard)
        let snapshotter = RecordingSnapshotter(pasteboard: pasteboard)
        let targetProcessIdentifier = target.processIdentifier
        let inserter = ClipboardTextInserter(
            pasteboard: pasteboard,
            activator: activator,
            poster: poster,
            focusInspector: focusInspector,
            submitSender: submitSender,
            submitDelay: .zero,
            settleDelay: .zero,
            restoreDelay: .zero,
            ownProcessIdentifier: ownProcessIdentifier,
            snapshotter: snapshotter,
            frontmostApp: FrontmostApplicationStub { targetProcessIdentifier },
            confirmationTimeout: .milliseconds(200),
            confirmationPollInterval: .milliseconds(5)
        )
        return Rig(
            pasteboard: pasteboard,
            activator: activator,
            poster: poster,
            focusInspector: focusInspector,
            submitSender: submitSender,
            snapshotter: snapshotter,
            original: original,
            inserter: inserter
        )
    }

    @Test("AC-1: フォーカスのある要素が指定した入力欄と同じなら、⌘V を送って挿入し、確定+送信なら Enter も送る")
    func insertsAndSubmitsWhenFocusStays() async {
        let rig = makeRig(focusedElements: [expectedField])
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert(
            "hello",
            into: target,
            expectedField: expectedField,
            shouldSendAfterInsert: true
        )

        #expect(result == .inserted)
        #expect(rig.poster.records.count == 1)
        #expect(rig.submitSender.records.count == 1)
        #expect(PasteboardSnapshot.capture(from: rig.pasteboard) == rig.original)
    }

    @Test("AC-1: 確定+挿入では同じ要素なら Enter は送らず、⌘V だけ送る")
    func insertsWithoutSubmitWhenFocusStays() async {
        let rig = makeRig(focusedElements: [expectedField])
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert(
            "hello",
            into: target,
            expectedField: expectedField,
            shouldSendAfterInsert: false
        )

        #expect(result == .inserted)
        #expect(rig.poster.records.count == 1)
        #expect(rig.submitSender.records.isEmpty)
    }

    @Test("AC-2: フォーカスが別の入力欄へ移っていたら .focusMoved を返し、⌘V も Enter も送らず、クリップボードは元のまま")
    func skipsWhenFocusMovedToAnotherField() async {
        let rig = makeRig(state: .textInput, focusedElements: [movedField])
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert(
            "hello",
            into: target,
            expectedField: expectedField,
            shouldSendAfterInsert: true
        )

        #expect(result == .focusMoved)
        #expect(rig.poster.records.isEmpty)
        #expect(rig.submitSender.records.isEmpty)
        #expect(rig.snapshotter.restoreResults.isEmpty)
        #expect(PasteboardSnapshot.capture(from: rig.pasteboard) == rig.original)
    }

    @Test("AC-3: フォーカスのある要素が読めなくても、入力欄を指定していれば .focusMoved を返して貼らない")
    func skipsWhenFocusedElementUnreadable() async {
        let rig = makeRig(focusedElements: [nil])
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert(
            "hello",
            into: target,
            expectedField: expectedField,
            shouldSendAfterInsert: true
        )

        #expect(result == .focusMoved)
        #expect(rig.poster.records.isEmpty)
        #expect(rig.submitSender.records.isEmpty)
        #expect(PasteboardSnapshot.capture(from: rig.pasteboard) == rig.original)
    }

    @Test("AC-4: 入力欄を指定しないときはフォーカスのある要素を読まず、今までどおり挿入する")
    func doesNotReadFocusedElementWithoutExpectedField() async {
        let rig = makeRig(focusedElements: [movedField])
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert("hello", into: target, shouldSendAfterInsert: false)

        #expect(result == .inserted)
        #expect(rig.focusInspector.focusedElementReadCount == 0)
        #expect(rig.poster.records.count == 1)
    }

    @Test("AC-4: TatakiNote 自身が挿入先のときはフォーカスのある要素を読まず、今までどおり挿入する")
    func doesNotReadFocusedElementForOwnTarget() async {
        let rig = makeRig(focusedElements: [movedField], ownProcessIdentifier: target.processIdentifier)
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert(
            "hello",
            into: target,
            expectedField: expectedField,
            shouldSendAfterInsert: false
        )

        #expect(result == .inserted)
        #expect(rig.focusInspector.focusedElementReadCount == 0)
        #expect(rig.poster.records.count == 1)
    }

    @Test("AC-4: 挿入先を前面にできなかったときはフォーカスのある要素を読まず、.targetNotActivated を返す")
    func doesNotReadFocusedElementWhenNotActivated() async {
        let rig = makeRig(focusedElements: [movedField], isActivated: false)
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert(
            "hello",
            into: target,
            expectedField: expectedField,
            shouldSendAfterInsert: false
        )

        #expect(result == .targetNotActivated)
        #expect(rig.focusInspector.focusedElementReadCount == 0)
        #expect(rig.poster.records.isEmpty)
    }

    @Test("AC-15: 別の入力欄でない要素へ移っていたら .noTextInput ではなく .focusMoved を返し、入力欄の調べも呼ばない")
    func returnsFocusMovedBeforeInspectingInput() async {
        let rig = makeRig(state: .notTextInput, focusedElements: [movedField])
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert(
            "hello",
            into: target,
            expectedField: expectedField,
            shouldSendAfterInsert: true
        )

        #expect(result == .focusMoved)
        #expect(rig.focusInspector.targets.isEmpty)
        #expect(rig.poster.records.isEmpty)
        #expect(rig.submitSender.records.isEmpty)
        #expect(PasteboardSnapshot.capture(from: rig.pasteboard) == rig.original)
    }

    @Test("AC-15: 指定した入力欄と同じ要素なのに入力欄と判定できないときは、今までどおり .noTextInput")
    func returnsNoTextInputForSameElementThatIsNotTextInput() async {
        let rig = makeRig(state: .notTextInput, focusedElements: [expectedField])
        defer { rig.pasteboard.releaseGlobally() }

        let result = await rig.inserter.insert(
            "hello",
            into: target,
            expectedField: expectedField,
            shouldSendAfterInsert: true
        )

        #expect(result == .noTextInput)
        #expect(rig.focusInspector.targets.count == 1)
        #expect(rig.poster.records.isEmpty)
        #expect(rig.submitSender.records.isEmpty)
    }

    @Test("AC-2: hasFocusMoved は、入力欄が nil なら偽、同じ要素なら偽、別の要素・nil なら真")
    func hasFocusMovedTable() {
        #expect(!ClipboardTextInserter.hasFocusMoved(expectedField: nil, focusedElement: movedField))
        #expect(!ClipboardTextInserter.hasFocusMoved(expectedField: nil, focusedElement: nil))
        #expect(!ClipboardTextInserter.hasFocusMoved(expectedField: expectedField, focusedElement: expectedField))
        #expect(ClipboardTextInserter.hasFocusMoved(expectedField: expectedField, focusedElement: movedField))
        #expect(ClipboardTextInserter.hasFocusMoved(expectedField: expectedField, focusedElement: nil))
    }
}
