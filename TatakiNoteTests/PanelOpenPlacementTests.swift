import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelOpenPlacementTests {
    private let screenA = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
    private let screenB = ScreenGeometry(
        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055)
    )
    private let size = CGSize(width: 520, height: 340)

    // MARK: - 入力欄の近く

    @Test("AC-10: 入力欄の下に 8pt 空けて左端をそろえて出す")
    func placesBelowField() {
        let placed = PanelOpenPlacement.nearField(
            size: size,
            fieldFrame: CGRect(x: 100, y: 500, width: 400, height: 30),
            visibleFrame: screenA.visibleFrame
        )

        #expect(placed == CGRect(x: 100, y: 152, width: 520, height: 340))
        #expect(500 - placed.maxY == PanelOpenPlacement.fieldGap)
    }

    @Test("AC-10: 下に収まらなければ入力欄の上に 8pt 空けて出す")
    func placesAboveFieldWhenBelowDoesNotFit() {
        let placed = PanelOpenPlacement.nearField(
            size: size,
            fieldFrame: CGRect(x: 100, y: 100, width: 400, height: 30),
            visibleFrame: screenA.visibleFrame
        )

        #expect(placed == CGRect(x: 100, y: 138, width: 520, height: 340))
    }

    @Test("AC-10: 上にも下にも収まらなければ(入力欄が可視の高さいっぱい・メニューバーの帯・Dock の上)、可視領域の中央に出す")
    func centersWhenNeitherFits() {
        let cases: [(CGRect, CGRect, String)] = [
            (CGRect(x: 100, y: 0, width: 400, height: 875), screenA.visibleFrame, "可視の高さいっぱい"),
            (CGRect(x: 100, y: 884, width: 200, height: 16), screenA.visibleFrame, "メニューバーの帯"),
            (CGRect(x: 100, y: 20, width: 200, height: 30), CGRect(x: 0, y: 70, width: 1440, height: 805), "Dock の上"),
        ]

        for (field, visibleFrame, label) in cases {
            let placed = PanelOpenPlacement.nearField(size: size, fieldFrame: field, visibleFrame: visibleFrame)
            #expect(placed == PanelPlacement.centeredFrame(size: size, in: visibleFrame), "\(label)")
        }
    }

    @Test("AC-10: 左端をそろえると可視領域からはみ出すときは、内側へずらす")
    func shiftsHorizontallyIntoVisibleFrame() {
        let right = PanelOpenPlacement.nearField(
            size: size,
            fieldFrame: CGRect(x: 1200, y: 500, width: 200, height: 30),
            visibleFrame: screenA.visibleFrame
        )
        #expect(right.minX == 920)
        #expect(right.maxX == screenA.visibleFrame.maxX)

        let left = PanelOpenPlacement.nearField(
            size: size,
            fieldFrame: CGRect(x: -50, y: 500, width: 200, height: 30),
            visibleFrame: screenA.visibleFrame
        )
        #expect(left.minX == 0)
    }

    // MARK: - 開く枠

    @Test("AC-10: 「入力欄の近く」で入力欄がその画面にあれば入力欄の近く、別の画面にあれば選んだ画面の中央")
    func frameUsesFieldOnlyOnTheSameScreen() {
        let fieldOnA = CGRect(x: 100, y: 500, width: 400, height: 30)
        #expect(
            PanelOpenPlacement.frame(size: size, on: screenA, mode: .nearFocusedField, fieldFrame: fieldOnA)
                == CGRect(x: 100, y: 152, width: 520, height: 340)
        )

        let fieldOnB = CGRect(x: 2000, y: 500, width: 400, height: 30)
        #expect(
            PanelOpenPlacement.frame(size: size, on: screenA, mode: .nearFocusedField, fieldFrame: fieldOnB)
                == PanelPlacement.centeredFrame(size: size, in: screenA.visibleFrame)
        )
    }

    @Test("AC-11: 入力欄の枠が無いときは、どの方式でも今と同じ可視領域の中央に出す。ほかの方式は入力欄の枠を使わない")
    func frameWithoutFieldIsCentered() {
        let centered = PanelPlacement.centeredFrame(size: size, in: screenA.visibleFrame)
        for mode in PanelScreen.allCases {
            #expect(PanelOpenPlacement.frame(size: size, on: screenA, mode: mode, fieldFrame: nil) == centered, "\(mode)")
        }

        let field = CGRect(x: 100, y: 500, width: 400, height: 30)
        for mode in PanelScreen.allCases where mode != .nearFocusedField {
            #expect(PanelOpenPlacement.frame(size: size, on: screenA, mode: mode, fieldFrame: field) == centered, "\(mode)")
        }
    }

    @Test("AC-8: 開く大きさが可視領域に収まらなければ収まるよう縮めて開き、渡した大きさ・保っている大きさそのものは変えない")
    func frameShrinksToVisibleFrame() {
        let huge = CGSize(width: 4000, height: 4000)
        #expect(
            PanelOpenPlacement.frame(size: huge, on: screenA, mode: .mouse, fieldFrame: nil)
                == CGRect(x: 0, y: 0, width: 1440, height: 875)
        )
        #expect(
            PanelOpenPlacement.frame(
                size: CGSize(width: 1600, height: 1000),
                on: screenA,
                mode: .nearFocusedField,
                fieldFrame: CGRect(x: 100, y: 500, width: 400, height: 30)
            ) == CGRect(x: 0, y: 0, width: 1440, height: 875)
        )

        let sizing = PanelSizing()
        sizing.beginOpening(defaultSize: CGSize(width: 520, height: 340))
        sizing.userDidResize(from: CGSize(width: 520, height: 340), to: CGSize(width: 1100, height: 700))
        let smallScreen = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1024, height: 768),
            visibleFrame: CGRect(x: 0, y: 0, width: 1024, height: 743)
        )
        let placed = PanelOpenPlacement.frame(size: sizing.baseSize, on: smallScreen, mode: .mouse, fieldFrame: nil)
        #expect(placed.size == CGSize(width: 1024, height: 700))
        #expect(smallScreen.visibleFrame.contains(placed))
        #expect(sizing.heldSize == CGSize(width: 1100, height: 700))
        #expect(sizing.baseSize == CGSize(width: 1100, height: 700))
    }

    // MARK: - 画面の選び方

    @Test("AC-10: 「入力欄の近く」で入力欄の枠があれば、マウス・挿入先のウィンドウの位置によらず入力欄と重なりの大きい画面")
    func screenFollowsField() {
        let chosen = PanelOpenPlacement.screen(
            mode: .nearFocusedField,
            screens: [screenA, screenB],
            mouseLocation: CGPoint(x: 700, y: 450),
            targetWindowFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            fieldFrame: CGRect(x: 1300, y: 500, width: 400, height: 30)
        )

        #expect(chosen == screenB)
    }

    @Test("AC-11: 入力欄の枠が無い・どの画面とも重ならない・ほかの方式のときは、今と同じ画面の選び方(挿入先のウィンドウの画面 → マウスの画面)")
    func screenFallsBackToPanelPlacement() {
        let screens = [screenA, screenB]
        let mouseOnB = CGPoint(x: 2000, y: 500)
        let windowOnA = CGRect(x: 100, y: 100, width: 800, height: 600)
        let fields: [CGRect?] = [nil, CGRect(x: 5000, y: 5000, width: 400, height: 30)]

        for mode in PanelScreen.allCases {
            for window in [windowOnA, nil] as [CGRect?] {
                let expected = PanelPlacement.screen(
                    for: mode,
                    screens: screens,
                    mouseLocation: mouseOnB,
                    targetWindowFrame: window
                )
                for field in fields {
                    let chosen = PanelOpenPlacement.screen(
                        mode: mode,
                        screens: screens,
                        mouseLocation: mouseOnB,
                        targetWindowFrame: window,
                        fieldFrame: field
                    )
                    #expect(chosen == expected, "\(mode) \(String(describing: window)) \(String(describing: field))")
                }
            }
        }

        #expect(
            PanelOpenPlacement.screen(
                mode: .nearFocusedField,
                screens: screens,
                mouseLocation: mouseOnB,
                targetWindowFrame: windowOnA,
                fieldFrame: nil
            ) == screenA
        )
        #expect(
            PanelOpenPlacement.screen(
                mode: .nearFocusedField,
                screens: screens,
                mouseLocation: mouseOnB,
                targetWindowFrame: nil,
                fieldFrame: nil
            ) == screenB
        )

        #expect(
            PanelOpenPlacement.screen(
                mode: .mouse,
                screens: screens,
                mouseLocation: mouseOnB,
                targetWindowFrame: nil,
                fieldFrame: CGRect(x: 100, y: 500, width: 400, height: 30)
            ) == screenB
        )
    }

    // MARK: - 入力欄の枠

    @Test("AC-11: 入力欄の枠はアクセシビリティの座標から画面の座標(左下が原点)に直し、問い合わせは1回・枠を読む")
    func fieldFrameConvertsAccessibilityCoordinates() {
        let probe = FocusedElementProbeStub()
        probe.result = FocusedElementProbe(
            element: nil,
            lookup: WatcherFixture.textFieldLookup,
            frame: CGRect(x: 100, y: 20, width: 400, height: 30)
        )

        let frame = PanelOpenPlacement.fieldFrame(
            mode: .nearFocusedField,
            isTrusted: true,
            target: WatcherFixture.editor,
            probe: probe,
            primaryScreenHeight: 900
        )

        #expect(frame == CGRect(x: 100, y: 850, width: 400, height: 30))
        #expect(probe.targets == [WatcherFixture.editor])
        #expect(probe.readsFrameValues == [true])
    }

    @Test("AC-11: 入力欄以外にフォーカス・フォーカスが無い・アプリが答えない・アプリが位置を教えないときは、入力欄の枠を使わない")
    func fieldFrameIsNilWhenFieldIsUnknown() {
        let frame = CGRect(x: 100, y: 20, width: 400, height: 30)
        let results: [(FocusedElementProbe, String)] = [
            (FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil), "フォーカスが無い"),
            (FocusedElementProbe(element: nil, lookup: .unavailable, frame: nil), "アプリが答えない"),
            (FocusedElementProbe(element: nil, lookup: WatcherFixture.buttonLookup, frame: frame), "ボタン"),
            (FocusedElementProbe(element: nil, lookup: WatcherFixture.textFieldLookup, frame: nil), "位置を教えない"),
        ]

        for (result, label) in results {
            let probe = FocusedElementProbeStub()
            probe.result = result
            let fieldFrame = PanelOpenPlacement.fieldFrame(
                mode: .nearFocusedField,
                isTrusted: true,
                target: WatcherFixture.editor,
                probe: probe,
                primaryScreenHeight: 900
            )
            #expect(fieldFrame == nil, "\(label)")
            #expect(probe.targets.count == 1, "\(label)")
        }
    }

    @Test("AC-11: 許可が無い・挿入先が無い・ほかの方式のときは、入力欄を問い合わせない")
    func fieldFrameDoesNotProbeWhenNotNeeded() {
        let cases: [(PanelScreen, Bool, InsertionTarget?, String)] = [
            (.nearFocusedField, false, WatcherFixture.editor, "許可が無い"),
            (.nearFocusedField, true, nil, "挿入先が無い"),
            (.mouse, true, WatcherFixture.editor, "マウスのある画面"),
            (.targetWindow, true, WatcherFixture.editor, "挿入先のウィンドウがある画面"),
            (.main, true, WatcherFixture.editor, "メインの画面"),
        ]

        for (mode, isTrusted, target, label) in cases {
            let probe = FocusedElementProbeStub()
            probe.result = FocusedElementProbe(
                element: nil,
                lookup: WatcherFixture.textFieldLookup,
                frame: CGRect(x: 100, y: 20, width: 400, height: 30)
            )
            let fieldFrame = PanelOpenPlacement.fieldFrame(
                mode: mode,
                isTrusted: isTrusted,
                target: target,
                probe: probe,
                primaryScreenHeight: 900
            )
            #expect(fieldFrame == nil, "\(label)")
            #expect(probe.targets.isEmpty, "\(label)")
        }
    }
}
