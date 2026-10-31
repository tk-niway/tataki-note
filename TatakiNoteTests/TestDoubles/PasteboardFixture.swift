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
