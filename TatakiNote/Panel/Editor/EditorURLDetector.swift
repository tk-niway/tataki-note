import Foundation

/// 入力欄の中の1つの URL。
struct EditorURL: Equatable {
    /// 文章の中の範囲(UTF-16)。
    let range: NSRange
    /// URL の全文。
    let text: String
}

/// 文章から `http://`・`https://` で始まる URL を探す。
enum EditorURLDetector {
    /// 文章の前から順に、重ならない URL を返す。
    static func urls(in text: NSString) -> [EditorURL] {
        let length = text.length
        guard length > 0 else { return [] }
        var units = [UInt16](repeating: 0, count: length)
        text.getCharacters(&units, range: NSRange(location: 0, length: length))

        var result: [EditorURL] = []
        var index = 0
        while index < length {
            guard let found = url(in: units, startingAt: index) else {
                index += 1
                continue
            }
            result.append(EditorURL(range: found.range, text: text.substring(with: found.range)))
            index = NSMaxRange(found.range)
        }
        return result
    }

    // MARK: - 1つの URL

    private static func url(in units: [UInt16], startingAt start: Int) -> EditorURL? {
        guard let schemeLength = schemeLength(in: units, at: start) else { return nil }
        if start > 0, isASCIIAlphanumeric(units[start - 1]) { return nil }

        var end = start + schemeLength
        while end < units.count, isURLCharacter(units[end]) { end += 1 }
        end = trimmedEnd(units: units, start: start, end: end)

        let hostStart = start + schemeLength
        guard hostStart < end, !isPathDelimiter(units[hostStart]) else { return nil }

        let range = NSRange(location: start, length: end - start)
        let text = String(decoding: units[start..<end], as: UTF16.self)
        return EditorURL(range: range, text: text)
    }

    private static func schemeLength(in units: [UInt16], at start: Int) -> Int? {
        let http = Array("http".utf16)
        guard start + http.count < units.count else { return nil }
        for (offset, expected) in http.enumerated() where lowercased(units[start + offset]) != expected {
            return nil
        }
        var cursor = start + http.count
        if lowercased(units[cursor]) == 0x73 { cursor += 1 }
        let separator = Array("://".utf16)
        guard cursor + separator.count <= units.count else { return nil }
        for (offset, expected) in separator.enumerated() where units[cursor + offset] != expected {
            return nil
        }
        return cursor + separator.count - start
    }

    private static func trimmedEnd(units: [UInt16], start: Int, end: Int) -> Int {
        var end = end
        while end > start {
            let last = units[end - 1]
            if trailingPunctuation.contains(last) {
                end -= 1
            } else if last == 0x29, isUnpaired(closing: last, opening: 0x28, units: units, start: start, end: end) {
                end -= 1
            } else if last == 0x5D, isUnpaired(closing: last, opening: 0x5B, units: units, start: start, end: end) {
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    private static func isUnpaired(closing: UInt16, opening: UInt16, units: [UInt16], start: Int, end: Int) -> Bool {
        var openCount = 0
        var closeCount = 0
        for unit in units[start..<end] {
            if unit == opening { openCount += 1 }
            if unit == closing { closeCount += 1 }
        }
        return closeCount > openCount
    }

    // MARK: - 文字の種類

    private static let trailingPunctuation: Set<UInt16> = Set(".,:;!?'([".utf16)

    private static let symbols: Set<UInt16> = Set("-._~:/?#[]@!$&'()*+,;=%".utf16)

    private static func lowercased(_ unit: UInt16) -> UInt16 {
        (unit >= 0x41 && unit <= 0x5A) ? unit + 0x20 : unit
    }

    private static func isASCIIAlphanumeric(_ unit: UInt16) -> Bool {
        (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
    }

    private static func isURLCharacter(_ unit: UInt16) -> Bool {
        isASCIIAlphanumeric(unit) || symbols.contains(unit)
    }

    private static func isPathDelimiter(_ unit: UInt16) -> Bool {
        unit == 0x2F || unit == 0x3F || unit == 0x23
    }
}
