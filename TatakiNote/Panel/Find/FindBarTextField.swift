import AppKit
import SwiftUI

/// 検索欄・置換欄のセル。文字を欄の縦の中央に置く。
final class FindBarTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centered(super.drawingRect(forBounds: rect))
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    private func centered(_ rect: NSRect) -> NSRect {
        FindBarFieldLayout.verticallyCentered(rect, contentHeight: lineHeight)
    }

    private var lineHeight: CGFloat {
        ceil(NSLayoutManager().defaultLineHeight(for: font ?? .systemFont(ofSize: NSFont.systemFontSize)))
    }
}

/// 検索欄・置換欄の `NSTextField`。⌘ の編集のキーを欄の編集として受け、取り消しは欄専用の履歴で行う。
final class FindBarNSTextField: NSTextField, FindFieldIdentifying {
    override class var cellClass: AnyClass? {
        get { FindBarTextFieldCell.self }
        set {}
    }

    let findField: FindField
    /// この欄の文字だけを戻すための取り消しの履歴。
    let fieldUndoManager = UndoManager()
    var onFocusChange: ((Bool) -> Void)?
    var onMovedToWindow: (() -> Void)?

    init(findField: FindField) {
        self.findField = findField
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    var hasMarkedTextInEditor: Bool {
        (currentEditor() as? NSTextView)?.hasMarkedText() ?? false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 24)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            onMovedToWindow?()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    @objc(undoManagerForTextView:)
    func undoManager(for view: NSTextView) -> UndoManager? {
        fieldUndoManager
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let editor = currentEditor() as? NSTextView
        guard event.type == .keyDown,
              let editor,
              let action = FindKeys.fieldEditAction(
                  modifiers: event.modifierFlags,
                  character: event.charactersIgnoringModifiers?.lowercased() ?? "",
                  isEditing: currentEditor() != nil,
                  hasMarkedText: editor.hasMarkedText()
              ) else {
            return super.performKeyEquivalent(with: event)
        }
        switch action {
        case .cut: editor.cut(nil)
        case .copy: editor.copy(nil)
        case .paste: editor.paste(nil)
        case .selectAll: editor.selectAll(nil)
        case .undo: editor.undoManager?.undo()
        case .redo: editor.undoManager?.redo()
        }
        return true
    }
}

/// 検索バーの検索欄・置換欄。文字は `Binding` で受け渡し、改行は欄の中では「↵」で見せる。
struct FindBarTextField: NSViewRepresentable {
    @Binding var text: String
    let model: FindModel
    let findField: FindField
    let focusRequest: FindFieldFocusRequest
    let placeholder: String
    let identifier: String
    let onFocusChange: (Bool) -> Void

    static let newlineMark = "↵"

    /// モデルの文字を、欄に出す文字にする。改行は「↵」にする。
    static func displayText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: newlineMark)
            .replacingOccurrences(of: "\r", with: newlineMark)
            .replacingOccurrences(of: "\n", with: newlineMark)
    }

    /// 欄の文字を、モデルに渡す文字にする。「↵」は改行に戻す。
    static func modelText(_ displayed: String) -> String {
        displayed.replacingOccurrences(of: newlineMark, with: "\n")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> FindBarNSTextField {
        let field = FindBarNSTextField(findField: findField)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = .labelColor
        field.lineBreakMode = .byClipping
        field.cell?.usesSingleLineMode = false
        field.cell?.isScrollable = true
        field.placeholderString = placeholder
        field.stringValue = Self.displayText(text)
        field.setAccessibilityIdentifier(identifier)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.onFocusChange = { [weak coordinator = context.coordinator] isFocused in
            coordinator?.parent.onFocusChange(isFocused)
        }
        field.onMovedToWindow = { [weak coordinator = context.coordinator, weak field] in
            guard let field else { return }
            coordinator?.applyPendingFocus(to: field)
        }
        context.coordinator.applyPendingFocus(to: field)
        return field
    }

    func updateNSView(_ field: FindBarNSTextField, context: Context) {
        context.coordinator.parent = self
        if !field.hasMarkedTextInEditor, Self.modelText(Coordinator.currentString(of: field)) != text {
            field.stringValue = Self.displayText(text)
            field.fieldUndoManager.removeAllActions()
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
        context.coordinator.applyPendingFocus(to: field)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FindBarTextField
        var isFocusScheduled = false
        private var isNormalizing = false

        init(_ parent: FindBarTextField) {
            self.parent = parent
        }

        static func currentString(of field: FindBarNSTextField) -> String {
            (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
        }

        func applyPendingFocus(to field: FindBarNSTextField) {
            let model = parent.model
            guard model.hasPendingFocus(for: field.findField), !isFocusScheduled else { return }
            isFocusScheduled = true
            DispatchQueue.main.async { [weak self, weak field] in
                self?.isFocusScheduled = false
                guard let self, let field, let window = field.window,
                      model.hasPendingFocus(for: field.findField) else { return }
                window.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
                model.didApplyFocus()
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isNormalizing, let field = notification.object as? FindBarNSTextField else { return }
            if let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText() {
                normalizeNewlines(in: editor)
            }
            let newText = FindBarTextField.modelText(Self.currentString(of: field))
            if parent.text != newText {
                parent.text = newText
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        private func normalizeNewlines(in editor: NSTextView) {
            let original = editor.string
            guard original.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) else { return }
            let converted = FindBarTextField.displayText(original)
            let source = original as NSString
            let selected = editor.selectedRange()
            let start = (FindBarTextField.displayText(source.substring(to: selected.location)) as NSString).length
            let end = (FindBarTextField.displayText(source.substring(to: selected.location + selected.length)) as NSString).length
            let fullRange = NSRange(location: 0, length: source.length)
            isNormalizing = true
            defer { isNormalizing = false }
            if editor.shouldChangeText(in: fullRange, replacementString: converted) {
                editor.replaceCharacters(in: fullRange, with: converted)
                editor.didChangeText()
            }
            editor.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        }
    }
}
