import AppKit

extension PromptTextView: FindTextEditing {
    var findText: String {
        string
    }

    var findSelection: NSRange {
        selectedRange()
    }

    func showFindHighlights(_ ranges: [NSRange], current: NSRange?) {
        let length = (string as NSString).length
        let highlights = FindHighlighter.highlights(ranges, current: current, textLength: length)
        storeFindHighlights(highlights)
        FindHighlighter.apply(highlights, to: self)
    }

    func revealFindMatch(_ range: NSRange) {
        let selection = LineEditing.clamped(range, toLength: (string as NSString).length)
        setSelectedRange(selection)
        scrollRangeToVisible(selection)
    }

    func replaceForFind(_ edits: [FindEdit], selectionAfter: NSRange) {
        let text = string as NSString
        let sorted = edits
            .map { FindEdit(range: LineEditing.clamped($0.range, toLength: text.length), replacement: $0.replacement) }
            .sorted { $0.range.location < $1.range.location }
        guard let first = sorted.first, let spanEnd = sorted.map({ NSMaxRange($0.range) }).max() else { return }

        let span = NSRange(location: first.range.location, length: spanEnd - first.range.location)
        let composed = NSMutableString()
        var cursor = span.location
        for edit in sorted where edit.range.location >= cursor {
            composed.append(text.substring(with: NSRange(location: cursor, length: edit.range.location - cursor)))
            composed.append(edit.replacement)
            cursor = NSMaxRange(edit.range)
        }
        composed.append(text.substring(with: NSRange(location: cursor, length: NSMaxRange(span) - cursor)))

        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        let changed = shouldChangeText(in: span, replacementString: composed as String)
        if changed {
            textStorage?.replaceCharacters(
                in: span,
                with: NSAttributedString(string: composed as String, attributes: typingAttributes)
            )
            didChangeText()
        }
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
        guard changed else { return }
        revealFindMatch(selectionAfter)
    }

    func focusForFind() {
        window?.makeFirstResponder(self)
    }
}
