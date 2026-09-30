import AppKit

extension KeyCode {
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
}

enum LineDirection: Equatable {
    case up
    case down
}

/// @note p0-286
enum LineArrowCommand: Equatable {
    case moveLines(LineDirection)
    case duplicateLines(LineDirection)
}

/// @note p0-287
struct LineEdit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange
}

/// @note p0-288
struct LineCut: Equatable {
    var copiedText: String
    var edit: LineEdit?
}

/// @note p0-289
enum LineEditing {
    /// @note p0-290
    static let fullLinePasteboardType = NSPasteboard.PasteboardType("jp.co.woube.TatakiNote.full-line")

    /// @note p0-291
    static func arrowCommand(for input: PanelKeyInput) -> LineArrowCommand? {
        guard !input.hasMarkedText else { return nil }
        let direction: LineDirection
        switch input.keyCode {
        case KeyCode.upArrow: direction = .up
        case KeyCode.downArrow: direction = .down
        default: return nil
        }
        // @note p0-292
        let modifiers = input.modifiers.intersection([.shift, .control, .option, .command])
        if modifiers == [.option] {
            return .moveLines(direction)
        }
        if modifiers == [.option, .shift] {
            return .duplicateLines(direction)
        }
        return nil
    }

    /// @note p0-293
    static func clamped(_ range: NSRange, toLength length: Int) -> NSRange {
        let location = min(range.location, length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    /// @note p0-294
    static func coveredLines(in text: String, selection: NSRange) -> NSRange {
        let string = text as NSString
        let selection = clamped(selection, toLength: string.length)
        let start = string.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let selectionEnd = NSMaxRange(selection)
        let end: Int
        if selection.length > 0 && isLineStart(selectionEnd, in: string) {
            end = selectionEnd
        } else {
            end = NSMaxRange(string.lineRange(for: NSRange(location: selectionEnd, length: 0)))
        }
        return NSRange(location: start, length: end - start)
    }

    /// @note p0-295
    static func moveLines(in text: String, selection: NSRange, direction: LineDirection) -> LineEdit? {
        let string = text as NSString
        let selection = clamped(selection, toLength: string.length)
        let block = coveredLines(in: text, selection: selection)
        switch direction {
        case .up:
            guard block.location > 0 else { return nil }
            let above = string.lineRange(for: NSRange(location: block.location - 1, length: 0))
            let edit = swapped(upper: above, lower: block, in: string)
            // @note p0-296
            let moved = NSRange(location: selection.location - above.length, length: selection.length)
            return LineEdit(range: edit.range, replacement: edit.replacement, selection: moved)
        case .down:
            guard endsWithLineBreak(block, in: string) else { return nil }
            // @note p0-297
            let below = string.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
            let edit = swapped(upper: block, lower: below, in: string)
            let belowEndsWithLineBreak = endsWithLineBreak(below, in: string)
            // @note p0-298
            let shift = belowEndsWithLineBreak ? below.length : below.length + 1
            var moved = NSRange(location: selection.location + shift, length: selection.length)
            if !belowEndsWithLineBreak {
                // @note p0-299
                let replacedEnd = edit.range.location + (edit.replacement as NSString).length
                moved = clamped(moved, toLength: replacedEnd)
            }
            return LineEdit(range: edit.range, replacement: edit.replacement, selection: moved)
        }
    }

    /// @note p0-300
    static func duplicateLines(in text: String, selection: NSRange, direction: LineDirection) -> LineEdit {
        let string = text as NSString
        let selection = clamped(selection, toLength: string.length)
        let block = coveredLines(in: text, selection: selection)
        let lines = string.substring(with: block)
        // @note p0-301
        let copy = endsWithLineBreak(block, in: string) ? lines : "\n" + lines
        let range = NSRange(location: NSMaxRange(block), length: 0)
        switch direction {
        case .up:
            return LineEdit(range: range, replacement: copy, selection: selection)
        case .down:
            let shift = (copy as NSString).length
            let moved = NSRange(location: selection.location + shift, length: selection.length)
            return LineEdit(range: range, replacement: copy, selection: moved)
        }
    }

    /// @note p0-302
    static func expandedLineSelection(in text: String, selection: NSRange) -> NSRange? {
        let string = text as NSString
        let selection = clamped(selection, toLength: string.length)
        let covered = coveredLines(in: text, selection: selection)
        if selection != covered {
            return covered
        }
        guard NSMaxRange(covered) < string.length else { return nil }
        let next = string.lineRange(for: NSRange(location: NSMaxRange(covered), length: 0))
        return NSRange(location: covered.location, length: NSMaxRange(next) - covered.location)
    }

    /// @note p0-303
    static func fullLineCopyText(in text: String, cursor: Int) -> String {
        let string = text as NSString
        let line = string.lineRange(for: NSRange(location: clampedCursor(cursor, length: string.length), length: 0))
        let lineText = string.substring(with: line)
        return endsWithLineBreak(line, in: string) ? lineText : lineText + "\n"
    }

    /// @note p0-304
    static func fullLineCut(in text: String, cursor: Int) -> LineCut {
        let string = text as NSString
        let cursor = clampedCursor(cursor, length: string.length)
        let line = string.lineRange(for: NSRange(location: cursor, length: 0))
        let copiedText = fullLineCopyText(in: text, cursor: cursor)
        let removal: NSRange
        if endsWithLineBreak(line, in: string) || line.location == 0 {
            removal = line
        } else {
            let previousContentsEnd = contentsEnd(ofLineAt: line.location - 1, in: string)
            removal = NSRange(location: previousContentsEnd, length: NSMaxRange(line) - previousContentsEnd)
        }
        guard removal.length > 0 else {
            return LineCut(copiedText: copiedText, edit: nil)
        }
        let edit = LineEdit(range: removal, replacement: "", selection: NSRange(location: removal.location, length: 0))
        return LineCut(copiedText: copiedText, edit: edit)
    }

    /// @note p0-305
    static func fullLinePaste(_ pasted: String, in text: String, cursor: Int) -> LineEdit {
        let string = text as NSString
        let cursor = clampedCursor(cursor, length: string.length)
        let lineStart = string.lineRange(for: NSRange(location: cursor, length: 0)).location
        let pastedLength = (pasted as NSString).length
        return LineEdit(
            range: NSRange(location: lineStart, length: 0),
            replacement: pasted,
            selection: NSRange(location: cursor + pastedLength, length: 0)
        )
    }

    /// @note p0-306
    static func isFullLinePaste(selection: NSRange, pasteboardTypes: [NSPasteboard.PasteboardType]) -> Bool {
        selection.length == 0 && pasteboardTypes.contains(fullLinePasteboardType)
    }

    /// @note p0-307
    static func wordSelection(in text: String, selection: NSRange, wordRange: (Int) -> NSRange) -> NSRange? {
        let string = text as NSString
        let selection = clamped(selection, toLength: string.length)
        guard selection.length == 0, string.length > 0 else { return nil }
        let cursor = selection.location
        var candidates: [Int] = []
        if cursor < string.length {
            candidates.append(cursor)
        }
        if cursor > 0 {
            candidates.append(cursor - 1)
        }
        for position in candidates {
            let range = clamped(wordRange(position), toLength: string.length)
            if range.length > 0 && string.substring(with: range).rangeOfCharacter(from: .alphanumerics) != nil {
                return range
            }
        }
        return nil
    }

    // MARK: - 補助

    private static func clampedCursor(_ cursor: Int, length: Int) -> Int {
        max(0, min(cursor, length))
    }

    private static func isLineStart(_ index: Int, in string: NSString) -> Bool {
        index == 0 || string.lineRange(for: NSRange(location: index, length: 0)).location == index
    }

    /// @note p0-308
    private static func contentsEnd(ofLineAt index: Int, in string: NSString) -> Int {
        var contentsEnd = 0
        string.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
        return contentsEnd
    }

    /// @note p0-309
    private static func endsWithLineBreak(_ lines: NSRange, in string: NSString) -> Bool {
        guard lines.length > 0 else { return false }
        return contentsEnd(ofLineAt: NSMaxRange(lines) - 1, in: string) < NSMaxRange(lines)
    }

    /// @note p0-310
    private static func contents(of lines: NSRange, in string: NSString) -> String {
        guard endsWithLineBreak(lines, in: string) else { return string.substring(with: lines) }
        let end = contentsEnd(ofLineAt: NSMaxRange(lines) - 1, in: string)
        return string.substring(with: NSRange(location: lines.location, length: end - lines.location))
    }

    /// @note p0-311
    private static func swapped(upper: NSRange, lower: NSRange, in string: NSString) -> (range: NSRange, replacement: String) {
        let range = NSRange(location: upper.location, length: NSMaxRange(lower) - upper.location)
        let lowerText = string.substring(with: lower)
        let replacement: String
        if endsWithLineBreak(lower, in: string) {
            replacement = lowerText + string.substring(with: upper)
        } else {
            replacement = lowerText + "\n" + contents(of: upper, in: string)
        }
        return (range, replacement)
    }
}
