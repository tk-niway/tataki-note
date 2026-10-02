import CoreGraphics
import Testing
@testable import TatakiNote

@MainActor
struct AutoShowDecisionTests {
    private let chrome = AutoShowApp(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
    private let slack = AutoShowApp(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack")

    private func input(_ change: (inout AutoShowInput) -> Void = { _ in }) -> AutoShowInput {
        var input = AutoShowInput(
            mode: .allApps,
            selectedApps: [chrome],
            isAccessibilityTrusted: true,
            isPanelPresented: false,
            isFrontmostOwnApp: false,
            frontmostBundleIdentifier: "com.google.Chrome",
            focusState: .textInput,
            focusedSubrole: nil,
            trigger: .focusChanged,
            isSameElementAsLastShown: false,
            isJustActivated: false,
            isJustDismissed: false,
            isClickInsideFocusedElement: false
        )
        change(&input)
        return input
    }

    private func clickInput(_ change: (inout AutoShowInput) -> Void = { _ in }) -> AutoShowInput {
        input {
            $0.trigger = .userClick
            $0.isClickInsideFocusedElement = true
            change(&$0)
        }
    }

    @Test("AC-2: 「全アプリ」で、前面のアプリのフォーカスが入力欄に移ったら出す")
    func showsWhenAllAppsAndTextInputFocused() {
        #expect(AutoShowDecision.shouldShow(input()))
        #expect(AutoShowDecision.shouldShow(input { $0.selectedApps = [] }))
        #expect(AutoShowDecision.shouldShow(input { $0.frontmostBundleIdentifier = nil }))
        #expect(AutoShowDecision.shouldShow(input { $0.focusedSubrole = "AXSearchField" }))
    }

    @Test("AC-1: 自動表示が「オフ」なら出さない")
    func offDoesNotShow() {
        #expect(!AutoShowDecision.shouldShow(input { $0.mode = .off }))
        #expect(!AutoShowDecision.shouldShow(clickInput { $0.mode = .off }))
    }

    @Test("AC-3: 「選んだアプリのみ」では一覧に入っているアプリでだけ出し、入っていない・一覧が空・bundle identifier が分からないときは出さない")
    func selectedAppsShowsOnlyForListedApps() {
        #expect(AutoShowDecision.shouldShow(input { $0.mode = .selectedApps }))
        #expect(AutoShowDecision.shouldShow(input {
            $0.mode = .selectedApps
            $0.selectedApps = [slack, chrome]
        }))
        #expect(AutoShowDecision.shouldShow(clickInput { $0.mode = .selectedApps }))

