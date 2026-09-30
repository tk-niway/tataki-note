import CoreGraphics

/// @note p0-210
enum AutoShowTrigger: Equatable {
    /// @note p0-211
    case focusChanged
    /// @note p0-212
    case userClick
}

/// @note p0-213
struct AutoShowInput: Equatable {
    var mode: AutoShowMode
    var selectedApps: [AutoShowApp]
    var isAccessibilityTrusted: Bool
    /// @note p0-214
    var isPanelPresented: Bool
    /// @note p0-215
    var isFrontmostOwnApp: Bool
    var frontmostBundleIdentifier: String?
    var focusState: FocusedTextInputState
    var focusedSubrole: String?
    var trigger: AutoShowTrigger
    /// @note p0-216
    var isSameElementAsLastShown: Bool
    /// @note p0-217
    var isJustActivated: Bool
    /// @note p0-218
    var isJustDismissed: Bool
    /// @note p0-219
    var isClickInsideFocusedElement: Bool
}

/// @note p0-220
enum AutoShowDecision {
    /// @note p0-221
    static func shouldShow(_ input: AutoShowInput) -> Bool {
        // @note p0-222
        if input.mode == .off {
            return false
        }
        // @note p0-223
        if !input.isAccessibilityTrusted {
            return false
        }
        // @note p0-224
        if input.isPanelPresented {
            return false
        }
        // @note p0-225
        if input.isFrontmostOwnApp {
            return false
        }
        // @note p0-226
        if input.mode == .selectedApps
            && !AutoShowApp.contains(input.selectedApps, bundleIdentifier: input.frontmostBundleIdentifier) {
            return false
        }
        // @note p0-227
        if input.focusState != .textInput {
            return false
        }
        // @note p0-228
        if input.focusedSubrole == FocusedTextInputState.secureTextFieldSubrole {
            return false
        }
        switch input.trigger {
        case .userClick:
            // @note p0-229
            return input.isClickInsideFocusedElement
        case .focusChanged:
            // @note p0-230
            if input.isSameElementAsLastShown {
                return false
            }
            // @note p0-231
            if input.isJustActivated || input.isJustDismissed {
                return false
            }
            // @note p0-232
            return true
        }
    }

    /// @note p0-233
    static func shouldWatch(
        mode: AutoShowMode,
        selectedApps: [AutoShowApp],
        isAccessibilityTrusted: Bool,
        isOwnApp: Bool,
        bundleIdentifier: String?
    ) -> Bool {
        if mode == .off || !isAccessibilityTrusted || isOwnApp {
            return false
        }
        if mode == .selectedApps && !AutoShowApp.contains(selectedApps, bundleIdentifier: bundleIdentifier) {
            return false
        }
        return true
    }

    /// @note p0-234
    static func accessibilityPoint(fromCocoa point: CGPoint, primaryScreenFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenFrame.maxY - point.y)
    }
}
