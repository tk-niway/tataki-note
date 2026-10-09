import CoreGraphics
import Observation
import Testing
import os
@testable import TatakiNote

@MainActor
struct InsertionTargetOutlineGeometryTests {
    private let targetPID: pid_t = 101
    private let otherPID: pid_t = 202
    private let ownPID: pid_t = 303
    private let field = CGRect(x: 100, y: 100, width: 200, height: 40)
    private let targetWindowBounds = CGRect(x: 0, y: 0, width: 800, height: 600)

    private func targetWindow() -> OnScreenWindow {
        OnScreenWindow(processIdentifier: targetPID, layer: 0, bounds: targetWindowBounds)
    }

    private func outline(fieldFrame: CGRect? = nil, windows: [OnScreenWindow]) -> CGRect? {
        InsertionTargetOutlineGeometry.outlineRect(
            fieldFrame: fieldFrame ?? field,
            targetProcessIdentifier: targetPID,
            ownProcessIdentifier: ownPID,
            windows: windows
        )
    }

    @Test("AC-3: 手前に何も重ならないとき、入力欄の枠がそのまま枠線の枠になる")
    func fullyVisibleFieldKeepsItsFrame() {
        #expect(outline(windows: [targetWindow()]) == field)
    }

    @Test("AC-3: 入力欄がウィンドウからはみ出すと、ウィンドウとの重なりになる")
    func fieldIsClippedToItsWindow() {
        let clipped = CGRect(x: 650, y: 100, width: 200, height: 40)
        #expect(outline(fieldFrame: clipped, windows: [targetWindow()]) == CGRect(x: 650, y: 100, width: 150, height: 40))
    }

    @Test("AC-3: 手前の他のアプリの通常のウィンドウが少しでも重なると枠線を出さない")
    func slightOverlapByOtherAppHidesOutline() {
        let cover = OnScreenWindow(
            processIdentifier: otherPID,
            layer: 0,
            bounds: CGRect(x: 290, y: 130, width: 100, height: 100)
        )
        #expect(outline(windows: [cover, targetWindow()]) == nil)
    }

    @Test("AC-3: 他のアプリのウィンドウが入力欄のウィンドウより奥にある・重ならないときは枠線を出す")
    func windowsBehindOrApartDoNotHideOutline() {
        let behind = OnScreenWindow(processIdentifier: otherPID, layer: 0, bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let apart = OnScreenWindow(processIdentifier: otherPID, layer: 0, bounds: CGRect(x: 300, y: 100, width: 100, height: 100))
        let below = OnScreenWindow(processIdentifier: otherPID, layer: 0, bounds: CGRect(x: 100, y: 140, width: 200, height: 100))
        #expect(outline(windows: [targetWindow(), behind]) == field)
        #expect(outline(windows: [apart, below, targetWindow()]) == field)
    }

    @Test("AC-3: 自分のウィンドウは手前で重なっても枠線を消さない")
    func ownWindowDoesNotHideOutline() {
        let own = OnScreenWindow(processIdentifier: ownPID, layer: 0, bounds: field)
        #expect(outline(windows: [own, targetWindow()]) == field)
    }

    @Test("AC-3: 挿入先のアプリの別のウィンドウが手前で重なっても枠線を消さない")
    func sameAppWindowDoesNotHideOutline() {
        let partialOverlap = OnScreenWindow(
            processIdentifier: targetPID,
            layer: 0,
            bounds: CGRect(x: 250, y: 90, width: 100, height: 100)
        )
        #expect(outline(windows: [partialOverlap, targetWindow()]) == field)
    }

    @Test("AC-3: 通常でない階層のウィンドウが手前で重なっても枠線を消さない")
    func nonNormalLayerWindowDoesNotHideOutline() {
        let floating = OnScreenWindow(processIdentifier: otherPID, layer: 3, bounds: field)
        let menuBar = OnScreenWindow(processIdentifier: otherPID, layer: 25, bounds: field)
        #expect(outline(windows: [floating, targetWindow()]) == field)
        #expect(outline(windows: [menuBar, targetWindow()]) == field)
    }

    @Test("AC-3: 入力欄の中心を含む挿入先のウィンドウが一覧に無ければ枠線を出さない")
    func missingFieldWindowHidesOutline() {
        let farAway = OnScreenWindow(processIdentifier: targetPID, layer: 0, bounds: CGRect(x: 1000, y: 0, width: 400, height: 400))
        let otherApp = OnScreenWindow(processIdentifier: otherPID, layer: 0, bounds: targetWindowBounds)
        let ownWindow = OnScreenWindow(processIdentifier: ownPID, layer: 0, bounds: targetWindowBounds)
        #expect(outline(windows: []) == nil)
        #expect(outline(windows: [farAway, otherApp, ownWindow]) == nil)
        #expect(outline(fieldFrame: CGRect(x: 900, y: 100, width: 200, height: 40), windows: [targetWindow()]) == nil)
    }

    @Test("AC-3: 入力欄の幅か高さが 0 以下なら枠線を出さない")
    func emptyFieldHidesOutline() {
        #expect(outline(fieldFrame: CGRect(x: 100, y: 100, width: 0, height: 40), windows: [targetWindow()]) == nil)
        #expect(outline(fieldFrame: CGRect(x: 100, y: 100, width: 200, height: 0), windows: [targetWindow()]) == nil)
        #expect(outline(fieldFrame: CGRect(x: 100, y: 100, width: -5, height: 40), windows: [targetWindow()]) == nil)
    }

    @Test("AC-3: 枠線の窓の枠は、左下が原点に直して外側へ広げたものになる")
    func windowFrameFlipsAndOutsets() {
        let frame = InsertionTargetOutlineGeometry.windowFrame(
            outlineRect: CGRect(x: 10, y: 20, width: 100, height: 50),
            primaryScreenHeight: 1000,
            outset: 3
        )
        #expect(frame == CGRect(x: 7, y: 927, width: 106, height: 56))
    }

    @Test("AC-3: 枠線の場所のモデルは、変わらない枠では何も変えず、入れ替えると新しい枠になる")
    func outlineModelKeepsLatestRect() {
        let model = InsertionTargetOutlineModel()
        #expect(model.rect == nil)
        model.update(field)
        #expect(model.rect == field)
        model.update(field)
        #expect(model.rect == field)

        let notified = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = model.rect
        } onChange: {
            notified.withLock { $0 = true }
        }
        model.update(field)
        #expect(!notified.withLock { $0 })

        model.update(nil)
        #expect(model.rect == nil)
        #expect(notified.withLock { $0 })
    }
}
