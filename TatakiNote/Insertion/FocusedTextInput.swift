import ApplicationServices

/// 挿入先のアプリで、キー入力を受ける要素(フォーカスのある要素)が文章の入力欄か。
enum FocusedTextInputState: Equatable {
    case textInput
    case notTextInput
    case unknown
}

/// フォーカスのある要素を問い合わせた結果。
enum FocusedElementLookup: Equatable {
    case element(role: String?, subrole: String?, isSelectedTextRangeSettable: Bool)
    case noFocusedElement
    case unavailable
}

extension FocusedTextInputState {
    static let textInputRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    static let nonTextInputRoles: Set<String> = [
        "AXWebArea",
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXLink",
        "AXList", "AXOutline", "AXTable", "AXBrowser", "AXRow", "AXCell",
        "AXScrollArea", "AXImage", "AXSlider", "AXTabGroup", "AXStaticText",
    ]

    static let unknownMeansNotTextInputBundleIdentifiers: Set<String> = ["com.apple.finder"]

    static let secureTextFieldSubrole = "AXSecureTextField"

    static func classify(_ lookup: FocusedElementLookup) -> FocusedTextInputState {
        switch lookup {
        case .unavailable:
            return .unknown
        case .noFocusedElement:
            return .notTextInput
        case .element(let role, _, let isSelectedTextRangeSettable):
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

/// フォーカスのある要素を1回の問い合わせでまとめて取った結果。
struct FocusedElementProbe {
    let element: AXUIElement?
    let lookup: FocusedElementLookup
    let frame: CGRect?

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

/// アクセシビリティ API で、挿入先のアプリのフォーカスのある要素を調べる。
struct AXFocusedTextInputInspector: FocusedTextInputInspecting, FocusedElementProbing {
    static let messagingTimeout: Float = 0.5

    func focusedTextInputState(in target: InsertionTarget) -> FocusedTextInputState {
        FocusedTextInputState.classifyForInsertion(
            probeFocusedElement(in: target, readsFrame: false).lookup,
            bundleIdentifier: target.bundleIdentifier
        )
    }

    /// Web の中身をアクセシビリティの仕組みに出すよう、挿入先のアプリに頼み、その結果を返す。
    @discardableResult
    static func exposeWebContent(of target: InsertionTarget) -> AXError {
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

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
        return unsafeDowncast(value, to: AXValue.self)
    }
}
