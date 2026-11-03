import ApplicationServices

/// アクセシビリティ API で、挿入先のアプリのフォーカスのある要素を調べる。
struct AXFocusedTextInputInspector: FocusedElementProbing {
    nonisolated static let messagingTimeout: Float = 0.5

    /// Web の中身をアクセシビリティの仕組みに出すよう、挿入先のアプリに頼み、その結果を返す。
    @discardableResult
    nonisolated static func exposeWebContent(of target: InsertionTarget) -> AXError {
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    nonisolated func probeFocusedElement(in target: InsertionTarget, readsFrame: Bool) -> FocusedElementProbe {
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)

        var focusedValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        if error == .noValue {
            return FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil)
        }
        guard error == .success, let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return FocusedElementProbe(element: nil, lookup: .unavailable, frame: nil)
        }
        let element = unsafeDowncast(focusedValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)

        var settable: DarwinBoolean = false
        let isSelectedTextRangeSettable =
            AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success
            && settable.boolValue
        let lookup = FocusedElementLookup.element(
            role: stringAttribute(kAXRoleAttribute, of: element),
            subrole: stringAttribute(kAXSubroleAttribute, of: element),
            isSelectedTextRangeSettable: isSelectedTextRangeSettable
        )
        return FocusedElementProbe(
            element: element,
            lookup: lookup,
            frame: Self.shouldReadFrame(requested: readsFrame, lookup: lookup) ? frame(of: element) : nil
        )
    }

    /// フォーカスのある要素の位置と大きさを読むか。
    nonisolated static func shouldReadFrame(requested: Bool, lookup: FocusedElementLookup) -> Bool {
        requested && FocusedTextInputState.classify(lookup) == .textInput
    }

    private nonisolated func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    nonisolated func frame(of element: AXUIElement) -> CGRect? {
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue = axValueAttribute(kAXPositionAttribute, of: element),
              AXValueGetValue(positionValue, .cgPoint, &origin),
              let sizeValue = axValueAttribute(kAXSizeAttribute, of: element),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private nonisolated func axValueAttribute(_ attribute: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXValue.self)
    }
}
