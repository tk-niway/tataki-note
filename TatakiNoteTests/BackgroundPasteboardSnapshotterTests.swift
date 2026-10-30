import AppKit
import Testing
@testable import TatakiNote

final class ThreadRecordingPasteboard: PasteboardAccessing, @unchecked Sendable {
    struct Call: Equatable {
        var name: String
        var isMainThread: Bool
    }

    private let base: NSPasteboard
    private let lock = NSLock()
    private var recordedCalls: [Call] = []

    init(base: NSPasteboard) {
        self.base = base
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    private func record(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append(Call(name: name, isMainThread: Thread.isMainThread))
    }

    var changeCount: Int {
        record("changeCount")
        return base.changeCount
    }

    var pasteboardItems: [NSPasteboardItem]? {
        record("pasteboardItems")
        return base.pasteboardItems
    }

    @discardableResult
    func clearContents() -> Int {
        record("clearContents")
        return base.clearContents()
    }

    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        record("writeObjects")
        return base.writeObjects(objects)
    }
}

@MainActor
struct BackgroundPasteboardSnapshotterTests {
    @Test("AC-1: 複数の項目と全てのデータ型(独自の型を含む)を写し取り、写し取る直前の変更回数を返し、書き戻すと元どおりになる")
    func capturesAllItemsAndTypesWithChangeCount() async {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        PasteboardFixture.writeRichContents(to: pasteboard)
        let changeCountBeforeCapture = pasteboard.changeCount
        let expected = PasteboardSnapshot.capture(from: pasteboard)
        let snapshotter = BackgroundPasteboardSnapshotter(pasteboard: pasteboard)

        let captured = await snapshotter.capture()

        #expect(captured.snapshot == expected)
        #expect(captured.snapshot.items.count == 2)
        #expect(captured.snapshot.items.first?.contains { $0.type == PasteboardFixture.customType } == true)
        #expect(captured.snapshot.items.first?.contains { $0.type == .rtf } == true)
        #expect(captured.snapshot.items.last?.contains { $0.type == .png } == true)
        #expect(captured.changeCount == changeCountBeforeCapture)

        PasteboardFixture.writeOtherContents(to: pasteboard)
        #expect(PasteboardSnapshot.capture(from: pasteboard) != captured.snapshot)

        let didRestore = await snapshotter.restore(captured.snapshot, ifChangeCountIs: pasteboard.changeCount)

        #expect(didRestore)
        #expect(PasteboardSnapshot.capture(from: pasteboard) == captured.snapshot)
    }

    @Test("AC-1: 空のクリップボードを写し取って書き戻すと、空に戻る")
    func capturesAndRestoresEmptyPasteboard() async {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let changeCountBeforeCapture = pasteboard.changeCount
        let snapshotter = BackgroundPasteboardSnapshotter(pasteboard: pasteboard)

        let captured = await snapshotter.capture()

        #expect(captured.snapshot.items.isEmpty)
        #expect(captured.changeCount == changeCountBeforeCapture)

        PasteboardFixture.writeOtherContents(to: pasteboard)
        let didRestore = await snapshotter.restore(captured.snapshot, ifChangeCountIs: pasteboard.changeCount)

        #expect(didRestore)
        #expect(PasteboardSnapshot.capture(from: pasteboard).items.isEmpty)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test("AC-2: 写し取りと書き戻しのクリップボードの読み書きは、メインスレッドの外で行われる")
    func accessesPasteboardOffTheMainThread() async {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        PasteboardFixture.writeRichContents(to: pasteboard)
        let recording = ThreadRecordingPasteboard(base: pasteboard)
        let snapshotter = BackgroundPasteboardSnapshotter(pasteboard: recording)

        #expect(Thread.isMainThread)
        let captured = await snapshotter.capture()
        let captureCalls = recording.calls
        PasteboardFixture.writeOtherContents(to: pasteboard)
        let didRestore = await snapshotter.restore(captured.snapshot, ifChangeCountIs: pasteboard.changeCount)
        let allCalls = recording.calls

        #expect(didRestore)
        #expect(captureCalls.map(\.name).contains("changeCount"))
        #expect(captureCalls.map(\.name).contains("pasteboardItems"))
        #expect(allCalls.map(\.name).contains("clearContents"))
        #expect(allCalls.map(\.name).contains("writeObjects"))
        #expect(allCalls.allSatisfy { !$0.isMainThread })
    }

    @Test("AC-3: 変更回数が渡した値のままなら元の内容に戻して true を返し、他のコピーで変わっていれば何もせず false を返す")
    func restoresOnlyWhenChangeCountIsUnchanged() async {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        PasteboardFixture.writeRichContents(to: pasteboard)
        let snapshotter = BackgroundPasteboardSnapshotter(pasteboard: pasteboard)
        let captured = await snapshotter.capture()

        PasteboardFixture.writeOtherContents(to: pasteboard)
        let otherContents = PasteboardSnapshot.capture(from: pasteboard)
        let changeCountAfterOtherCopy = pasteboard.changeCount

        let didRestoreStale = await snapshotter.restore(captured.snapshot, ifChangeCountIs: captured.changeCount)

        #expect(!didRestoreStale)
        #expect(pasteboard.changeCount == changeCountAfterOtherCopy)
        #expect(PasteboardSnapshot.capture(from: pasteboard) == otherContents)
        #expect(pasteboard.string(forType: .string) == "other")

        let didRestoreCurrent = await snapshotter.restore(captured.snapshot, ifChangeCountIs: changeCountAfterOtherCopy)

        #expect(didRestoreCurrent)
        #expect(PasteboardSnapshot.capture(from: pasteboard) == captured.snapshot)
    }
}
