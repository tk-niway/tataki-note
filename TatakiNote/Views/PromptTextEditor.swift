import AppKit
import SwiftUI

/// パネルの入力欄。
final class PromptTextView: NSTextView {
    var onKeyInput: ((PanelKeyInput) -> Bool)?

    var pasteboard: NSPasteboard = .general

    private var pendingFont: NSFont?

    // MARK: - フォント

    func applyFont(_ font: NSFont) {
        guard !hasMarkedText() else {
            pendingFont = font
            return
        }
        pendingFont = nil
        guard self.font != font || typingAttributes[.font] as? NSFont != font else { return }
        self.font = font
        typingAttributes[.font] = font
    }


    override func unmarkText() {
        super.unmarkText()
        applyPendingFontIfNeeded()
    }

    override func didChangeText() {
        super.didChangeText()
        applyPendingFontIfNeeded()
    }

    private func applyPendingFontIfNeeded() {
        guard let pendingFont, !hasMarkedText() else { return }
        applyFont(pendingFont)
    }

    // MARK: - 確定

    func commitMarkedText() {
        guard hasMarkedText() else { return }
        unmarkText()
        inputContext?.discardMarkedText()
        didChangeText()
    }

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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, !hasMarkedText() else {
            return super.performKeyEquivalent(with: event)
        }
        let input = PanelKeyInput(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
            hasMarkedText: false,
            characters: event.charactersIgnoringModifiers?.lowercased() ?? ""
        )
        if onKeyInput?(input) == true {
            return true
        }
        if event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.keypadEnter {
            if PanelKeyResolver.insertsNewlineExplicitly(for: input) {
                insertNewline(nil)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = input.characters
        let command: NSEvent.ModifierFlags = [.command]
        let shiftCommand: NSEvent.ModifierFlags = [.command, .shift]
        if modifiers == command {
            switch key {
            case "a": selectAll(nil)
            case "c": copyLineOrSelection()
            case "d": selectWordAtCursor()
            case "l": expandLineSelection()
            case "v": pasteLineOrClipboard()
            case "x": cutLineOrSelection()
            case "z": undoManager?.undo()
            default: return super.performKeyEquivalent(with: event)
            }
            return true
        }
        if modifiers == shiftCommand && key == "z" {
            undoManager?.redo()
            return true
        }
        return super.performKeyEquivalent(with: event)
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
    let onKeyInput: (PanelKeyInput) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = PromptTextView()
        textView.delegate = context.coordinator
        textView.onKeyInput = onKeyInput
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.applyFont(font)
        textView.textColor = .textColor
        textView.drawsBackground = false
        textView.textContainerInset = PanelMetrics.textContainerInset
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.setAccessibilityIdentifier("promptPanel.textView")

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PromptTextView else { return }
        textView.onKeyInput = onKeyInput
        context.coordinator.text = $text
        textView.applyFont(font)

        if textView.string != text && !textView.hasMarkedText() {
            textView.string = text
            textView.undoManager?.removeAllActions()
        }

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                textView.window?.makeFirstResponder(textView)
                let end = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                textView.scrollRangeToVisible(NSRange(location: end, length: 0))
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var lastFocusRequest: Int?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
