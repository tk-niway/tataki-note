import ApplicationServices

/// 挿入先のアプリで、キー入力を受ける要素(フォーカスのある要素)が文章の入力欄か。
nonisolated enum FocusedTextInputState: Equatable {
    case textInput
    case notTextInput
    case unknown
}

/// フォーカスのある要素を問い合わせた結果。
nonisolated enum FocusedElementLookup: Equatable, Sendable {
    case element(role: String?, subrole: String?, isSelectedTextRangeSettable: Bool)
    case noFocusedElement
    case unavailable
}

nonisolated extension FocusedTextInputState {
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

    /// パスワード欄(subrole が AXSecureTextField)か。
    static func isSecureTextField(_ lookup: FocusedElementLookup) -> Bool {
        if case .element(_, let subrole, _) = lookup {
            return subrole == secureTextFieldSubrole
        }
        return false
    }
}
