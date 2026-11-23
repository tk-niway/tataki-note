import Foundation
import Testing
@testable import TatakiNote

struct EditorURLDetectorTests {
    private func detect(_ text: String) -> [EditorURL] {
        EditorURLDetector.urls(in: text as NSString)
    }

    private func texts(_ text: String) -> [String] {
        detect(text).map(\.text)
    }

    // MARK: - 始まりと終わり

    @Test("AC-1: ASCII 以外の文字で URL は止まり、範囲は UTF-16 で文章の位置を指す")
    func stopsAtNonASCII() {
        let text = "見て https://example.com/a。次"
        let urls = detect(text)
        #expect(urls.map(\.text) == ["https://example.com/a"])
        #expect(urls.first?.range == NSRange(location: 3, length: 21))
        #expect((text as NSString).substring(with: urls[0].range) == "https://example.com/a")
    }

    @Test("AC-1: 空白と改行で URL は止まる")
    func stopsAtWhitespace() {
        #expect(texts("https://a.com/x y") == ["https://a.com/x"])
        #expect(texts("https://a.com/x\nz") == ["https://a.com/x"])
    }

    @Test("AC-1: URL に使えない記号 <>\"{}|\\^` で止まる")
    func stopsAtInvalidSymbols() {
        for symbol in ["<", ">", "\"", "{", "}", "|", "\\", "^", "`"] {
            #expect(texts("https://a.com/x\(symbol)y") == ["https://a.com/x"])
        }
    }

    @Test("AC-1: http と https を大文字小文字を問わずに検出する")
    func detectsSchemeCaseInsensitively() {
        #expect(texts("HTTPS://EXAMPLE.COM") == ["HTTPS://EXAMPLE.COM"])
        #expect(texts("Http://a.com") == ["Http://a.com"])
        #expect(texts("http://a.com") == ["http://a.com"])
    }

    @Test("AC-1: クエリ・断片・記号を含む URL を丸ごと取る")
    func keepsQueryAndFragment() {
        let url = "https://example.com/a/b?x=1&y=%E3%81%82#top"
        #expect(texts("見て \(url) 次") == [url])
    }

    // MARK: - 末尾

    @Test("AC-1: 末尾の句読点を含めない")
    func trimsTrailingPunctuation() {
        #expect(texts("https://example.com/a.") == ["https://example.com/a"])
        #expect(texts("https://example.com/a,") == ["https://example.com/a"])
        #expect(texts("https://example.com/a:") == ["https://example.com/a"])
        #expect(texts("https://example.com/a;") == ["https://example.com/a"])
        #expect(texts("https://example.com/a!?") == ["https://example.com/a"])
        #expect(texts("https://example.com/a'.") == ["https://example.com/a"])
        #expect(texts("https://example.com/a.,") == ["https://example.com/a"])
    }

    @Test("AC-1: 対になっていない閉じ括弧を含めない")
    func trimsUnpairedClosingBrackets() {
        #expect(texts("(https://example.com/a)") == ["https://example.com/a"])
        #expect(texts("[a](https://example.com/x)") == ["https://example.com/x"])
        #expect(texts("[https://example.com/a]") == ["https://example.com/a"])
        #expect(texts("(https://example.com/a).") == ["https://example.com/a"])
    }

    @Test("AC-1: 対になっている括弧は含める")
    func keepsPairedBrackets() {
        #expect(texts("https://en.wikipedia.org/wiki/Swift_(language)") == ["https://en.wikipedia.org/wiki/Swift_(language)"])
        #expect(texts("https://en.wikipedia.org/wiki/Swift_(language).") == ["https://en.wikipedia.org/wiki/Swift_(language)"])
        #expect(texts("https://a.com/x[1]") == ["https://a.com/x[1]"])
    }

    @Test("AC-1: ASCII 以外で止まったとき、末尾の開き括弧を外す")
    func trimsTrailingOpeningBracketAfterNonASCII() {
        #expect(texts("https://ja.wikipedia.org/wiki/Swift_(言語)") == ["https://ja.wikipedia.org/wiki/Swift_"])
        #expect(texts("https://a.com/x[あ]") == ["https://a.com/x"])
    }

    // MARK: - 対象外

    @Test("AC-1: ほかのスキーム・裸のドメイン・メールアドレスは検出しない")
    func ignoresOtherForms() {
        #expect(texts("ftp://example.com").isEmpty)
        #expect(texts("example.com").isEmpty)
        #expect(texts("www.example.com/path").isEmpty)
        #expect(texts("a@example.com").isEmpty)
        #expect(texts("mailto:a@example.com").isEmpty)
    }

    @Test("AC-1: 英数字に続く http は始まりにしない")
    func ignoresSchemeAfterAlphanumeric() {
        #expect(texts("xhttps://e.com").isEmpty)
        #expect(texts("1http://e.com").isEmpty)
        #expect(texts("x http://e.com") == ["http://e.com"])
        #expect(texts("あhttps://e.com") == ["https://e.com"])
    }

    @Test("AC-1: ホストの無いものと空の文章は検出しない")
    func ignoresWithoutHost() {
        #expect(texts("https://").isEmpty)
        #expect(texts("http://").isEmpty)
        #expect(texts("https:///a").isEmpty)
        #expect(texts("https://?a").isEmpty)
        #expect(texts("https://.").isEmpty)
        #expect(texts("").isEmpty)
        #expect(texts("http").isEmpty)
        #expect(texts("https:/").isEmpty)
    }

