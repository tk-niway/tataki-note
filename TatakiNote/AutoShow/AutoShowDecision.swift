import CoreGraphics

/// 自動表示のきっかけ。
enum AutoShowTrigger: Equatable {
    case focusChanged
    case userClick
}

/// 自動表示するかどうかを決めるのに要るもの(値だけ)。
struct AutoShowInput: Equatable {
    var mode: AutoShowMode
    var selectedApps: [AutoShowApp]
    var isAccessibilityTrusted: Bool
    var isPanelPresented: Bool
    var isFrontmostOwnApp: Bool
    var frontmostBundleIdentifier: String?
    var focusState: FocusedTextInputState
    var focusedSubrole: String?
    var trigger: AutoShowTrigger
    var isSameElementAsLastShown: Bool
    var isJustActivated: Bool
    var isJustDismissed: Bool
    var isClickInsideFocusedElement: Bool
    var isClickSuppressed: Bool
}

/// 入力欄が選ばれたときにパネルを自動で出すかの判定。
enum AutoShowDecision {
    static func shouldShow(_ input: AutoShowInput) -> Bool {
        if input.mode == .off {
            return false
        }
        if !input.isAccessibilityTrusted {
            return false
        }
        if input.isPanelPresented {
            return false
        }
        if input.isFrontmostOwnApp {
            return false
        }
        if input.mode == .selectedApps
            && !AutoShowApp.contains(input.selectedApps, bundleIdentifier: input.frontmostBundleIdentifier) {
            return false
        }
        if input.focusState != .textInput {
            return false
        }
        if input.focusedSubrole == FocusedTextInputState.secureTextFieldSubrole {
            return false
        }
        switch input.trigger {
        case .userClick:
            return input.isClickInsideFocusedElement && !input.isClickSuppressed
        case .focusChanged:
            if input.isSameElementAsLastShown {
                return false
            }
            if input.isJustActivated || input.isJustDismissed {
                return false
            }
            return true
        }
    }

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

    static func accessibilityPoint(fromCocoa point: CGPoint, primaryScreenFrame: CGRect) -> CGPoint {
        ScreenCoordinates.topLeftPoint(fromCocoa: point, primaryScreenHeight: primaryScreenFrame.maxY)
    }
}
