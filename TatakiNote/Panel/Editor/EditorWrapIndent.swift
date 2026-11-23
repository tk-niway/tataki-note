import CoreGraphics
import Foundation

/// 折り返した行の字下げの判定。
enum EditorWrapIndent {
    private static let maxDigits = 9

    /// 段落の先頭の、字下げに揃える部分(行頭の空白・タブと、箇条書きの記号とその後ろの空白)の UTF-16 の長さ。
    static func hangingPrefixLength(of paragraph: NSString) -> Int {
        let length = paragraph.length
        let indentEnd = skipSpaces(in: paragraph, from: 0)
        guard indentEnd < length else { return indentEnd }

        switch paragraph.character(at: indentEnd) {
        case Character("-").utf16Unit, Character("*").utf16Unit, Character("+").utf16Unit:
            let end = skipSpaces(in: paragraph, from: indentEnd + 1)
            return end > indentEnd + 1 ? end : indentEnd
        case Character("・").utf16Unit:
            return skipSpaces(in: paragraph, from: indentEnd + 1)
        default:
            return numberedMarkerEnd(in: paragraph, from: indentEnd) ?? indentEnd
        }
    }

    /// 字下げの幅。接頭辞が無ければ 0。1行の幅の半分を超えない。
    static func headIndent(prefixWidth: CGFloat, lineWidth: CGFloat) -> CGFloat {
        guard prefixWidth > 0, lineWidth > 0 else { return 0 }
        return min(prefixWidth, lineWidth / 2)
    }

    private static func isSpace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x3000
    }

    private static func skipSpaces(in paragraph: NSString, from start: Int) -> Int {
        var index = start
        while index < paragraph.length, isSpace(paragraph.character(at: index)) {
            index += 1
        }
        return index
    }

    private static func numberedMarkerEnd(in paragraph: NSString, from start: Int) -> Int? {
        var index = start
        while index < paragraph.length, isDigit(paragraph.character(at: index)) {
            index += 1
        }
        let digits = index - start
        guard (1...maxDigits).contains(digits), index < paragraph.length else { return nil }
        let separator = paragraph.character(at: index)
        guard separator == Character(".").utf16Unit || separator == Character(")").utf16Unit else { return nil }
        let end = skipSpaces(in: paragraph, from: index + 1)
        return end > index + 1 ? end : nil
    }

    private static func isDigit(_ unit: unichar) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }
}

private extension Character {
    var utf16Unit: unichar { utf16.first ?? 0 }
}
