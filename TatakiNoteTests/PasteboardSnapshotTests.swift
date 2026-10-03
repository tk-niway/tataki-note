import AppKit
import Testing
@testable import TatakiNote

@MainActor
enum PasteboardFixture {
    static let customType = NSPasteboard.PasteboardType("jp.co.woube.TatakiNoteTests.custom")

    static func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("TatakiNoteTests.\(UUID().uuidString)"))
    }

    static func writeRichContents(to pasteboard: NSPasteboard) {
        let first = NSPasteboardItem()
        first.setString("original", forType: .string)
        first.setData(Data("{\\rtf1 hello}".utf8), forType: .rtf)
        first.setData(Data([0x01, 0x02, 0x03, 0xFF]), forType: customType)
        let second = NSPasteboardItem()
        second.setData(Data([0x89, 0x50, 0x4E, 0x47, 0x00]), forType: .png)
        second.setString("second item", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])
    }

    static func writeOtherContents(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString("other", forType: .string)
    }
}

final class NonProvidingDataProvider: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {}
}

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

@MainActor
struct PasteboardSnapshotTests {
    @Test("AC-12: 複数の項目と全てのデータ型(独自の型を含む)ごと退避し、元どおりに戻す")
    func roundTripsAllItemsAndTypes() {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        PasteboardFixture.writeRichContents(to: pasteboard)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        #expect(snapshot.items.count == 2)
        #expect(snapshot.items.first?.contains { $0.type == PasteboardFixture.customType } == true)
        #expect(snapshot.items.first?.contains { $0.type == .rtf } == true)
        #expect(snapshot.items.last?.contains { $0.type == .png } == true)

        PasteboardFixture.writeOtherContents(to: pasteboard)
        #expect(PasteboardSnapshot.capture(from: pasteboard) != snapshot)

        snapshot.restore(to: pasteboard)
        #expect(PasteboardSnapshot.capture(from: pasteboard) == snapshot)
    }

    @Test("AC-12: 元が空なら、空に戻る")
    func roundTripsEmptyPasteboard() {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        #expect(snapshot.items.isEmpty)

        PasteboardFixture.writeOtherContents(to: pasteboard)
        snapshot.restore(to: pasteboard)

        #expect(PasteboardSnapshot.capture(from: pasteboard).items.isEmpty)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test("AC-12: 遅延提供で取り出せない型は含めず(全ての型が取り出せない項目は項目ごと含めず)、残りの型は戻る")
    func skipsTypesThatCannotBeRead() {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let provider = NonProvidingDataProvider()

        let first = NSPasteboardItem()
        first.setString("kept", forType: .string)
        first.setDataProvider(provider, forTypes: [PasteboardFixture.customType])
        let second = NSPasteboardItem()
        second.setDataProvider(provider, forTypes: [PasteboardFixture.customType])
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        #expect(snapshot.items.count == 1)
        #expect(snapshot.items.first?.map(\.type) == [.string])
        #expect(snapshot.items.first?.first?.data == Data("kept".utf8))

        PasteboardFixture.writeOtherContents(to: pasteboard)
        snapshot.restore(to: pasteboard)

        #expect(PasteboardSnapshot.capture(from: pasteboard) == snapshot)
        #expect(pasteboard.string(forType: .string) == "kept")
        withExtendedLifetime(provider) {}
    }
}
