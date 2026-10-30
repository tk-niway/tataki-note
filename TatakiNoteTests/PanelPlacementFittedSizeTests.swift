import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelPlacementFittedSizeTests {
    private let visible = CGRect(x: 100, y: 50, width: 1000, height: 800)
    private var screen: ScreenGeometry {
        ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1200, height: 900), visibleFrame: visible)
    }

    @Test("AC-4: fittedSize は可視領域より小さければそのまま、大きい向きだけ可視領域に合わせる")
    func fittedSizeClampsEachDimension() {
        #expect(PanelPlacement.fittedSize(CGSize(width: 400, height: 300), in: visible) == CGSize(width: 400, height: 300))
        #expect(PanelPlacement.fittedSize(CGSize(width: 1500, height: 300), in: visible) == CGSize(width: 1000, height: 300))
        #expect(PanelPlacement.fittedSize(CGSize(width: 400, height: 900), in: visible) == CGSize(width: 400, height: 800))
        #expect(PanelPlacement.fittedSize(CGSize(width: 1500, height: 900), in: visible) == CGSize(width: 1000, height: 800))
        #expect(PanelPlacement.fittedSize(CGSize(width: 1000, height: 800), in: visible) == CGSize(width: 1000, height: 800))
    }

    @Test("AC-4: centeredFrame は詰めた大きさを可視領域の中央に置く")
    func centeredFrameUsesFittedSize() {
        #expect(
            PanelPlacement.centeredFrame(size: CGSize(width: 400, height: 300), in: visible)
                == CGRect(x: 400, y: 300, width: 400, height: 300)
        )
        #expect(
            PanelPlacement.centeredFrame(size: CGSize(width: 1500, height: 900), in: visible)
                == CGRect(x: 100, y: 50, width: 1000, height: 800)
        )
        #expect(
            PanelPlacement.centeredFrame(size: CGSize(width: 1500, height: 300), in: visible)
                == CGRect(x: 100, y: 300, width: 1000, height: 300)
        )
    }

    @Test("AC-4: PanelOpenPlacement.frame は中央に置くときも入力欄の近くに置くときも詰めた大きさを使う")
    func openPlacementFrameUsesFittedSize() {
        #expect(
            PanelOpenPlacement.frame(size: CGSize(width: 1500, height: 900), on: screen, mode: .mouse, fieldFrame: nil)
                == CGRect(x: 100, y: 50, width: 1000, height: 800)
        )
        let fieldFrame = CGRect(x: 300, y: 400, width: 200, height: 30)
        #expect(
            PanelOpenPlacement.frame(
                size: CGSize(width: 1500, height: 200),
                on: screen,
                mode: .nearFocusedField,
                fieldFrame: fieldFrame
            ) == CGRect(x: 100, y: 192, width: 1000, height: 200)
        )
    }

    @Test("AC-4: PanelSizing.openingSize は基準の大きさを可視領域に詰める")
    func openingSizeUsesFittedSize() {
        let sizing = PanelSizing()
        sizing.beginOpening(defaultSize: CGSize(width: 1500, height: 900), hasText: true)
        #expect(sizing.openingSize(in: visible) == CGSize(width: 1000, height: 800))
        #expect(sizing.openingSize(in: visible) == PanelPlacement.fittedSize(sizing.baseSize, in: visible))

        sizing.beginOpening(defaultSize: CGSize(width: 500, height: 400), hasText: true)
        #expect(sizing.openingSize(in: visible) == CGSize(width: 500, height: 400))
    }
}
