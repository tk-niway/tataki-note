import ApplicationServices

/// 挿入の前に調べた、フォーカスのある要素。
struct FocusedInputInspection: Equatable {
    let state: FocusedTextInputState
    let isSecureTextField: Bool
}

protocol FocusedTextInputInspecting {
    func focusedTextInputState(in target: InsertionTarget) -> FocusedTextInputState
    /// 入力欄かと、パスワード欄かを1回の問い合わせで調べる。
    func inspectFocusedInput(in target: InsertionTarget) -> FocusedInputInspection
    /// フォーカスのある要素の中身の文字列。読めなければ nil。
    func focusedTextValue(in target: InsertionTarget) -> String?
    /// フォーカスのある要素。読めなければ nil。
    func focusedElement(in target: InsertionTarget) -> AXUIElement?
}

extension FocusedTextInputInspecting {
    func inspectFocusedInput(in target: InsertionTarget) -> FocusedInputInspection {
        FocusedInputInspection(state: focusedTextInputState(in: target), isSecureTextField: false)
    }

    func focusedTextValue(in target: InsertionTarget) -> String? { nil }
}

extension AXFocusedTextInputInspector: FocusedTextInputInspecting {
    static let valueReadTimeout: Float = 0.2

    func focusedTextValue(in target: InsertionTarget) -> String? {
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, Self.valueReadTimeout)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let element = unsafeDowncast(focusedValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, Self.valueReadTimeout)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    func focusedElement(in target: InsertionTarget) -> AXUIElement? {
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(focusedValue, to: AXUIElement.self)
    }

    func focusedTextInputState(in target: InsertionTarget) -> FocusedTextInputState {
        FocusedTextInputState.classifyForInsertion(
            probeFocusedElement(in: target, readsFrame: false).lookup,
            bundleIdentifier: target.bundleIdentifier
        )
    }

    func inspectFocusedInput(in target: InsertionTarget) -> FocusedInputInspection {
        let lookup = probeFocusedElement(in: target, readsFrame: false).lookup
        return FocusedInputInspection(
            state: FocusedTextInputState.classifyForInsertion(lookup, bundleIdentifier: target.bundleIdentifier),
            isSecureTextField: FocusedTextInputState.isSecureTextField(lookup)
        )
    }
}
