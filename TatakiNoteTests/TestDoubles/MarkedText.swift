import AppKit
import Testing
@testable import TatakiNote

@MainActor
enum MarkedText {
    static func parse(_ marked: String) -> (text: String, selection: NSRange) {
        var text = ""
        var start: Int?
        var end: Int?
        for character in marked {
            switch character {
            case "|":
                start = text.utf16.count
                end = start
            case "[":
                start = text.utf16.count
            case "]":
                end = text.utf16.count
            default:
                text.append(character)
            }
        }
        let location = start ?? text.utf16.count
        return (text, NSRange(location: location, length: (end ?? location) - location))
    }

    static func render(_ text: String, selection: NSRange) -> String {
        let string = text as NSString
        guard selection.location >= 0, selection.length >= 0, NSMaxRange(selection) <= string.length else {
            return "<選択が文章の外: \(text.debugDescription) \(selection)>"
        }
        let before = string.substring(to: selection.location)
        let after = string.substring(from: NSMaxRange(selection))
        if selection.length == 0 {
            return before + "|" + after
        }
        return before + "[" + string.substring(with: selection) + "]" + after
    }

    static func applying(_ edit: LineEdit, to text: String) -> String {
        let string = text as NSString
        guard NSMaxRange(edit.range) <= string.length else {
            return "<置き換える範囲が文章の外: \(text.debugDescription) \(edit.range)>"
        }
        let replaced = string.replacingCharacters(in: edit.range, with: edit.replacement)
        return render(replaced, selection: edit.selection)
    }
}
