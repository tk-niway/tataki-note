import Foundation
import Testing
@testable import TatakiNote

struct TextSearchTests {
    private static func locations(
        _ query: String,
        options: FindOptions = FindOptions(),
        in text: String,
        limit: Int? = TextSearch.matchLimit
    ) -> [Int]? {
        guard case let .found(matches, _) = TextSearch.search(query, options: options, in: text, limit: limit) else {
            return nil
        }
        return matches.map(\.range.location)
    }

    @Test("AC-1: 既定では大文字と小文字を区別せず、一致を位置の順にすべて見つける")
    func defaultIgnoresCase() {
        #expect(Self.locations("foo", in: "Foo foo FOO") == [0, 4, 8])
    }

    @Test("AC-1: 一致の範囲は UTF-16 の位置で返る")
    func rangesAreUTF16() {
        guard case let .found(matches, isTruncated) = TextSearch.search("a", options: FindOptions(), in: "😀a") else {
            Issue.record("一致が返りません")
            return
        }
        #expect(matches.map(\.range) == [NSRange(location: 2, length: 1)])
        #expect(!isTruncated)
    }

    @Test("AC-1: 全角と半角は区別する")
    func fullWidthIsDistinctFromHalfWidth() {
        #expect(Self.locations("ＡＢ", in: "AB ＡＢ ab") == [3])
    }

    @Test("AC-1: ひらがなとカタカナ(半角カナも)は区別する")
    func hiraganaIsDistinctFromKatakana() {
        #expect(Self.locations("か", in: "か カ ｶ") == [0])
    }

    @Test("AC-1: 検索語が空なら一致なし")
    func emptyQueryHasNoQuery() {
        #expect(TextSearch.search("", options: FindOptions(), in: "abc") == .noQuery)
    }

    @Test("AC-1: 空の文章では 0 件")
    func emptyTextHasNoMatches() {
        #expect(TextSearch.search("x", options: FindOptions(), in: "") == .found([], isTruncated: false))
    }

    @Test("AC-1: 打ち切りの上限に達した後にまだ一致があれば打ち切りの印が付く")
    func truncatesAtLimit() {
        guard case let .found(matches, isTruncated) = TextSearch.search(
            "a", options: FindOptions(), in: "aaa", limit: 2
        ) else {
            Issue.record("一致が返りません")
            return
        }
        #expect(matches.count == 2)
        #expect(isTruncated)
    }

    @Test("AC-1: 上限ちょうどの件数なら打ち切りの印は付かない")
    func exactLimitIsNotTruncated() {
        guard case let .found(matches, isTruncated) = TextSearch.search(
            "a", options: FindOptions(), in: "aa", limit: 2
        ) else {
            Issue.record("一致が返りません")
            return
        }
        #expect(matches.count == 2)
        #expect(!isTruncated)
    }

    @Test("AC-1: limit が nil なら打ち切らない")
    func nilLimitDoesNotTruncate() {
        let text = String(repeating: "a", count: TextSearch.matchLimit + 5)
        guard case let .found(matches, isTruncated) = TextSearch.search(
            "a", options: FindOptions(), in: text, limit: nil
        ) else {
            Issue.record("一致が返りません")
            return
        }
        #expect(matches.count == TextSearch.matchLimit + 5)
        #expect(!isTruncated)
    }

    @Test("AC-1: 既定の上限は 19999 件")
    func defaultLimitIs19999() {
        let text = String(repeating: "a", count: TextSearch.matchLimit + 1)
        guard case let .found(matches, isTruncated) = TextSearch.search("a", options: FindOptions(), in: text) else {
            Issue.record("一致が返りません")
            return
        }
        #expect(TextSearch.matchLimit == 19_999)
        #expect(matches.count == 19_999)
        #expect(isTruncated)
    }

    @Test("AC-2: 大文字と小文字を区別するがオンだと、違う箇所は一致しない")
    func caseSensitiveSkipsOtherCase() {
        var options = FindOptions()
        options.isCaseSensitive = true
        #expect(Self.locations("foo", options: options, in: "Foo foo FOO") == [4])
    }

    @Test("AC-3: 単語単位がオンだと、前後が区切りの一致だけが残る")
    func wholeWordKeepsDelimitedMatches() {
        var options = FindOptions()
        options.isWholeWord = true
        #expect(Self.locations("foo", options: options, in: "foo foobar (foo) xfoo") == [0, 12])
    }

