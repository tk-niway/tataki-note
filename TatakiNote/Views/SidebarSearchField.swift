import AppKit
import SwiftUI

/// サイドバーの検索欄。入力メソッドが使わなかった ↑ ↓ ↩ esc を `SidebarKey` にして渡す。
struct SidebarSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let hasPendingFocus: Bool
    let onFocusHandled: () -> Void
    let onFocusChange: (Bool) -> Void
    let onKey: (SidebarKey, NSEvent.ModifierFlags, Bool) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> FocusReportingSearchField {
        let field = FocusReportingSearchField()
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.valueChanged(_:))
        field.sendsSearchStringImmediately = true
        field.focusRingType = .none
        field.setAccessibilityIdentifier("sidebar.searchField")
        field.onFocusChange = { [weak coordinator = context.coordinator] isFocused in
            coordinator?.parent.onFocusChange(isFocused)
        }
        return field
    }

    func updateNSView(_ field: FocusReportingSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text, !field.hasMarkedTextInEditor {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
        if hasPendingFocus, !context.coordinator.isFocusScheduled {
            context.coordinator.isFocusScheduled = true
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                coordinator?.isFocusScheduled = false
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
                coordinator?.parent.onFocusHandled()
            }
        }
    }

    final class FocusReportingSearchField: NSSearchField {
        var onFocusChange: ((Bool) -> Void)?

        var hasMarkedTextInEditor: Bool {
            (currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocusChange?(true) }
            return accepted
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SidebarSearchField
        var isFocusScheduled = false

        init(_ parent: SidebarSearchField) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: NSSearchField) {
            if parent.text != sender.stringValue {
                parent.text = sender.stringValue
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            valueChanged(field)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let key = Self.key(for: commandSelector) else { return false }
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            return parent.onKey(key, modifiers, textView.hasMarkedText())
        }

        static func key(for selector: Selector) -> SidebarKey? {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): .up
            case #selector(NSResponder.moveDown(_:)): .down
            case #selector(NSResponder.insertNewline(_:)): .returnKey
            case #selector(NSResponder.cancelOperation(_:)): .escape
            default: nil
            }
        }
    }
}
