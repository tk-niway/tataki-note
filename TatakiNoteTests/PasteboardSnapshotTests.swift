import AppKit
import Testing
@testable import TatakiNote

/// @note p0-1021
@MainActor
enum PasteboardFixture {
    static let customType = NSPasteboard.PasteboardType("jp.co.woube.TatakiNoteTests.custom")

    /// @note p0-1022
    static func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("TatakiNoteTests.\(UUID().uuidString)"))
    }

    /// @note p0-1023
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

/// @note p0-1024
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
