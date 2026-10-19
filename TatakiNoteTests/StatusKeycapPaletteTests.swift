import AppKit
import Testing
@testable import TatakiNote

struct StatusKeycapPaletteTests {
    private static let previousFaceWhite = 0.29
    private static let previousEdgeOpacity = 0.15
    private static let previousShadowOpacity = 0.22

    private static func panelBackgroundWhite(appearanceName: NSAppearance.Name) throws -> Double {
        let appearance = try #require(NSAppearance(named: appearanceName))
        var white: Double?
        appearance.performAsCurrentDrawingAppearance {
            white = NSColor.textBackgroundColor
                .usingColorSpace(.genericGray)
                .map { Double($0.whiteComponent) }
        }
        return try #require(white)
    }

    @Test("AC-13: ダークでは面とパネルの背景の明るさの差が今より小さい")
    func darkFaceIsCloserToBackgroundThanBefore() throws {
        let background = try Self.panelBackgroundWhite(appearanceName: .darkAqua)
        let palette = StatusKeycapPalette.palette(isDark: true)

        let difference = abs(palette.faceWhite - background)
        let previousDifference = abs(Self.previousFaceWhite - background)
        #expect(difference < previousDifference)
    }

    @Test("AC-13: ライトでは面とパネルの背景の明るさの差が 0.06 以下")
    func lightFaceIsWithinSixHundredthsOfBackground() throws {
        let background = try Self.panelBackgroundWhite(appearanceName: .aqua)
        let palette = StatusKeycapPalette.palette(isDark: false)

        #expect(abs(palette.faceWhite - background) <= 0.06)
    }

    @Test("AC-13: 縁は 0 より濃く今より薄く、影は 0 以上で今より薄い", arguments: [true, false])
    func edgeAndShadowStayWithinRange(isDark: Bool) {
        let palette = StatusKeycapPalette.palette(isDark: isDark)

        #expect(palette.edgeOpacity > 0)
        #expect(palette.edgeOpacity < Self.previousEdgeOpacity)
        #expect(palette.shadowOpacity >= 0)
        #expect(palette.shadowOpacity < Self.previousShadowOpacity)
    }
}
