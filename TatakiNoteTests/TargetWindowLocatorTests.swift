import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct TargetWindowLocatorTests {
    private let targetPID: pid_t = 101
    private let otherPID: pid_t = 202

    /// @note p0-1101
    private func window(pid: pid_t, layer: Int, bounds: CGRect) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowBounds as String: bounds.dictionaryRepresentation,
        ]
    }

    @Test("AC-7: 前から順に、挿入先のプロセスで layer 0 の最初のウィンドウを選ぶ")
    func picksFirstNormalWindowOfTarget() {
        let expected = CGRect(x: 100, y: 200, width: 800, height: 600)
        let windowList: [[String: Any]] = [
            // @note p0-1102
            window(pid: otherPID, layer: 0, bounds: CGRect(x: 0, y: 0, width: 300, height: 300)),
            // @note p0-1103
            window(pid: targetPID, layer: 101, bounds: CGRect(x: 10, y: 10, width: 200, height: 400)),
            window(pid: targetPID, layer: 0, bounds: expected),
            // @note p0-1104
            window(pid: targetPID, layer: 0, bounds: CGRect(x: 2000, y: 0, width: 800, height: 600)),
        ]

        #expect(TargetWindowLocator.frontWindowBounds(in: windowList, processIdentifier: targetPID) == expected)
    }

    @Test("AC-7: 枠が壊れている・無いウィンドウは飛ばして次を選ぶ")
    func skipsBrokenBounds() {
        let expected = CGRect(x: 1500, y: 100, width: 640, height: 480)
        let windowList: [[String: Any]] = [
            [
                kCGWindowOwnerPID as String: NSNumber(value: targetPID),
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowBounds as String: "壊れた値",
            ],
            [
                kCGWindowOwnerPID as String: NSNumber(value: targetPID),
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowBounds as String: ["X": "a", "Y": "b"] as NSDictionary,
            ],
            [
                kCGWindowOwnerPID as String: NSNumber(value: targetPID),
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": "wide", "Height": 10] as NSDictionary,
            ],
            [
                kCGWindowOwnerPID as String: NSNumber(value: targetPID),
                kCGWindowLayer as String: NSNumber(value: 0),
            ],
            // @note p0-1105
            [
                kCGWindowOwnerPID as String: NSNumber(value: targetPID),
                kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 10, height: 10).dictionaryRepresentation,
            ],
            window(pid: targetPID, layer: 0, bounds: expected),
        ]

        #expect(TargetWindowLocator.frontWindowBounds(in: windowList, processIdentifier: targetPID) == expected)
    }

    @Test("AC-7: 挿入先のプロセスで layer 0 のウィンドウが無ければ決めない")
    func noMatchReturnsNil() {
        let windowList: [[String: Any]] = [
            window(pid: otherPID, layer: 0, bounds: CGRect(x: 0, y: 0, width: 300, height: 300)),
            window(pid: targetPID, layer: 25, bounds: CGRect(x: 0, y: 0, width: 300, height: 22)),
        ]

        #expect(TargetWindowLocator.frontWindowBounds(in: windowList, processIdentifier: targetPID) == nil)
        #expect(TargetWindowLocator.frontWindowBounds(in: [], processIdentifier: targetPID) == nil)
    }

    @Test("AC-5, AC-7: 選んだウィンドウの枠を左下が原点の座標に直すと、重なりの大きい画面が選ばれる")
    func selectedWindowLeadsToScreen() {
        // @note p0-1106
        let screenA = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
        )
        let screenB = ScreenGeometry(
            frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        )
        // @note p0-1107
        let windowList = [window(pid: targetPID, layer: 0, bounds: CGRect(x: 2000, y: 700, width: 800, height: 200))]

        let bounds = TargetWindowLocator.frontWindowBounds(in: windowList, processIdentifier: targetPID)
        let frame = bounds.map { PanelPlacement.cocoaFrame(fromQuartz: $0, primaryScreenHeight: screenA.frame.height) }
        #expect(frame == CGRect(x: 2000, y: 0, width: 800, height: 200))

        let chosen = PanelPlacement.screen(
            for: .targetWindow,
            screens: [screenA, screenB],
            mouseLocation: CGPoint(x: 700, y: 450),
            targetWindowFrame: frame
        )
        #expect(chosen == screenB)
    }
}
