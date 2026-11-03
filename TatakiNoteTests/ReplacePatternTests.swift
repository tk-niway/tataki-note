import Foundation
import Testing
@testable import TatakiNote

struct ReplacePatternTests {
    private static func regexOptions(preservesCase: Bool = false) -> FindOptions {
        var options = FindOptions()
        options.isRegex = true
        options.preservesCase = preservesCase
        return options
    }

    private static func replaced(
        _ query: String,
        with template: String,
        in text: String,
        options: FindOptions
    ) -> String? {
        guard case let .found(matches, _) = TextSearch.search(query, options: options, in: text),
              let match = matches.first
        else { return nil }
        return ReplacePattern.replacement(for: match, in: text as NSString, template: template, options: options)
    }

    @Test("AC-6: 正規表現がオフなら置換語をそのまま使う")
    func plainTemplateIsLiteral() {
        let replaced = Self.replaced("a", with: "$1\\n\\t$&", in: "a", options: FindOptions())
        #expect(replaced == "$1\\n\\t$&")
    }

    @Test("AC-6: $1〜$9 はグループの文字に置き換わる")
    func groupReferences() {
        #expect(Self.replaced("(\\w+)@(\\w+)", with: "$2 at $1", in: "a@b", options: Self.regexOptions()) == "b at a")
    }

    @Test("AC-6: $& と $0 は一致の全体になる")
    func wholeMatchReferences() {
        #expect(Self.replaced("b+", with: "[$&][$0]", in: "abbc", options: Self.regexOptions()) == "[bb][bb]")
    }

    @Test("AC-6: $$ は $ 1文字になり、$$1 は $1 の文字のまま残る")
    func dollarEscape() {
        #expect(Self.replaced("(a)", with: "$$", in: "a", options: Self.regexOptions()) == "$")
        #expect(Self.replaced("(a)", with: "$$1", in: "a", options: Self.regexOptions()) == "$1")
    }

    @Test("AC-6: \\n は改行、\\t はタブ、\\\\ は \\ になり、ほかの \\x はそのまま残る")
    func backslashEscapes() {
        #expect(Self.replaced("a", with: "x\\ny", in: "a", options: Self.regexOptions()) == "x\ny")
        #expect(Self.replaced("a", with: "x\\ty", in: "a", options: Self.regexOptions()) == "x\ty")
        #expect(Self.replaced("a", with: "x\\\\y", in: "a", options: Self.regexOptions()) == "x\\y")
        #expect(Self.replaced("a", with: "x\\qy", in: "a", options: Self.regexOptions()) == "x\\qy")
        #expect(Self.replaced("(a)", with: "\\$1", in: "a", options: Self.regexOptions()) == "\\$1")
    }

    @Test("AC-6: 末尾の \\ と $ はそのまま残る")
    func trailingBackslashAndDollar() {
        #expect(Self.replaced("a", with: "x\\", in: "a", options: Self.regexOptions()) == "x\\")
        #expect(Self.replaced("a", with: "x$", in: "a", options: Self.regexOptions()) == "x$")
    }

    @Test("AC-6: 2桁の番号は2桁として読み、グループが足りなければ下の桁を文字に戻す")
    func twoDigitReferences() {
        #expect(Self.replaced("(a)", with: "$12", in: "a", options: Self.regexOptions()) == "a2")
        #expect(Self.replaced("(a)", with: "$5", in: "a", options: Self.regexOptions()) == "$5")
        #expect(Self.replaced("(a)", with: "$55", in: "a", options: Self.regexOptions()) == "$55")
        let tenGroups = "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)"
        #expect(Self.replaced(tenGroups, with: "$10", in: "abcdefghij", options: Self.regexOptions()) == "j")
        #expect(Self.replaced(tenGroups, with: "$01", in: "abcdefghij", options: Self.regexOptions()) == "abcdefghij1")
    }

    @Test("AC-6: 一致しなかったグループは空文字になる")
    func unmatchedGroupIsEmpty() {
        #expect(Self.replaced("(a)|(b)", with: "[$1][$2]", in: "b", options: Self.regexOptions()) == "[][b]")
    }

    @Test("AC-6: \\u と \\l は直後のグループの最初の1文字を大文字・小文字にする")
    func caseOperationsOnFirstCharacter() {
        #expect(Self.replaced("(\\w+)", with: "\\u$1", in: "foo", options: Self.regexOptions()) == "Foo")
        #expect(Self.replaced("(\\w+)", with: "\\l$1", in: "FOO", options: Self.regexOptions()) == "fOO")
    }

