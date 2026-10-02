import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelPlacementTests {
    private let screenA = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
    private let screenB = ScreenGeometry(
        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055)
    )
    private let screenC = ScreenGeometry(
        frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: -1080, width: 1920, height: 1055)
    )

    @Test("AC-6: 横に並んだ2画面で、マウスのある画面を選び、境界は右の画面・右端はどの画面にも無い扱い")
    func sideBySideScreens() {
        let screens = [screenA, screenB]
        let cases: [(CGPoint, ScreenGeometry)] = [
            (CGPoint(x: 700, y: 450), screenA),
            (CGPoint(x: 2000, y: 500), screenB),
            (CGPoint(x: 1440, y: 450), screenB),
            (CGPoint(x: 0, y: 450), screenA),
            (CGPoint(x: 3360, y: 450), screenA),
        ]

        for (location, expected) in cases {
            #expect(PanelPlacement.screenContainingMouse(location, in: screens) == expected, "\(location)")
        }
    }

    @Test("AC-6: 縦に並んだ2画面で、境界は下の画面・上端はその画面・下端はどの画面にも無い扱い")
    func stackedScreens() {
        let screens = [screenA, screenC]
        let cases: [(CGPoint, ScreenGeometry)] = [
            (CGPoint(x: 100, y: 450), screenA),
            (CGPoint(x: 100, y: -500), screenC),
            (CGPoint(x: 100, y: 0), screenC),
            (CGPoint(x: 100, y: 900), screenA),
            (CGPoint(x: 100, y: -1080), screenA),
        ]

        for (location, expected) in cases {
            #expect(PanelPlacement.screenContainingMouse(location, in: screens) == expected, "\(location)")
        }
    }

    @Test("AC-6: どの画面の外でも先頭の画面、画面が無ければ決めない")
    func outsideAllScreensAndNoScreens() {
        #expect(PanelPlacement.screenContainingMouse(CGPoint(x: -5000, y: -5000), in: [screenB, screenA]) == screenB)
        #expect(PanelPlacement.screenContainingMouse(CGPoint(x: 100, y: 100), in: []) == nil)
    }

    @Test("AC-7: 収まる大きさなら可視領域の中央に置き、原点は整数")
    func centersWithinVisibleFrame() {
        let size = CGSize(width: 520, height: 340)

        let frame = PanelPlacement.centeredFrame(size: size, in: CGRect(x: 0, y: 0, width: 1440, height: 875))
        #expect(frame.size == size)
        #expect(frame.origin.x == 460)
        #expect(frame.origin.y == frame.origin.y.rounded())
        #expect(abs(frame.midY - 437.5) <= 0.5)

        let shifted = CGRect(x: 1440, y: 70, width: 1921, height: 985)
        let shiftedFrame = PanelPlacement.centeredFrame(size: size, in: shifted)
        #expect(shiftedFrame.size == size)
        #expect(shiftedFrame.origin.x == shiftedFrame.origin.x.rounded())
        #expect(shiftedFrame.origin.y == shiftedFrame.origin.y.rounded())
        #expect(abs(shiftedFrame.midX - shifted.midX) <= 0.5)
        #expect(abs(shiftedFrame.midY - shifted.midY) <= 0.5)
        #expect(shifted.contains(shiftedFrame))
    }

    @Test("AC-7: 可視領域より大きいときは収まるように縮めて中央に置く")
    func shrinksToFitVisibleFrame() {
        let visible = CGRect(x: 100, y: -1055, width: 400, height: 300)

        let frame = PanelPlacement.centeredFrame(size: CGSize(width: 520, height: 340), in: visible)
        #expect(frame == visible)

        let wide = PanelPlacement.centeredFrame(size: CGSize(width: 520, height: 200), in: visible)
        #expect(wide.width == 400)
        #expect(wide.height == 200)
        #expect(wide.origin.x == 100)
        #expect(wide.origin.y == -1005)
    }

    // MARK: - 設定の方式での画面の選び方

    @Test("AC-5: 挿入先のウィンドウがある画面では、ウィンドウとの重なりが最も大きい画面を選ぶ")
    func targetWindowChoosesLargestOverlap() {
        let screens = [screenA, screenB, screenC]
        let mouseOnA = CGPoint(x: 700, y: 450)
        let cases: [(CGRect, ScreenGeometry, String)] = [
            (CGRect(x: 2000, y: 200, width: 800, height: 600), screenB, "B の中"),
            (CGRect(x: 1300, y: 200, width: 800, height: 600), screenB, "A と B にまたがり B が大きい"),
            (CGRect(x: 800, y: 200, width: 800, height: 600), screenA, "A と B にまたがり A が大きい"),
            (CGRect(x: 100, y: -700, width: 800, height: 800), screenC, "A と C にまたがり C が大きい"),
        ]

        for (window, expected, label) in cases {
            let chosen = PanelPlacement.screen(
                for: .targetWindow,
                screens: screens,
                mouseLocation: mouseOnA,
                targetWindowFrame: window
            )
            #expect(chosen == expected, "\(label)")
        }
    }

    @Test("AC-5: ウィンドウが分からないか、どの画面とも重ならないときは、マウスのある画面を選ぶ")
    func targetWindowFallsBackToMouseScreen() {
        let screens = [screenA, screenB]
        let mouseOnB = CGPoint(x: 2000, y: 500)
        let windows: [(CGRect?, String)] = [
            (nil, "ウィンドウが分からない"),
            (CGRect(x: 5000, y: 5000, width: 400, height: 300), "どの画面とも重ならない"),
            (CGRect(x: 0, y: 900, width: 400, height: 300), "A の上の辺に接するだけ"),
        ]

        for (window, label) in windows {
            let chosen = PanelPlacement.screen(
                for: .targetWindow,
                screens: screens,
                mouseLocation: mouseOnB,
                targetWindowFrame: window
            )
            #expect(chosen == screenB, "\(label)")
        }
    }

    @Test("AC-6: メインの画面では先頭の画面を、マウスのある画面ではマウスのある画面を選ぶ(ウィンドウの位置は見ない)")
    func mainAndMouseModes() {
        let screens = [screenA, screenB, screenC]
        let windowOnC = CGRect(x: 100, y: -900, width: 400, height: 300)
        let mouseCases: [(CGPoint, ScreenGeometry)] = [
            (CGPoint(x: 700, y: 450), screenA),
            (CGPoint(x: 2000, y: 500), screenB),
            (CGPoint(x: 100, y: -500), screenC),
        ]

        for (mouse, mouseScreen) in mouseCases {
            let main = PanelPlacement.screen(for: .main, screens: screens, mouseLocation: mouse, targetWindowFrame: windowOnC)
            #expect(main == screenA, "\(mouse)")
            let byMouse = PanelPlacement.screen(for: .mouse, screens: screens, mouseLocation: mouse, targetWindowFrame: windowOnC)
            #expect(byMouse == mouseScreen, "\(mouse)")
        }

        let reordered = PanelPlacement.screen(
            for: .main,
            screens: [screenB, screenA],
            mouseLocation: CGPoint(x: 700, y: 450),
            targetWindowFrame: nil
        )
        #expect(reordered == screenB)
    }

    @Test("AC-5, AC-6: 画面が無ければ、どの方式でも決めない")
    func noScreensForAnyMode() {
        for mode in PanelScreen.allCases {
            let chosen = PanelPlacement.screen(
                for: mode,
                screens: [],
                mouseLocation: CGPoint(x: 100, y: 100),
                targetWindowFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
            #expect(chosen == nil, "\(mode)")
        }
    }

    // MARK: - 「入力欄の近く」

    @Test("AC-9: 「入力欄の近く」は「挿入先のウィンドウがある画面」と同じ画面を選ぶ(重なりの最も大きい画面、枠が無い・重ならなければマウスのある画面)")
    func nearFocusedFieldChoosesSameScreenAsTargetWindow() {
        let screens = [screenA, screenB, screenC]
        let mouseOnB = CGPoint(x: 2000, y: 500)
        let cases: [(CGRect?, ScreenGeometry, String)] = [
            (CGRect(x: 2000, y: 200, width: 800, height: 600), screenB, "B の中"),
            (CGRect(x: 800, y: 200, width: 800, height: 600), screenA, "A と B にまたがり A が大きい"),
            (CGRect(x: 100, y: -700, width: 800, height: 800), screenC, "A と C にまたがり C が大きい"),
            (nil, screenB, "ウィンドウが分からない"),
            (CGRect(x: 5000, y: 5000, width: 400, height: 300), screenB, "どの画面とも重ならない"),
            (CGRect(x: 0, y: 900, width: 400, height: 300), screenB, "A の上の辺に接するだけ"),
        ]

        for (window, expected, label) in cases {
            let nearFocusedField = PanelPlacement.screen(
                for: .nearFocusedField,
                screens: screens,
                mouseLocation: mouseOnB,
                targetWindowFrame: window
            )
            let targetWindow = PanelPlacement.screen(
                for: .targetWindow,
                screens: screens,
                mouseLocation: mouseOnB,
                targetWindowFrame: window
            )
            #expect(nearFocusedField == expected, "\(label)")
            #expect(nearFocusedField == targetWindow, "\(label)")
        }

        let noScreen = PanelPlacement.screen(
            for: .nearFocusedField,
            screens: [],
            mouseLocation: mouseOnB,
            targetWindowFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        #expect(noScreen == nil)
    }

    @Test("AC-9: 挿入先の窓の枠を取るのは「挿入先のウィンドウがある画面」と「入力欄の近く」だけ")
    func usesTargetWindowFrameOnlyForWindowBasedModes() {
        for mode in PanelScreen.allCases {
            let expected: Bool
            switch mode {
            case .targetWindow, .nearFocusedField:
                expected = true
            case .mouse, .main:
                expected = false
            }
            #expect(mode.usesTargetWindowFrame == expected, "\(mode)")
        }
    }

    @Test("AC-7: Quartz の座標(左上が原点)の枠を、左下が原点の画面の座標に直す")
    func convertsQuartzToCocoa() {
        let primaryHeight: CGFloat = 900
        let cases: [(CGRect, CGRect)] = [
            (CGRect(x: 0, y: 0, width: 400, height: 300), CGRect(x: 0, y: 600, width: 400, height: 300)),
            (CGRect(x: 100, y: 600, width: 400, height: 300), CGRect(x: 100, y: 0, width: 400, height: 300)),
            (CGRect(x: 100, y: 1000, width: 400, height: 300), CGRect(x: 100, y: -400, width: 400, height: 300)),
            (CGRect(x: -500, y: -800, width: 400, height: 300), CGRect(x: -500, y: 1400, width: 400, height: 300)),
        ]

        for (quartz, expected) in cases {
            #expect(PanelPlacement.cocoaFrame(fromQuartz: quartz, primaryScreenHeight: primaryHeight) == expected, "\(quartz)")
        }
    }
}
