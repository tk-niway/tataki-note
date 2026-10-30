import AppKit
import Testing
@testable import TatakiNote

final class NonProvidingDataProvider: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {}
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