    @Test("AC-6: \\U と \\L は直後のグループ全体を大文字・小文字にする")
    func caseOperationsOnWholeGroup() {
        #expect(Self.replaced("(\\w+) (\\w+)", with: "\\U$1\\E $2", in: "foo bar", options: Self.regexOptions()) == "FOO\\E bar")
        #expect(Self.replaced("(\\w+) (\\w+)", with: "\\L$1 \\U$2", in: "FOO bar", options: Self.regexOptions()) == "foo BAR")
        #expect(Self.replaced("(\\w+)", with: "\\u\\L$1", in: "fOO", options: Self.regexOptions()) == "Foo")
    }

    @Test("AC-6: 大文字・小文字の指定は直後のグループにだけ掛かる")
    func caseOperationAppliesToNextGroupOnly() {
        #expect(Self.replaced("(\\w)(\\w)", with: "\\U$1$2", in: "ab", options: Self.regexOptions()) == "Ab")
        #expect(Self.replaced("(\\w)(\\w)", with: "\\ux$1$2", in: "ab", options: Self.regexOptions()) == "xAb")
    }

    @Test("AC-7: 一致が先頭だけ大文字なら置換語の先頭を大文字にする")
    func preservesCapitalizedMatch() {
        #expect(ReplacePattern.preservingCase(of: "Foo", in: "bar") == "Bar")
    }

    @Test("AC-7: 一致が全部大文字なら置換語も全部大文字にする")
    func preservesUppercaseMatch() {
        #expect(ReplacePattern.preservingCase(of: "FOO", in: "bar") == "BAR")
    }

    @Test("AC-7: 一致が全部小文字なら置換語も全部小文字にする")
    func preservesLowercaseMatch() {
        #expect(ReplacePattern.preservingCase(of: "foo", in: "Bar") == "bar")
    }

    @Test("AC-7: 一致が先頭だけ小文字の混在なら置換語の先頭を小文字にする")
    func preservesLowerFirstOfMixedMatch() {
        #expect(ReplacePattern.preservingCase(of: "fOo", in: "Bar") == "bar")
    }

    @Test("AC-7: - 区切りは区切りごとに合わせる")
    func preservesCasePerHyphenPart() {
        #expect(ReplacePattern.preservingCase(of: "Foo-Bar", in: "baz-qux") == "Baz-Qux")
        #expect(ReplacePattern.preservingCase(of: "FOO-bar", in: "baz-qux") == "BAZ-qux")
        #expect(ReplacePattern.preservingCase(of: "foo-Bar", in: "baz-qux") == "baz-Qux")
    }

    @Test("AC-7: _ 区切りは区切りごとに合わせる")
    func preservesCasePerUnderscorePart() {
        #expect(ReplacePattern.preservingCase(of: "Foo_Bar", in: "baz_qux") == "Baz_Qux")
    }

    @Test("AC-7: 区切りの数が違えば区切りごとには合わせない")
    func differentSeparatorCountFallsBack() {
        #expect(ReplacePattern.preservingCase(of: "Foo-Bar", in: "baz") == "Baz")
        #expect(ReplacePattern.preservingCase(of: "Foo-Bar", in: "a-b-c") == "A-b-c")
    }

    @Test("AC-7: 一致が空か置換語が空ならそのまま")
    func emptyInputsAreKept() {
        #expect(ReplacePattern.preservingCase(of: "", in: "Bar") == "Bar")
        #expect(ReplacePattern.preservingCase(of: "Foo", in: "") == "")
    }

    @Test("AC-7: 大文字と小文字を保持するがオンだと、置換の文字列に反映される")
    func replacementPreservesCaseWhenOn() {
        var options = FindOptions()
        options.preservesCase = true
        #expect(Self.replaced("foo", with: "bar", in: "Foo", options: options) == "Bar")
        #expect(Self.replaced("foo", with: "bar", in: "FOO", options: options) == "BAR")
        #expect(Self.replaced("foo", with: "Bar", in: "foo", options: options) == "bar")
    }

    @Test("AC-7: 大文字と小文字を保持するがオフなら置換語のまま")
    func replacementKeepsTemplateWhenOff() {
        #expect(Self.replaced("foo", with: "bar", in: "FOO", options: FindOptions()) == "bar")
    }

    @Test("AC-7: 正規表現の置換語を解釈した後の文字列に、大文字と小文字の保持が掛かる")
    func preserveCaseAppliesAfterExpansion() {
        let options = Self.regexOptions(preservesCase: true)
        #expect(Self.replaced("F(o+)", with: "b$1", in: "Foo", options: options) == "Boo")
    }
}
