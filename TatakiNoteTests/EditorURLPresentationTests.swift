import Foundation
import Testing
@testable import TatakiNote

struct EditorURLPresentationTests {
    private let url = NSRange(location: 10, length: 30)

    private func revealed(_ selection: NSRange, find: [NSRange] = []) -> Bool {
        EditorURLPresentation.isRevealed(url, selection: selection, findRanges: find)
    }

    // MARK: - 選択とカーソル

    @Test("AC-3: カーソルが URL の端を含めて触れている間は開き、離れると畳む")
    func caretTouchingOpens() {
        #expect(!revealed(NSRange(location: 9, length: 0)))
        #expect(revealed(NSRange(location: 10, length: 0)))
        #expect(revealed(NSRange(location: 25, length: 0)))
        #expect(revealed(NSRange(location: 40, length: 0)))
        #expect(!revealed(NSRange(location: 41, length: 0)))
    }

    @Test("AC-3: 選択が URL をまたぐときは畳み、端が URL に触れるときは開く")
    func selectionEnds() {
        #expect(!revealed(NSRange(location: 5, length: 40)))
        #expect(revealed(NSRange(location: 5, length: 5)))
        #expect(revealed(NSRange(location: 20, length: 25)))
        #expect(revealed(NSRange(location: 40, length: 5)))
        #expect(!revealed(NSRange(location: 0, length: 9)))
        #expect(!revealed(NSRange(location: 41, length: 5)))
    }

    @Test("AC-3: 選択が無い(NSNotFound)ときは畳む")
    func notFoundSelectionFolds() {
        #expect(!revealed(NSRange(location: NSNotFound, length: 0)))
    }

    // MARK: - 検索の一致

    @Test("AC-3: 検索の一致が URL に重なる間は開く")
    func findOverlapOpens() {
        #expect(revealed(NSRange(location: 0, length: 0), find: [NSRange(location: 30, length: 3)]))
        #expect(revealed(NSRange(location: 0, length: 0), find: [NSRange(location: 39, length: 5)]))
        #expect(revealed(NSRange(location: 0, length: 0), find: [NSRange(location: 0, length: 3), NSRange(location: 20, length: 1)]))
    }

    @Test("AC-3: 検索の一致が URL に接するだけで重ならないときは畳む")
    func findAdjacentFolds() {
        #expect(!revealed(NSRange(location: 0, length: 0), find: [NSRange(location: 40, length: 2)]))
        #expect(!revealed(NSRange(location: 0, length: 0), find: [NSRange(location: 8, length: 2)]))
        #expect(!revealed(NSRange(location: 0, length: 0), find: []))
    }

    // MARK: - 見え方を作る

    private let first = "https://github.com/tk-niway/tataki-note/issues/42"
    private let short = "https://a.com/x"

    private func sampleURLs() -> (text: NSString, urls: [EditorURL]) {
        let text = "\(short) と \(first) を見て" as NSString
        return (text, EditorURLDetector.urls(in: text))
    }

    @Test("AC-3: 短い URL は fold が nil で、長い URL の隠す範囲は文章の位置に直す")
    func makeShiftsRangesIntoText() {
        let (text, urls) = sampleURLs()
        #expect(urls.count == 2)
        let presentations = EditorURLPresentation.make(
            urls: urls,
            selection: NSRange(location: text.length, length: 0),
            findRanges: []
        )
        #expect(presentations.count == 2)
        #expect(presentations[0].url == urls[0])
        #expect(presentations[0].fold == nil)
        let origin = urls[1].range.location
        #expect(presentations[1].fold?.schemeRange == NSRange(location: origin, length: 8))
        #expect(presentations[1].fold?.middleRange == NSRange(location: origin + 19, length: 20))
    }

    @Test("AC-3: 開く URL は fold が nil、離れた URL は畳む")
    func makeLeavesRevealedUnfolded() {
        let (_, urls) = sampleURLs()
        let inside = NSRange(location: urls[1].range.location + 5, length: 0)
        let presentations = EditorURLPresentation.make(urls: urls, selection: inside, findRanges: [])
        #expect(presentations[1].fold == nil)

        let away = NSRange(location: 0, length: 0)
        #expect(EditorURLPresentation.make(urls: urls, selection: away, findRanges: [])[1].fold != nil)
    }

    @Test("AC-3: 検索の一致に重なる URL は開く")
    func makeOpensForFindMatch() {
        let (_, urls) = sampleURLs()
        let match = NSRange(location: urls[1].range.location + 3, length: 2)
        let presentations = EditorURLPresentation.make(
            urls: urls,
            selection: NSRange(location: 0, length: 0),
            findRanges: [match]
        )
        #expect(presentations[1].fold == nil)
    }

    @Test("AC-3: URL が無ければ空")
    func makeWithoutURLs() {
        #expect(EditorURLPresentation.make(urls: [], selection: NSRange(location: 0, length: 0), findRanges: []).isEmpty)
    }
}
