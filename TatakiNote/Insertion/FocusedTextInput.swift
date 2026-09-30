import ApplicationServices

/// @note p0-66
enum FocusedTextInputState: Equatable {
    /// @note p0-67
    case textInput
    /// @note p0-68
    case notTextInput
    /// @note p0-69
    case unknown
}

/// @note p0-70
enum FocusedElementLookup: Equatable {
    /// @note p0-71
    case element(role: String?, subrole: String?, isSelectedTextRangeSettable: Bool)
    /// @note p0-72
    case noFocusedElement
    /// @note p0-73
    case unavailable
}

extension FocusedTextInputState {
    /// @note p0-74
    static let textInputRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    /// @note p0-75
    static let nonTextInputRoles: Set<String> = [
        "AXWebArea",
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXLink",
        "AXList", "AXOutline", "AXTable", "AXBrowser", "AXRow", "AXCell",
        "AXScrollArea", "AXImage", "AXSlider", "AXTabGroup", "AXStaticText",
    ]

    /// @note p0-76
    static let unknownMeansNotTextInputBundleIdentifiers: Set<String> = ["com.apple.finder"]

    /// @note p0-77
    static let secureTextFieldSubrole = "AXSecureTextField"

    static func classify(_ lookup: FocusedElementLookup) -> FocusedTextInputState {
        switch lookup {
        case .unavailable:
            return .unknown
        case .noFocusedElement:
            return .notTextInput
        // @note p0-78
        case .element(let role, _, let isSelectedTextRangeSettable):
            // @note p0-79
            if isSelectedTextRangeSettable {
                return .textInput
            }
            guard let role else { return .unknown }
            if textInputRoles.contains(role) {
                return .textInput
            }
            if nonTextInputRoles.contains(role) {
                return .notTextInput
            }
            return .unknown
        }
    }

    /// @note p0-80
    static func classifyForInsertion(_ lookup: FocusedElementLookup, bundleIdentifier: String?) -> FocusedTextInputState {
        let state = classify(lookup)
        if state == .unknown, let bundleIdentifier, unknownMeansNotTextInputBundleIdentifiers.contains(bundleIdentifier) {
            return .notTextInput
        }
        return state
    }
}

protocol FocusedTextInputInspecting {
    func focusedTextInputState(in target: InsertionTarget) -> FocusedTextInputState
}

/// @note p0-81
struct FocusedElementProbe {
    /// @note p0-82
    let element: AXUIElement?
    let lookup: FocusedElementLookup
    /// @note p0-83
    let frame: CGRect?

    /// @note p0-84
    var subrole: String? {
        if case .element(_, let subrole, _) = lookup {
            return subrole
        }
        return nil
    }
}

protocol FocusedElementProbing {
    func probeFocusedElement(in target: InsertionTarget, readsFrame: Bool) -> FocusedElementProbe
}

/// @note p0-85
struct AXFocusedTextInputInspector: FocusedTextInputInspecting, FocusedElementProbing {
    /// @note p0-86
    static let messagingTimeout: Float = 0.5

    func focusedTextInputState(in target: InsertionTarget) -> FocusedTextInputState {
        FocusedTextInputState.classifyForInsertion(
            probeFocusedElement(in: target, readsFrame: false).lookup,
            bundleIdentifier: target.bundleIdentifier
        )
    }

    /// @note p0-87
    static func exposeWebContent(of target: InsertionTarget) {
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// @note p0-88
    func probeFocusedElement(in target: InsertionTarget, readsFrame: Bool) -> FocusedElementProbe {
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
        // @note p0-89
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
        return FocusedElementProbe(element: element, lookup: lookup, frame: readsFrame ? frame(of: element) : nil)
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    /// @note p0-90
    private func frame(of element: AXUIElement) -> CGRect? {
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

    private func axValueAttribute(_ attribute: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        // @note p0-91
        return unsafeDowncast(value, to: AXValue.self)
    }
}
