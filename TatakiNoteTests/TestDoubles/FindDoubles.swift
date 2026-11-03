import Foundation
@testable import TatakiNote

@MainActor
final class FakeFindEditor: FindTextEditing {
    var findText: String
    var findSelection: NSRange
    var onTextChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?

    private(set) var highlightCalls: [(ranges: [NSRange], current: NSRange?)] = []
    private(set) var revealed: [NSRange] = []
    private(set) var replaceCalls: [(edits: [FindEdit], selectionAfter: NSRange)] = []
    private(set) var focusCount = 0

    init(_ marked: String) {
        let (text, selection) = MarkedText.parse(marked)
        findText = text
        findSelection = selection
    }

    var lastHighlights: (ranges: [NSRange], current: NSRange?)? {
        highlightCalls.last
    }

    var marked: String {
        MarkedText.render(findText, selection: findSelection)
    }

    func showFindHighlights(_ ranges: [NSRange], current: NSRange?) {
        highlightCalls.append((ranges, current))
    }

    func revealFindMatch(_ range: NSRange) {
        revealed.append(range)
        findSelection = range
        onSelectionChange?()
    }

    func replaceForFind(_ edits: [FindEdit], selectionAfter: NSRange) {
        replaceCalls.append((edits, selectionAfter))
        let text = NSMutableString(string: findText)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            text.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        findText = text as String
        findSelection = selectionAfter
        onTextChange?()
    }

    func focusForFind() {
        focusCount += 1
    }

    func setText(_ marked: String) {
        let (text, selection) = MarkedText.parse(marked)
        findText = text
        findSelection = selection
    }
}
