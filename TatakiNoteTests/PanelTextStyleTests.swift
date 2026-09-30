import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelTextStyleTests {
    @Test("AC-5: 文字サイズは 10〜32、透明度は 0.4〜1.0 に丸め、NaN・無限大は初期値(14・1.0)")
    func clampsFontSizeAndOpacity() {
        #expect(PanelTextStyle.defaultFontSize == 14)
        #expect(PanelTextStyle.fontSizeRange == 10...32)
        #expect(PanelTextStyle.defaultOpacity == 1.0)
        #expect(PanelTextStyle.opacityRange == 0.4...1.0)

        let fontSizes: [(Double, Double)] = [
            (-5, 10), (0, 10), (9.99, 10), (10, 10), (14, 14), (15.5, 15.5), (32, 32), (32.01, 32), (1000, 32),
            (.nan, 14), (.infinity, 14), (-.infinity, 14),
        ]
        for (size, expected) in fontSizes {
            #expect(PanelTextStyle.clampedFontSize(size) == expected, "\(size)")
        }

        let opacities: [(Double, Double)] = [
            (-1, 0.4), (0, 0.4), (0.39, 0.4), (0.4, 0.4), (0.5, 0.5), (0.99, 0.99), (1.0, 1.0), (1.01, 1.0), (3.5, 1.0),
            (.nan, 1.0), (.infinity, 1.0), (-.infinity, 1.0),
        ]
        for (opacity, expected) in opacities {
            #expect(PanelTextStyle.clampedOpacity(opacity) == expected, "\(opacity)")
        }
    }

    @Test("AC-6: 名前が無い・空・先頭が「.」・Mac に無い名前ならシステムフォントで、指定の文字サイズ(丸めた値)になる")
    func fallsBackToSystemFont() {
        let systemFontName = NSFont.systemFont(ofSize: 14).fontName
        let names: [String?] = [
            nil,
            "",
            // @note p0-1001
            systemFontName,
            ".AppleSystemUIFont",
            ".NoSuchHiddenFont",
            "TatakiNoteNoSuchFont-Regular",
        ]
        let sizes: [(Double, CGFloat)] = [(14, 14), (20, 20), (5, 10), (100, 32), (.nan, 14)]

        for name in names {
            for (size, expectedSize) in sizes {
                let font = PanelTextStyle.font(name: name, size: size)
                let label = "\(name ?? "nil") / \(size)"
                #expect(font.fontName == NSFont.systemFont(ofSize: expectedSize).fontName, "\(label)")
                #expect(font.pointSize == expectedSize, "\(label)")
            }
        }
    }

    @Test("AC-6: Mac にある名前ならそのフォントで、指定の文字サイズ(丸めた値)になる")
    func usesInstalledFont() throws {
        let fixedPitchName = try #require(NSFont.userFixedPitchFont(ofSize: 14)?.fontName)
        let names = [fixedPitchName, "Helvetica"]
        let sizes: [(Double, CGFloat)] = [(14, 14), (20, 20), (5, 10), (100, 32), (.infinity, 14)]

        for name in names {
            for (size, expectedSize) in sizes {
                let font = PanelTextStyle.font(name: name, size: size)
                let label = "\(name) / \(size)"
                #expect(font.fontName == name, "\(label)")
                #expect(font.pointSize == expectedSize, "\(label)")
                #expect(font.fontName != NSFont.systemFont(ofSize: expectedSize).fontName, "\(label)")
            }
        }
    }
}