    // MARK: - 複数

    @Test("AC-1: 複数の URL を前から順に、重ならずに返す")
    func returnsMultipleInOrder() {
        let urls = detect("https://a.com https://b.com")
        #expect(urls.map(\.text) == ["https://a.com", "https://b.com"])
        #expect(urls[0].range == NSRange(location: 0, length: 13))
        #expect(urls[1].range == NSRange(location: 14, length: 13))
    }

    @Test("AC-1: URL の中の http:// は新しい URL にしない")
    func doesNotNestURLs() {
        #expect(texts("https://a.com/?u=http://b.com") == ["https://a.com/?u=http://b.com"])
    }

    @Test("AC-1: 絵文字などサロゲートペアの後の範囲も UTF-16 で正しい")
    func rangesAreUTF16AfterSurrogatePairs() {
        let text = "😀 https://a.com"
        let urls = detect(text)
        #expect(urls.count == 1)
        #expect(urls.first?.range == NSRange(location: 3, length: 13))
        #expect((text as NSString).substring(with: urls[0].range) == "https://a.com")
    }

    // MARK: - 範囲版

    private let rangedSample = "前置き https://example.com/a(b)c 中\nhttp://x.jp/path?q=1#f, と😀 https://example.com/docs/2026/11/some-page.\n\nabchttps://no.example 後"

    private func paragraphBoundaries(of text: NSString) -> [Int] {
        var boundaries = [0]
        var index = 0
        while index < text.length {
            index = NSMaxRange(text.paragraphRange(for: NSRange(location: index, length: 0)))
            boundaries.append(index)
        }
        return boundaries
    }

    @Test("AC-2: 段落の境目にそろえた範囲の結果は、全文の結果のうち範囲に始まりのあるものと同じ")
    func rangeMatchesWholeResultsStartingInRange() {
        let text = rangedSample as NSString
        let whole = EditorURLDetector.urls(in: text)
        #expect(!whole.isEmpty)
        let boundaries = paragraphBoundaries(of: text)
        for start in boundaries {
            for end in boundaries where end >= start {
                let range = NSRange(location: start, length: end - start)
                let expected = whole.filter { NSLocationInRange($0.range.location, range) }
                #expect(EditorURLDetector.urls(in: text, range: range) == expected, "範囲 \(range)")
            }
        }
    }

    @Test("AC-2: 範囲の外の文字は無いものとして扱い、位置は文章全体の位置になる")
    func rangeIgnoresOutsideAndReportsWholeTextLocations() {
        let text = "abchttps://a.com https://b.com" as NSString
        let urls = EditorURLDetector.urls(in: text, range: NSRange(location: 3, length: 27))
        #expect(urls.map(\.text) == ["https://a.com", "https://b.com"])
        #expect(urls.map(\.range) == [NSRange(location: 3, length: 13), NSRange(location: 17, length: 13)])
        #expect(urls.allSatisfy { text.substring(with: $0.range) == $0.text })
    }

    @Test("AC-2: 範囲が空・範囲が文章の端・文章より外へはみ出すときも位置が正しい")
    func rangeAtEdgesAndEmpty() {
        let text = "https://a.com\nx https://b.com" as NSString
        #expect(EditorURLDetector.urls(in: text, range: NSRange(location: 4, length: 0)).isEmpty)
        #expect(EditorURLDetector.urls(in: "" as NSString, range: NSRange(location: 0, length: 0)).isEmpty)
        let head = EditorURLDetector.urls(in: text, range: NSRange(location: 0, length: 14))
        #expect(head.map(\.range) == [NSRange(location: 0, length: 13)])
        let tail = EditorURLDetector.urls(in: text, range: NSRange(location: 14, length: 100))
        #expect(tail.map(\.range) == [NSRange(location: 16, length: 13)])
        #expect(tail.map(\.text) == ["https://b.com"])
        #expect(EditorURLDetector.urls(in: text, range: NSRange(location: 100, length: 5)).isEmpty)
    }

    @Test("AC-2: サロゲートペアの後ろから始まる範囲の URL の位置が UTF-16 で正しい")
    func rangeAfterSurrogatePair() {
        let text = "😀\n😀 https://a.com" as NSString
        let urls = EditorURLDetector.urls(in: text, range: NSRange(location: 3, length: text.length - 3))
        #expect(urls.map(\.range) == [NSRange(location: 6, length: 13)])
        #expect(text.substring(with: urls[0].range) == "https://a.com")
    }

    @Test("AC-2: 範囲の始まりの直前の英数字は見ない")
    func rangeDoesNotLookBeforeItsStart() {
        let text = "abhttps://a.com" as NSString
        #expect(EditorURLDetector.urls(in: text).isEmpty)
        #expect(EditorURLDetector.urls(in: text, range: NSRange(location: 2, length: 13)).map(\.text) == ["https://a.com"])
    }

    @Test("AC-2: 範囲を全体にした結果は、全文の検出と同じ")
    func wholeRangeEqualsWholeDetection() {
        let text = rangedSample as NSString
        #expect(EditorURLDetector.urls(in: text, range: NSRange(location: 0, length: text.length)) == EditorURLDetector.urls(in: text))
    }
}
