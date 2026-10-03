import AppKit
import SwiftUI

/// ⌘ のキーの処理を、派生クラスが先に引き受けたかどうか。
enum EditorKeyEquivalentResult {
    case notHandled
    case handled
    case passToSystem
}

/// パネルと練習用のチャットの入力欄に共通の土台。
class EditorTextView: NSTextView {
    var pasteboard: NSPasteboard = .general

    private var pendingFont: NSFont?

    /// 空のときに出すプレースホルダー。アクセシビリティの値にも渡す。
    var placeholder = "" {
        didSet {
            setAccessibilityPlaceholderValue(placeholder)
            needsDisplay = true
        }
    }

    /// true のときだけ、空の入力欄にプレースホルダーを薄い文字で描く。
    var drawsPlaceholder: Bool { false }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard drawsPlaceholder, string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = NSPoint(x: textContainerOrigin.x + padding, y: textContainerOrigin.y)
        NSAttributedString(string: placeholder, attributes: attributes).draw(at: origin)
    }

    // MARK: - 変換とフォント

    override func didChangeText() {
        super.didChangeText()
        applyPendingFontIfNeeded()
        if drawsPlaceholder {
            needsDisplay = true
        }
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        if drawsPlaceholder {
            needsDisplay = true
        }
    }

    override func unmarkText() {
        super.unmarkText()
        applyPendingFontIfNeeded()
        if drawsPlaceholder {
            needsDisplay = true
        }
    }

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

    private func applyPendingFontIfNeeded() {
        guard let pendingFont, !hasMarkedText() else { return }
        applyFont(pendingFont)
    }

    // MARK: - 確定

    /// 変換中の文字を今の読みのまま確定する。
    func commitMarkedText() {
        guard hasMarkedText() else { return }
        unmarkText()
        inputContext?.discardMarkedText()
        didChangeText()
    }

    // MARK: - キー操作

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, !hasMarkedText() else {
            return super.performKeyEquivalent(with: event)
        }
        switch handleKeyEquivalent(event) {
        case .handled:
            return true
        case .passToSystem:
            return super.performKeyEquivalent(with: event)
        case .notHandled:
            break
        }
        let modifiers = event.modifierFlags.intersection(PanelShortcut.relevantModifiers)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if modifiers == [.command] {
            switch key {
            case "a": selectAll(nil)
            case "c": copyCommand()
            case "x": cutCommand()
            case "v": pasteCommand()
            case "z": performUndoRedo { $0.undo() }
            default: return super.performKeyEquivalent(with: event)
            }
            return true
        }
        if modifiers == [.command, .shift] && key == "z" {
            performUndoRedo { $0.redo() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func performUndoRedo(_ action: (UndoManager) -> Void) {
        guard let undoManager else { return }
        let before = string
        action(undoManager)
        if string != before {
            didChangeText()
        }
    }

    /// 派生クラスが、共通の ⌘ のキーより先に処理するための口。
    func handleKeyEquivalent(_ event: NSEvent) -> EditorKeyEquivalentResult {
        .notHandled
    }

    /// ⌘C の処理。選択があればクリップボードへ入れる。
    func copyCommand() {
        _ = copySelectionToPasteboard()
    }

    /// ⌘X の処理。選択をクリップボードへ入れて消す。
    func cutCommand() {
        guard copySelectionToPasteboard() else { return }
        insertText("", replacementRange: selectedRange())
    }

    /// ⌘V の処理。クリップボードの文字列を選択の位置へ入れる。
    func pasteCommand() {
        guard let string = pasteboard.string(forType: .string) else { return }
        insertText(string, replacementRange: selectedRange())
    }

    private func copySelectionToPasteboard() -> Bool {
        let selection = selectedRange()
        guard selection.length > 0 else { return false }
        pasteboard.clearContents()
        return pasteboard.setString((string as NSString).substring(with: selection), forType: .string)
    }

    // MARK: - 組み立て

    /// 書式なしの文章を縦に伸ばして入れる入力欄としての設定をまとめて行う。
    func configurePlainTextEditing(textContainerInset: NSSize, accessibilityIdentifier: String) {
        isRichText = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        textColor = .textColor
        drawsBackground = false
        self.textContainerInset = textContainerInset
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        setAccessibilityIdentifier(accessibilityIdentifier)
    }

    /// 入力欄を縦のスクロールビューで包む。`backgroundColor` が `nil` なら背景を描かない。
    static func scrollView(containing textView: EditorTextView, backgroundColor: NSColor?) -> NSScrollView {
        let scrollView = NSScrollView()
        if let backgroundColor {
            scrollView.drawsBackground = true
            scrollView.backgroundColor = backgroundColor
        } else {
            scrollView.drawsBackground = false
        }
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }
}

/// 入力欄と SwiftUI の文章のやり取りと、フォーカスの要求を受け持つ。
final class EditorTextCoordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    var lastFocusRequest: Int?
    private(set) var lastSyncedText: String

    init(text: Binding<String>) {
        self.text = text
        self.lastSyncedText = text.wrappedValue
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        let current = textView.string
        lastSyncedText = current
        text.wrappedValue = current
    }

    /// SwiftUI 側の文章が入力欄と違うときだけ、変換中でなければ入力欄へ入れ、取り消しの履歴を消す。
    func syncText(_ newText: String, to textView: EditorTextView) {
        guard newText != lastSyncedText, !textView.hasMarkedText() else { return }
        textView.string = newText
        lastSyncedText = newText
        textView.undoManager?.removeAllActions()
        textView.needsDisplay = true
    }

    /// 新しい要求の番号のときだけ、入力欄をファーストレスポンダにして末尾にカーソルを置く。
    func focusIfRequested(_ request: Int, textView: EditorTextView) {
        guard lastFocusRequest != request else { return }
        lastFocusRequest = request
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
        }
    }
}
