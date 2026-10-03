import AppKit
import SwiftUI

/// チュートリアルの練習用の入力欄。
final class PracticeTextView: EditorTextView {
    var onSend: ((String) -> Bool)?

    override var drawsEmptyPlaceholder: Bool { true }

    // MARK: - キー操作

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
            commitMarkedText()
            _ = onSend?(string)
        case .insertNewline:
            insertNewline(nil)
        case .passThrough:
            super.keyDown(with: event)
        }
    }
}

/// 練習用の入力欄を SwiftUI に置く。
struct PracticeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let placeholder: String
    let onSend: (String) -> Bool

    typealias Coordinator = EditorTextCoordinator

    func makeCoordinator() -> Coordinator {
        EditorTextCoordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PracticeTextView()
        textView.delegate = context.coordinator
        textView.onSend = onSend
        textView.configurePlainTextEditing(
            textContainerInset: NSSize(width: 4, height: 6),
            accessibilityIdentifier: "tutorial.practiceField"
        )
        textView.applyFont(.systemFont(ofSize: NSFont.systemFontSize))
        textView.placeholder = placeholder
        textView.string = text
        return EditorTextView.scrollView(containing: textView, backgroundColor: .textBackgroundColor)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PracticeTextView else { return }
        context.coordinator.text = $text
        textView.onSend = onSend
        if textView.placeholder != placeholder {
            textView.placeholder = placeholder
        }
        context.coordinator.syncText(text, to: textView)
        context.coordinator.focusIfRequested(focusRequest, textView: textView)
    }
}