        #expect(!AutoShowDecision.shouldShow(input {
            $0.mode = .selectedApps
            $0.selectedApps = [slack]
        }))
        #expect(!AutoShowDecision.shouldShow(input {
            $0.mode = .selectedApps
            $0.selectedApps = []
        }))
        #expect(!AutoShowDecision.shouldShow(input {
            $0.mode = .selectedApps
            $0.frontmostBundleIdentifier = nil
        }))
        #expect(!AutoShowDecision.shouldShow(clickInput {
            $0.mode = .selectedApps
            $0.selectedApps = [slack]
        }))
    }

    @Test("AC-4: フォーカスのある要素がパスワード欄(AXSecureTextField)なら、フォーカスの移り変わりでもクリックでも出さない")
    func secureTextFieldDoesNotShow() {
        #expect(!AutoShowDecision.shouldShow(input { $0.focusedSubrole = "AXSecureTextField" }))
        #expect(!AutoShowDecision.shouldShow(clickInput { $0.focusedSubrole = "AXSecureTextField" }))
    }

    @Test("AC-5: 入力欄でない・入力欄か分からない(.unknown)なら出さない")
    func nonTextInputAndUnknownDoNotShow() {
        for state in [FocusedTextInputState.notTextInput, .unknown] {
            #expect(!AutoShowDecision.shouldShow(input { $0.focusState = state }), "\(state)")
            #expect(!AutoShowDecision.shouldShow(clickInput { $0.focusState = state }), "\(state)")
        }
    }

    @Test("AC-6: アクセシビリティの許可が無いなら出さない")
    func untrustedDoesNotShow() {
        #expect(!AutoShowDecision.shouldShow(input { $0.isAccessibilityTrusted = false }))
        #expect(!AutoShowDecision.shouldShow(clickInput { $0.isAccessibilityTrusted = false }))
    }

    @Test("AC-7: パネルが開いている間は、フォーカスが移ってもクリックしても出さない")
    func presentedPanelDoesNotShowAgain() {
        #expect(!AutoShowDecision.shouldShow(input { $0.isPanelPresented = true }))
        #expect(!AutoShowDecision.shouldShow(clickInput { $0.isPanelPresented = true }))
    }

    @Test("AC-8: アプリが前面になった直後のフォーカスの通知や、最後に出したのと同じ要素への通知では出さない")
    func justActivatedDoesNotShow() {
        #expect(!AutoShowDecision.shouldShow(input { $0.isJustActivated = true }))
        #expect(!AutoShowDecision.shouldShow(input { $0.isSameElementAsLastShown = true }))
    }

    @Test("AC-9: パネルを閉じた直後のフォーカスの通知や、最後に出したのと同じ要素に当て直された通知では出さない")
    func justDismissedDoesNotShow() {
        #expect(!AutoShowDecision.shouldShow(input { $0.isJustDismissed = true }))
        #expect(!AutoShowDecision.shouldShow(input { $0.isSameElementAsLastShown = true }))
        #expect(!AutoShowDecision.shouldShow(input {
            $0.isSameElementAsLastShown = true
            $0.isJustDismissed = true
        }))
    }

    @Test("AC-10: 入力欄の枠の中のクリックなら、閉じた直後・同じ要素・前面になった直後でも出し、枠の外なら出さない")
    func clickInsideFocusedElementShows() {
        #expect(AutoShowDecision.shouldShow(clickInput()))
        #expect(AutoShowDecision.shouldShow(clickInput {
            $0.isSameElementAsLastShown = true
            $0.isJustDismissed = true
            $0.isJustActivated = true
        }))

        #expect(!AutoShowDecision.shouldShow(clickInput { $0.isClickInsideFocusedElement = false }))
        #expect(AutoShowDecision.shouldShow(input { $0.isClickInsideFocusedElement = false }))
    }

    @Test("AC-10: Cocoa の座標(左下が原点)を、アクセシビリティの座標(左上が原点)に直す")
    func accessibilityPointFlipsY() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

        #expect(AutoShowDecision.accessibilityPoint(fromCocoa: CGPoint(x: 10, y: 800), primaryScreenFrame: screen) == CGPoint(x: 10, y: 0))
        #expect(AutoShowDecision.accessibilityPoint(fromCocoa: CGPoint(x: 990, y: 0), primaryScreenFrame: screen) == CGPoint(x: 990, y: 800))
        #expect(AutoShowDecision.accessibilityPoint(fromCocoa: CGPoint(x: 500, y: 400), primaryScreenFrame: screen) == CGPoint(x: 500, y: 400))
        #expect(AutoShowDecision.accessibilityPoint(fromCocoa: CGPoint(x: 100, y: 700), primaryScreenFrame: screen) == CGPoint(x: 100, y: 100))
    }

    @Test("AC-11: 前面が TatakiNote 自身なら、フォーカスの移り変わりでもクリックでも出さない")
    func ownAppDoesNotShow() {
        #expect(!AutoShowDecision.shouldShow(input { $0.isFrontmostOwnApp = true }))
        #expect(!AutoShowDecision.shouldShow(clickInput { $0.isFrontmostOwnApp = true }))
    }

    @Test("AC-16: 見張るのは「全アプリ」と「選んだアプリのみ」で選んだアプリだけ")
    func shouldWatchOnlyTargetApps() {
        func shouldWatch(
            mode: AutoShowMode,
            selectedApps: [AutoShowApp],
            isAccessibilityTrusted: Bool = true,
            isOwnApp: Bool = false,
            bundleIdentifier: String?
        ) -> Bool {
            AutoShowDecision.shouldWatch(
                mode: mode,
                selectedApps: selectedApps,
                isAccessibilityTrusted: isAccessibilityTrusted,
                isOwnApp: isOwnApp,
                bundleIdentifier: bundleIdentifier
            )
        }

        #expect(shouldWatch(mode: .allApps, selectedApps: [], bundleIdentifier: "com.google.Chrome"))
        #expect(shouldWatch(mode: .allApps, selectedApps: [slack], bundleIdentifier: nil))
        #expect(shouldWatch(mode: .selectedApps, selectedApps: [slack, chrome], bundleIdentifier: "com.google.Chrome"))

        #expect(!shouldWatch(mode: .selectedApps, selectedApps: [slack], bundleIdentifier: "com.google.Chrome"))
        #expect(!shouldWatch(mode: .selectedApps, selectedApps: [], bundleIdentifier: "com.google.Chrome"))
        #expect(!shouldWatch(mode: .selectedApps, selectedApps: [chrome], bundleIdentifier: nil))
        #expect(!shouldWatch(mode: .off, selectedApps: [chrome], bundleIdentifier: "com.google.Chrome"))
        #expect(!shouldWatch(mode: .allApps, selectedApps: [], isAccessibilityTrusted: false, bundleIdentifier: "com.google.Chrome"))
        #expect(!shouldWatch(mode: .selectedApps, selectedApps: [chrome], isAccessibilityTrusted: false, bundleIdentifier: "com.google.Chrome"))
        #expect(!shouldWatch(mode: .allApps, selectedApps: [], isOwnApp: true, bundleIdentifier: "com.example.TatakiNote"))
        #expect(!shouldWatch(mode: .selectedApps, selectedApps: [chrome], isOwnApp: true, bundleIdentifier: "com.google.Chrome"))
    }
}
