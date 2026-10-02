import AppKit
import SwiftUI

/// チュートリアルの練習用の入力欄。
final class PracticeTextView: NSTextView {
    var pasteboard: NSPasteboard = .general

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

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        let textView = PracticeTextView()
        textView.delegate = context.coordinator
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
