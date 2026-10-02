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

    private func member(_ postScriptName: String, weight: Int, italic: Bool = false) -> [Any] {
        let traits: NSFontTraitMask = italic ? .italicFontMask : []
        return [postScriptName, "Face", NSNumber(value: weight), NSNumber(value: traits.rawValue)]
    }

    @Test("AC-8: ファミリーの標準の太さは、斜体でなく太さ 5 に最も近いもの。同じ近さなら細い方、斜体しか無ければ最初のもの、太さが取れないものは 5 として数える")
    func regularPostScriptNameIsRegularWeight() {
        let regular = PanelTextStyle.regularPostScriptName(members: [
            member("Regular-Italic", weight: 5, italic: true),
            member("Regular-Light", weight: 3),
            member("Regular-Regular", weight: 5),
            member("Regular-Bold", weight: 9),
        ])
        #expect(regular == "Regular-Regular")

        let threeSeven = PanelTextStyle.regularPostScriptName(members: [
            member("ThreeSeven-Bold", weight: 7), member("ThreeSeven-Light", weight: 3),
        ])
        #expect(threeSeven == "ThreeSeven-Light")

        let steps = PanelTextStyle.regularPostScriptName(
            members: [0, 1, 2, 3, 4, 6, 7, 8, 9].map { member("Steps-W\($0)", weight: $0) }
        )
        #expect(steps == "Steps-W4")

        let italicOnly = PanelTextStyle.regularPostScriptName(members: [
            member("ItalicOnly-BoldItalic", weight: 9, italic: true), member("ItalicOnly-Italic", weight: 5, italic: true),
        ])
        #expect(italicOnly == "ItalicOnly-BoldItalic")

        let noTraits = PanelTextStyle.regularPostScriptName(members: [
            member("NoTraits-Light", weight: 3), ["NoTraits-Plain"],
        ])
        #expect(noTraits == "NoTraits-Plain")
    }

    @Test("AC-8: 使える書体が無いファミリー(空・名前が文字列でない・空文字)は nil、先頭が「.」の書体は選ばない")
    func regularPostScriptNameSkipsUnusableMembers() {
        #expect(PanelTextStyle.regularPostScriptName(members: []) == nil)
        #expect(PanelTextStyle.regularPostScriptName(members: [
            [NSNumber(value: 1), "Face", NSNumber(value: 5), NSNumber(value: 0)], ["", "Face"],
        ]) == nil)
        #expect(PanelTextStyle.regularPostScriptName(members: [
            member(".AllHidden-Regular", weight: 5), member(".AllHidden-Bold", weight: 9),
        ]) == nil)
        #expect(PanelTextStyle.regularPostScriptName(members: [
            member(".Foo-Hidden", weight: 5), member("Foo-Light", weight: 3),
        ]) == "Foo-Light")
    }

    @Test("AC-3, AC-8, AC-9: 入力欄のフォントは、書体があればその書体、無ければ同じファミリーの標準の太さ、ファミリーも無ければシステムフォント")
    func resolvedFontFollowsFallbackOrder() throws {
        let menloMembers: (String) -> [[Any]]? = { family in
            family == "Menlo" ? [self.member("Menlo-Regular", weight: 5), self.member("Menlo-Bold", weight: 9)] : nil
        }
        let systemName = NSFont.systemFont(ofSize: 14).fontName

        let installed = try #require(PanelTextStyle.resolvedFont(
            name: "HiraginoSans-W6", familyName: "Hiragino Sans", size: 20, members: menloMembers
        ))
        #expect(installed.fontName == "HiraginoSans-W6")
        #expect(installed.pointSize == 20)

        let sameFamily = try #require(PanelTextStyle.resolvedFont(
            name: "Menlo-TatakiNoteNoSuchFace", familyName: "Menlo", size: 40, members: menloMembers
        ))
        #expect(sameFamily.fontName == "Menlo-Regular")
        #expect(sameFamily.pointSize == 32)

        let noFamily = PanelTextStyle.resolvedFont(
            name: "TatakiNoteNoSuchFont-Regular", familyName: "TatakiNoteNoSuchFamily", size: 14, members: menloMembers
        )
        #expect(noFamily == nil)
        let familyNameMissing = PanelTextStyle.resolvedFont(
            name: "TatakiNoteNoSuchFont-Regular", familyName: nil, size: 14, members: menloMembers
        )
        #expect(familyNameMissing == nil)
        let hiddenFamily = PanelTextStyle.resolvedFont(
            name: "TatakiNoteNoSuchFont-Regular", familyName: ".Menlo", size: 14, members: menloMembers
        )
        #expect(hiddenFamily == nil)

        for name in [nil, "", ".AppleSystemUIFont", ".SFNS-Bold"] as [String?] {
            #expect(PanelTextStyle.resolvedFont(name: name, familyName: "Menlo", size: 14, members: menloMembers) == nil, "\(name ?? "nil")")
        }

        let fallback = PanelTextStyle.font(name: "TatakiNoteNoSuchFont-Regular", familyName: "TatakiNoteNoSuchFamily", size: 5)
        #expect(fallback.fontName == NSFont.systemFont(ofSize: 10).fontName)
        #expect(fallback.fontName == systemName)
        #expect(fallback.pointSize == 10)

        let sameFamilyFont = PanelTextStyle.font(name: "Menlo-TatakiNoteNoSuchFace", familyName: "Menlo", size: 18)
        #expect(sameFamilyFont.fontName == "Menlo-Regular")
        #expect(sameFamilyFont.pointSize == 18)
    }

    @Test("AC-5: 名前が無い・空・先頭が「.」はシステムフォントの名前")
    func isSystemFontNameDetectsSystemNames() {
        #expect(PanelTextStyle.isSystemFontName(nil))
        #expect(PanelTextStyle.isSystemFontName(""))
        #expect(PanelTextStyle.isSystemFontName(".SFNS-Bold"))
        #expect(!PanelTextStyle.isSystemFontName("Menlo-Regular"))
    }
}