    @Test("AC-3: 単語単位がオンだと、日本語の語の一部は一致しない")
    func wholeWordSkipsPartOfJapaneseWord() {
        var options = FindOptions()
        options.isWholeWord = true
        #expect(Self.locations("日本", options: options, in: "日本語") == [])
    }

    @Test("AC-3: 単語単位がオンでも、文頭・文末・空白・改行に挟まれた一致は残る")
    func wholeWordAcceptsLineAndTextEdges() {
        var options = FindOptions()
        options.isWholeWord = true
        #expect(Self.locations("foo", options: options, in: "foo\nfoo\r\nfoo\tfoo") == [0, 4, 9, 13])
    }

    @Test("AC-3: 単語単位の判定は一致の前後の文字と、一致の端の文字の区切りで決まる")
    func wholeWordBoundaryRules() {
        let text = "ab-cd x-y" as NSString
        #expect(TextSearch.isWholeWordMatch(NSRange(location: 0, length: 2), in: text))
        #expect(TextSearch.isWholeWordMatch(NSRange(location: 3, length: 2), in: text))
        #expect(!TextSearch.isWholeWordMatch(NSRange(location: 1, length: 2), in: text))
        #expect(TextSearch.isWholeWordMatch(NSRange(location: 6, length: 2), in: text))
        #expect(!TextSearch.isWholeWordMatch(NSRange(location: 1, length: 0), in: text))
    }

    @Test("AC-4: 正規表現がオフだと記号もそのままの文字として探す")
    func plainSearchEscapesSymbols() {
        #expect(Self.locations("a.c", in: "abc a.c") == [4])
    }

    @Test("AC-4: 正規表現がオンだと検索語を正規表現として探す")
    func regexSearchUsesPattern() {
        var options = FindOptions()
        options.isRegex = true
        #expect(Self.locations("a.c", options: options, in: "abc a.c") == [0, 4])
    }

    @Test("AC-4: 正規表現の ^ は行ごとの先頭に一致する")
    func caretMatchesEachLine() {
        var options = FindOptions()
        options.isRegex = true
        #expect(Self.locations("^b", options: options, in: "ab\nbc") == [3])
    }

    @Test("AC-4: 正規表現の $ は行ごとの末尾に一致する")
    func dollarMatchesEachLineEnd() {
        var options = FindOptions()
        options.isRegex = true
        #expect(Self.locations("b$", options: options, in: "ab\nbc\nb") == [1, 6])
    }

    @Test("AC-4: 正規表現の \\n で改行をまたいで一致する")
    func regexMatchesAcrossNewline() {
        var options = FindOptions()
        options.isRegex = true
        #expect(Self.locations("b\\nb", options: options, in: "ab\nbc") == [1])
    }

    @Test("AC-4: 正規表現の . は改行に一致しない")
    func dotDoesNotMatchNewline() {
        var options = FindOptions()
        options.isRegex = true
        #expect(Self.locations("a.b", options: options, in: "a\nb a-b") == [4])
    }

    @Test("AC-4: 正規表現がオフで検索語に改行があると、改行をまたいで一致する")
    func plainSearchMatchesAcrossNewline() {
        #expect(Self.locations("b\nb", in: "ab\nbc") == [1])
    }

    @Test("AC-4: 長さ 0 の一致も含み、キャプチャの範囲を返す")
    func zeroLengthMatchesAndGroups() {
        var options = FindOptions()
        options.isRegex = true
        #expect(Self.locations("^", options: options, in: "a\nb") == [0, 2])

        guard case let .found(matches, _) = TextSearch.search("(a)|(b)", options: options, in: "b") else {
            Issue.record("一致が返りません")
            return
        }
        #expect(matches.count == 1)
        #expect(matches[0].groups[0] == NSRange(location: 0, length: 1))
        #expect(matches[0].groups[1].location == NSNotFound)
        #expect(matches[0].groups[2] == NSRange(location: 0, length: 1))
    }

    @Test("AC-5: 正規表現が正しくないと、落ちずに正規表現のエラーの結果になる")
    func invalidRegexReturnsInvalidPattern() {
        var options = FindOptions()
        options.isRegex = true
        #expect(TextSearch.search("(", options: options, in: "abc") == .invalidPattern)
        #expect(TextSearch.search("(", options: options, in: "") == .invalidPattern)
        #expect(TextSearch.search("[a-", options: options, in: "abc") == .invalidPattern)
    }

    @Test("AC-5: 正規表現がオフなら ( もそのままの文字として探せる")
    func plainParenthesisIsNotInvalid() {
        #expect(Self.locations("(", in: "a(b") == [1])
    }
}
