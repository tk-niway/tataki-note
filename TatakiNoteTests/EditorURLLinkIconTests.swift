import AppKit
import Testing
@testable import TatakiNote

struct EditorURLLinkIconTests {
    @Test("AC-31: アイコンの矩形は左端が minX、上下の中央が文字の高さの中央")
    func rectIsCenteredOnTheTextHeight() {
        let first = EditorURLLinkIcon.rect(minX: 10, baselineY: 20, ascender: 13, descender: -3, size: CGSize(width: 16, height: 12))
        #expect(first == CGRect(x: 10, y: 9, width: 16, height: 12))

        let second = EditorURLLinkIcon.rect(minX: 0, baselineY: 0, ascender: 10, descender: -2, size: CGSize(width: 8, height: 8))
        #expect(second == CGRect(x: 0, y: -8, width: 8, height: 8))

        let empty = EditorURLLinkIcon.rect(minX: 5, baselineY: 30, ascender: 12, descender: 0, size: .zero)
        #expect(empty == CGRect(x: 5, y: 24, width: 0, height: 0))
    }

    @Test("AC-31: アイコンの後ろのすき間はフォントサイズの 1/4")
    func gapIsAQuarterOfThePointSize() {
        #expect(EditorURLLinkIcon.gap(pointSize: 14) == 3.5)
        #expect(EditorURLLinkIcon.gap(pointSize: 20) == 5)
        #expect(EditorURLLinkIcon.gap(pointSize: 0) == 0)
    }

    @Test("AC-31: アイコンの大きさはフォントサイズが大きいほど大きい")
    func sizeGrowsWithThePointSize() throws {
        let small = try #require(EditorURLLinkIcon.size(pointSize: 14))
        let large = try #require(EditorURLLinkIcon.size(pointSize: 20))

        #expect(small.width > 0)
        #expect(small.height > 0)
        #expect(large.height > small.height)
        #expect(large.width > small.width)
    }

    @Test("AC-31: 色を付けた画像が作れる")
    func imageIsMadeWithTheSize() throws {
        let image = try #require(EditorURLLinkIcon.image(pointSize: 14, color: .linkColor))
        let size = try #require(EditorURLLinkIcon.size(pointSize: 14))

        #expect(image.size == size)
    }
}
