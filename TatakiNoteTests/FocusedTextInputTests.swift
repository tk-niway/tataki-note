import Testing
@testable import TatakiNote

@MainActor
struct FocusedTextInputTests {
    @Test("文章の入力欄の役割なら入力欄")
    func textInputRoles() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
            #expect(FocusedTextInputState.classify(.element(role: role, subrole: nil, isSelectedTextRangeSettable: false)) == .textInput, "\(role)")
        }
    }

    @Test("選択範囲を変えられる要素は、役割にかかわらず入力欄(Web ページの contenteditable など)")
    func selectedTextRangeSettableIsTextInput() {
        #expect(FocusedTextInputState.classify(.element(role: "AXGroup", subrole: nil, isSelectedTextRangeSettable: true)) == .textInput)
        #expect(FocusedTextInputState.classify(.element(role: "AXWebArea", subrole: nil, isSelectedTextRangeSettable: true)) == .textInput)
        #expect(FocusedTextInputState.classify(.element(role: nil, subrole: nil, isSelectedTextRangeSettable: true)) == .textInput)
    }

    @Test("フォーカスのある要素が無い、または入力欄ではないと言い切れる役割なら、入力欄ではない")
    func notTextInput() {
        #expect(FocusedTextInputState.classify(.noFocusedElement) == .notTextInput)
        for role in ["AXWebArea", "AXButton", "AXList", "AXOutline", "AXTable", "AXScrollArea", "AXLink"] {
            #expect(FocusedTextInputState.classify(.element(role: role, subrole: nil, isSelectedTextRangeSettable: false)) == .notTextInput, "\(role)")
        }
    }

    @Test("問い合わせに答えない、役割が分からない、独自の描画のアプリが返しがちな役割なら、分からない(挿入する)")
    func unknown() {
        #expect(FocusedTextInputState.classify(.unavailable) == .unknown)
        #expect(FocusedTextInputState.classify(.element(role: nil, subrole: nil, isSelectedTextRangeSettable: false)) == .unknown)
        for role in ["AXGroup", "AXUnknown", "AXWindow"] {
            #expect(FocusedTextInputState.classify(.element(role: role, subrole: nil, isSelectedTextRangeSettable: false)) == .unknown, "\(role)")
        }
    }

    @Test("挿入の判定: Finder では、分からないを入力欄ではないとして扱う(デスクトップを選んで確定しても下書きに残る)")
    func finderUnknownIsNotTextInput() {
        let finder = "com.apple.finder"
        #expect(FocusedTextInputState.classifyForInsertion(.unavailable, bundleIdentifier: finder) == .notTextInput)
        for role in ["AXGroup", "AXUnknown", "AXWindow"] {
            #expect(FocusedTextInputState.classifyForInsertion(.element(role: role, subrole: nil, isSelectedTextRangeSettable: false), bundleIdentifier: finder) == .notTextInput, "\(role)")
        }
        // @note p0-877
        #expect(FocusedTextInputState.classifyForInsertion(.element(role: "AXTextField", subrole: nil, isSelectedTextRangeSettable: false), bundleIdentifier: finder) == .textInput)
        #expect(FocusedTextInputState.classifyForInsertion(.element(role: "AXGroup", subrole: nil, isSelectedTextRangeSettable: true), bundleIdentifier: finder) == .textInput)
    }

    @Test("挿入の判定: Finder 以外のアプリ・アプリが分からないときは、今までどおり分からない(挿入する)")
    func otherAppsKeepUnknown() {
        for bundleIdentifier in ["com.mitchellh.ghostty", "dev.warp.Warp-Stable", nil] as [String?] {
            #expect(FocusedTextInputState.classifyForInsertion(.unavailable, bundleIdentifier: bundleIdentifier) == .unknown, "\(String(describing: bundleIdentifier))")
            #expect(FocusedTextInputState.classifyForInsertion(.element(role: "AXGroup", subrole: nil, isSelectedTextRangeSettable: false), bundleIdentifier: bundleIdentifier) == .unknown, "\(String(describing: bundleIdentifier))")
        }
        #expect(FocusedTextInputState.classifyForInsertion(.noFocusedElement, bundleIdentifier: nil) == .notTextInput)
    }

    // MARK: - 自動表示

    @Test("AC-13: 挿入の判定は subrole を見ない(パスワード欄も今までどおり入力欄として挿入し、役割ごとの結果も同じ)")
    func classifyIgnoresSubrole() {
        let secure = FocusedTextInputState.secureTextFieldSubrole
        #expect(secure == "AXSecureTextField")
        #expect(FocusedTextInputState.classify(.element(role: "AXTextField", subrole: secure, isSelectedTextRangeSettable: false)) == .textInput)
        #expect(FocusedTextInputState.classify(.element(role: "AXTextField", subrole: secure, isSelectedTextRangeSettable: true)) == .textInput)

        let roles: [String?] = [
            nil, "AXTextField", "AXTextArea", "AXComboBox",
            "AXWebArea", "AXButton", "AXList", "AXLink",
            "AXGroup", "AXUnknown", "AXWindow",
        ]
        for role in roles {
            for isSettable in [false, true] {
                let withoutSubrole = FocusedTextInputState.classify(.element(role: role, subrole: nil, isSelectedTextRangeSettable: isSettable))
                for subrole in [secure, "AXSearchField", "AXUnknown"] {
                    #expect(
                        FocusedTextInputState.classify(.element(role: role, subrole: subrole, isSelectedTextRangeSettable: isSettable)) == withoutSubrole,
                        "\(String(describing: role)) \(subrole) \(isSettable)"
                    )
                }
            }
        }
    }
}
