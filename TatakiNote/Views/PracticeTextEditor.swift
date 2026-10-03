import AppKit
import SwiftUI

/// チュートリアルの練習用の入力欄。
final class PracticeTextView: NSTextView {
    var pasteboard: NSPasteboard = .general
    var onSend: ((String) -> Bool)?
    var placeholder = "" {
        didSet {
            setAccessibilityPlaceholderValue(placeholder)
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        let action = PracticeChatKeyResolver.action(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            hasMarkedText: hasMarkedText()
        )
        switch action {
        case .send:
            _ = onSend?(string)
        case .commitMarkedTextAndSend:
            super.keyDown(with: event)
            if hasMarkedText() {
                unmarkText()
                inputContext?.discardMarkedText()
            }
            _ = onSend?(string)
        case .insertNewline:
            insertNewline(nil)
        case .passThrough:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = NSPoint(x: textContainerOrigin.x + padding, y: textContainerOrigin.y)
        NSAttributedString(string: placeholder, attributes: attributes).draw(at: origin)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
    }

    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, !hasMarkedText() else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection(PanelShortcut.relevantModifiers)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if modifiers == [.command] {
            switch key {
            case "a": selectAll(nil)
            case "c": copySelection()
            case "v": pasteFromPasteboard()
            case "x": cutSelection()
            case "z": undoManager?.undo()
            default: return super.performKeyEquivalent(with: event)
            }
            return true
        }
        if modifiers == [.command, .shift] && key == "z" {
            undoManager?.redo()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @discardableResult
    private func copySelection() -> Bool {
        let selection = selectedRange()
        guard selection.length > 0 else { return false }
        pasteboard.clearContents()
        return pasteboard.setString((string as NSString).substring(with: selection), forType: .string)
    }

    private func cutSelection() {
        guard copySelection() else { return }
        insertText("", replacementRange: selectedRange())
    }

    private func pasteFromPasteboard() {
        guard let string = pasteboard.string(forType: .string) else { return }
        insertText(string, replacementRange: selectedRange())
    }
}

/// 練習用の入力欄を SwiftUI に置く。
struct PracticeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let placeholder: String
    let onSend: (String) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSend: onSend)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = PracticeTextView()
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.onSend = { [weak coordinator = context.coordinator] text in
            coordinator?.onSend(text) ?? false
        }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .textColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.setAccessibilityIdentifier("tutorial.practiceField")

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PracticeTextView else { return }
        context.coordinator.text = $text
        context.coordinator.onSend = onSend
        if textView.placeholder != placeholder {
            textView.placeholder = placeholder
        }

        if textView.string != text && !textView.hasMarkedText() {
            textView.string = text
            textView.undoManager?.removeAllActions()
            textView.needsDisplay = true
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
        var onSend: (String) -> Bool
        var lastFocusRequest: Int?

        init(text: Binding<String>, onSend: @escaping (String) -> Bool = { _ in false }) {
            self.text = text
            self.onSend = onSend
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
