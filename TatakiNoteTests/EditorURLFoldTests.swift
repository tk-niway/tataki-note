import Foundation
import Testing
@testable import TatakiNote

struct EditorURLFoldTests {
    private func display(_ url: String) -> String? {
        EditorURLFold.make(for: url)?.displayText(of: url)
    }

    // MARK: - 境目

    @Test("AC-2: 30 文字以下は畳まず、31 文字から畳む")
    func thresholdIsThirty() {
        let thirty = "https://example.com/abcdefghij"
        let thirtyOne = "https://example.com/abcdefghijk"
        #expect(thirty.utf16.count == 30)
        #expect(thirtyOne.utf16.count == 31)
        #expect(EditorURLFold.make(for: thirty) == nil)
        #expect(EditorURLFold.make(for: thirtyOne) != nil)
        #expect(EditorURLFold.foldThreshold == 30)
        #expect(EditorURLFold.tailMaxLength == 16)
        #expect(EditorURLFold.ellipsis == "…")
    }

    // MARK: - 見え方

    @Test("AC-2: ドメインと末尾の区切りを残して間を「…」にする")
    func keepsHostAndTail() {
        #expect(display("https://github.com/tk-niway/tataki-note/issues/42") == "github.com/…/issues/42")
    }

    @Test("AC-2: パスが 16 文字以下なら、スキームだけ隠す")
    func hidesOnlySchemeWhenPathIsShort() {
        #expect(display("https://example.com/abcdefghijk") == "example.com/abcdefghijk")
        #expect(display("https://very-long-subdomain.example.co.jp") == "very-long-subdomain.example.co.jp")
    }

    @Test("AC-2: 最後の区切りだけで 16 文字を超えるなら、パス全体を「…」にする")
    func ellipsisWhenLastSegmentIsTooLong() {
        #expect(display("https://example.com/abcdefghij1234567") == "example.com/…")
        #expect(display("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "www.youtube.com/…")
    }

    @Test("AC-2: 末尾の空の区切りも丸ごとの区切りとして数える")
    func trailingEmptySegmentCounts() {
        #expect(display("https://example.com/a/b/c/d/e/f/g/h/i/") == "example.com/…/b/c/d/e/f/g/h/i/")
    }

    @Test("AC-2: パスが無く ? か # で続くときは、ドメインの後ろを「…」にする")
    func ellipsisAfterHostForQueryOrFragment() {
        #expect(display("https://example.com?q=very-long-query-x") == "example.com…")
        #expect(display("https://example.com#section-with-a-long-name") == "example.com…")
    }

    @Test("AC-2: 区切りの長さがちょうど 16 のときは残し、17 のときは残さない")
    func tailLimitBoundary() {
        #expect(display("https://example.com/aaaaaaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb") == "example.com/…/bbbbbbbbbbbbbbbb")
        #expect(display("https://example.com/aaaaaaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbbb") == "example.com/…")
    }

    // MARK: - 隠す範囲

    @Test("AC-2: スキームの範囲は先頭から :// の後まで、間の範囲は「…」を描く位置を最後に持つ")
    func hiddenRanges() {
        let url = "https://github.com/tk-niway/tataki-note/issues/42"
        let fold = EditorURLFold.make(for: url)
        #expect(fold?.schemeRange == NSRange(location: 0, length: 8))
        #expect(fold?.middleRange == NSRange(location: 19, length: 20))
        #expect((url as NSString).substring(with: NSRange(location: 19, length: 20)) == "tk-niway/tataki-note")
    }

    @Test("AC-2: http:// のスキームの範囲は 7 文字")
    func httpSchemeRange() {
        let fold = EditorURLFold.make(for: "http://example.com/abcdefghijklmnopqrstuvwxyz")
        #expect(fold?.schemeRange == NSRange(location: 0, length: 7))
    }

    @Test("AC-2: 間が空になるときは間の範囲を持たない")
    func emptyMiddleIsNil() {
        let url = "https://example.com//bbbbbbbbbbbbbbbb"
        let fold = EditorURLFold.make(for: url)
        #expect(fold?.schemeRange == NSRange(location: 0, length: 8))
        #expect(fold?.middleRange == nil)
        #expect(fold?.displayText(of: url) == "example.com//bbbbbbbbbbbbbbbb")
    }

    @Test("AC-2: ホストだけのときは間の範囲が無い")
    func hostOnlyHasNoMiddle() {
        let fold = EditorURLFold.make(for: "https://very-long-subdomain.example.co.jp")
        #expect(fold?.schemeRange == NSRange(location: 0, length: 8))
        #expect(fold?.middleRange == nil)
    }
}
