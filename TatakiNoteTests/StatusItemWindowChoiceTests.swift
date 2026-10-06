import CoreGraphics
import Testing
@testable import TatakiNote

struct StatusItemWindowChoiceTests {
    private let firstScreen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let secondScreen = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    private func barFrame(onScreen screen: CGRect) -> CGRect {
        CGRect(x: screen.maxX - 100, y: screen.maxY - 24, width: 30, height: 24)
    }

    @Test("AC-13: 窓が無ければ選ばれない")
    func noWindows() {
        let index = StatusItemWindowChoice.index(
            windowFrames: [],
            screenFrames: [firstScreen],
            mouseLocation: CGPoint(x: 10, y: 10)
        )
        #expect(index == nil)
    }

    @Test("AC-13: 窓が1つならそれが選ばれる(マウスがその画面に無くても)")
    func singleWindow() {
        let index = StatusItemWindowChoice.index(
            windowFrames: [barFrame(onScreen: firstScreen)],
            screenFrames: [firstScreen, secondScreen],
            mouseLocation: CGPoint(x: 1500, y: 400)
        )
        #expect(index == 0)
    }

    @Test("AC-13: 2画面でマウスが2つ目の画面にあるときは、2つ目の画面の窓が選ばれる")
    func mouseOnSecondScreen() {
        let index = StatusItemWindowChoice.index(
            windowFrames: [barFrame(onScreen: firstScreen), barFrame(onScreen: secondScreen)],
            screenFrames: [firstScreen, secondScreen],
            mouseLocation: CGPoint(x: 1500, y: 400)
        )
        #expect(index == 1)
    }

    @Test("AC-13: 2画面でマウスが1つ目の画面にあるときは、1つ目の画面の窓が選ばれる")
    func mouseOnFirstScreen() {
        let index = StatusItemWindowChoice.index(
            windowFrames: [barFrame(onScreen: secondScreen), barFrame(onScreen: firstScreen)],
            screenFrames: [firstScreen, secondScreen],
            mouseLocation: CGPoint(x: 500, y: 400)
        )
        #expect(index == 1)
    }

    @Test("AC-13: マウスがどの画面にも無いときは、最初の窓が選ばれる")
    func mouseOutsideEveryScreen() {
        let index = StatusItemWindowChoice.index(
            windowFrames: [barFrame(onScreen: firstScreen), barFrame(onScreen: secondScreen)],
            screenFrames: [firstScreen, secondScreen],
            mouseLocation: CGPoint(x: 5000, y: 5000)
        )
        #expect(index == 0)
    }

    @Test("AC-13: マウスのある画面に窓が無いときは、最初の窓が選ばれる")
    func noWindowOnMouseScreen() {
        let index = StatusItemWindowChoice.index(
            windowFrames: [barFrame(onScreen: firstScreen)],
            screenFrames: [firstScreen, secondScreen],
            mouseLocation: CGPoint(x: 1500, y: 400)
        )
        #expect(index == 0)
    }
}
