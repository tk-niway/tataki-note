import AppKit
import SwiftUI

/// パネルの入力欄。
final class PromptTextView: EditorTextView {
    var onKeyInput: ((PanelKeyInput) -> Bool)?

    // MARK: - キー操作

    override func keyDown(with event: NSEvent) {
        let input = PanelKeyInput(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
            hasMarkedText: hasMarkedText(),
            characters: event.charactersIgnoringModifiers?.lowercased() ?? ""
        )
        if onKeyInput?(input) == true {
            return
        }
        if let command = LineEditing.arrowCommand(for: input) {
            performLineArrowCommand(command)
            return
        }
        super.keyDown(with: event)
    }

    override func handleKeyEquivalent(_ event: NSEvent) -> EditorKeyEquivalentResult {
        let input = PanelKeyInput(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
            hasMarkedText: false,
            characters: event.charactersIgnoringModifiers?.lowercased() ?? ""
        )
        if onKeyInput?(input) == true {
            return .handled
        }
        if event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.keypadEnter {
            if PanelKeyResolver.insertsNewlineExplicitly(for: input) {
                insertNewline(nil)
                return .handled
            }
            return .passToSystem
        }
        let modifiers = event.modifierFlags.intersection(PanelShortcut.relevantModifiers)
        switch EditorKeyCommand.command(modifiers: modifiers, character: input.characters) {
        case .selectWord:
            selectWordAtCursor()
            return .handled
        case .selectLine:
            expandLineSelection()
            return .handled
        default:
            return .notHandled
        }
    }

    override func copyCommand() {
        copyLineOrSelection()
    }

    override func cutCommand() {
        cutLineOrSelection()
    }

    override func pasteCommand() {
        pasteLineOrClipboard()
    }

    // MARK: - 行・単語の操作

    func performLineArrowCommand(_ command: LineArrowCommand) {
        switch command {
        case .moveLines(let direction): moveLines(direction)
        case .duplicateLines(let direction): duplicateLines(direction)
        }
    }

    func moveLines(_ direction: LineDirection) {
        guard let edit = LineEditing.moveLines(in: string, selection: selectedRange(), direction: direction) else { return }
        apply(edit)
    }

    func duplicateLines(_ direction: LineDirection) {
        apply(LineEditing.duplicateLines(in: string, selection: selectedRange(), direction: direction))
    }

    func expandLineSelection() {
        guard let range = LineEditing.expandedLineSelection(in: string, selection: selectedRange()) else { return }
        selectAndReveal(range)
    }

    func selectWordAtCursor() {
        let word = LineEditing.wordSelection(in: string, selection: selectedRange()) { position in
            selectionRange(forProposedRange: NSRange(location: position, length: 1), granularity: .selectByWord)
        }
        guard let word else { return }
        selectAndReveal(word)
    }

    func copyLineOrSelection() {
        let selection = selectedRange()
        guard selection.length == 0 else {
            copy(nil)
            return
        }
        writeFullLine(LineEditing.fullLineCopyText(in: string, cursor: selection.location))
    }

    func cutLineOrSelection() {
        let selection = selectedRange()
        guard selection.length == 0 else {
            cut(nil)
            return
        }
        let lineCut = LineEditing.fullLineCut(in: string, cursor: selection.location)
        writeFullLine(lineCut.copiedText)
        if let edit = lineCut.edit {
            apply(edit)
        }
    }

    func pasteLineOrClipboard() {
        let selection = selectedRange()
        if LineEditing.isFullLinePaste(selection: selection, pasteboardTypes: pasteboard.types ?? []),
           let line = pasteboard.string(forType: .string) {
            apply(LineEditing.fullLinePaste(line, in: string, cursor: selection.location))
            return
        }
        paste(nil)
    }

    private func writeFullLine(_ line: String) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, LineEditing.fullLinePasteboardType], owner: nil)
        pasteboard.setString(line, forType: .string)
        pasteboard.setString("1", forType: LineEditing.fullLinePasteboardType)
    }

    private func apply(_ edit: LineEdit) {
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        let changed = shouldChangeText(in: edit.range, replacementString: edit.replacement)
        if changed {
            textStorage?.replaceCharacters(
                in: edit.range,
                with: NSAttributedString(string: edit.replacement, attributes: typingAttributes)
            )
            didChangeText()
        }
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
        guard changed else { return }
        selectAndReveal(edit.selection)
    }

    private func selectAndReveal(_ range: NSRange) {
        let selection = LineEditing.clamped(range, toLength: (string as NSString).length)
        setSelectedRange(selection)
        scrollRangeToVisible(selection)
    }
}

struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let font: NSFont
    var placeholder: String = ""
    let onKeyInput: (PanelKeyInput) -> Bool

    typealias Coordinator = EditorTextCoordinator

    func makeCoordinator() -> Coordinator {
        EditorTextCoordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PromptTextView()
        textView.delegate = context.coordinator
        textView.onKeyInput = onKeyInput
        textView.configurePlainTextEditing(
            textContainerInset: PanelMetrics.textContainerInset,
            accessibilityIdentifier: "promptPanel.textView"
        )
        textView.applyFont(font)
        textView.placeholder = placeholder
        textView.string = text
        return EditorTextView.scrollView(containing: textView, backgroundColor: nil)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PromptTextView else { return }
        textView.onKeyInput = onKeyInput
        context.coordinator.text = $text
        textView.applyFont(font)
        if textView.placeholder != placeholder {
            textView.placeholder = placeholder
        }
        context.coordinator.syncText(text, to: textView)
        context.coordinator.focusIfRequested(focusRequest, textView: textView)
    }
}
