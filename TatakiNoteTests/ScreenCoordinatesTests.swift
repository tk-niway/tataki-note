import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct ScreenCoordinatesTests {
    @Test("AC-5: cocoaRect は左上原点の枠を左下原点の枠に直し、直して戻すと元に戻る")
    func cocoaRectConvertsAndRoundTrips() {
        let topLeft = CGRect(x: 10, y: 20, width: 300, height: 100)
        let cocoa = ScreenCoordinates.cocoaRect(fromTopLeft: topLeft, primaryScreenHeight: 1000)
        #expect(cocoa == CGRect(x: 10, y: 880, width: 300, height: 100))
        #expect(ScreenCoordinates.cocoaRect(fromTopLeft: cocoa, primaryScreenHeight: 1000) == topLeft)
    }

    @Test("AC-5: topLeftPoint は左下原点の点を左上原点の点に直し、直して戻すと元に戻る")
    func topLeftPointConvertsAndRoundTrips() {
        let cocoa = CGPoint(x: 50, y: 200)
        let topLeft = ScreenCoordinates.topLeftPoint(fromCocoa: cocoa, primaryScreenHeight: 1000)
        #expect(topLeft == CGPoint(x: 50, y: 800))
        #expect(ScreenCoordinates.topLeftPoint(fromCocoa: topLeft, primaryScreenHeight: 1000) == cocoa)
    }

    @Test("AC-5: cocoaFrame と accessibilityPoint は共通の変換と同じ値を返す")
    func callersMatchSharedConversions() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 100)
        #expect(
            PanelPlacement.cocoaFrame(fromQuartz: rect, primaryScreenHeight: 900)
                == ScreenCoordinates.cocoaRect(fromTopLeft: rect, primaryScreenHeight: 900)
        )

        let point = CGPoint(x: 50, y: 200)
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(
            AutoShowDecision.accessibilityPoint(fromCocoa: point, primaryScreenFrame: primary)
                == ScreenCoordinates.topLeftPoint(fromCocoa: point, primaryScreenHeight: primary.maxY)
        )
        #expect(AutoShowDecision.accessibilityPoint(fromCocoa: point, primaryScreenFrame: primary) == CGPoint(x: 50, y: 700))
    }

    @Test("AC-5: primaryScreenFrame はメインの画面の枠を返す")
    func primaryScreenFrameIsFirstScreen() {
        #expect(ScreenCoordinates.primaryScreenFrame == NSScreen.screens.first?.frame)
    }
}
