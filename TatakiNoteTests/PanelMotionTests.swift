import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelMotionTests {
    private func keyDown(_ characters: String, modifiers: NSEvent.ModifierFlags, in panel: NSPanel) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 4
        )
    }

    @Test("AC-4: 線の枠は元の枠と同じ x と幅で、高さが 2、縦の中心が元の枠と同じ")
    func lineFrameKeepsXWidthAndCenter() {
        let frame = CGRect(x: 100, y: 200, width: 520, height: 340)
        let line = PanelMotion.lineFrame(of: frame)

        #expect(line.minX == frame.minX)
        #expect(line.width == frame.width)
        #expect(line.height == 2)
        #expect(line.midY == frame.midY)
        #expect(line == CGRect(x: 100, y: 369, width: 520, height: 2))
    }

    @Test("AC-4: 高さが 2 以下の枠でも縦の中心を保つ")
    func lineFrameKeepsCenterForShortFrames() {
        for height in [CGFloat(0), 1, 2] {
            let frame = CGRect(x: 10, y: 50, width: 300, height: height)
            let line = PanelMotion.lineFrame(of: frame)

            #expect(line.midY == frame.midY)
            #expect(line.height == 2)
            #expect(line.minX == 10)
            #expect(line.width == 300)
        }
    }

    @Test("AC-5: 作った直後は閉じた状態")
    func stateStartsHidden() {
        let state = PanelMotionState()

        #expect(state.phase == .hidden)
    }

    @Test("AC-5: 開く動きの終わりで開いた状態、閉じる動きの終わりで閉じた状態に進む")
    func finishAdvancesPhase() {
        var state = PanelMotionState()

        let openToken = state.beginOpening()
        #expect(state.phase == .opening)
        let openAdvanced = state.finish(openToken)
        #expect(openAdvanced)
        #expect(state.phase == .shown)

        let closeToken = state.beginClosing()
        #expect(state.phase == .closing)
        let closeAdvanced = state.finish(closeToken)
        #expect(closeAdvanced)
        #expect(state.phase == .hidden)
    }

    @Test("AC-5: 後から始めた動きより前の動きの終わりの知らせは状態を変えない")
    func staleFinishAfterNewMotionIsIgnored() {
        var state = PanelMotionState()

        let closeToken = state.beginClosing()
        let openToken = state.beginOpening()
        let before = state

        let staleAdvanced = state.finish(closeToken)
        #expect(staleAdvanced == false)
        #expect(state == before)
        #expect(state.phase == .opening)

        let currentAdvanced = state.finish(openToken)
        #expect(currentAdvanced)
        #expect(state.phase == .shown)
    }

    @Test("AC-5: 動きなしの変更より前の動きの終わりの知らせは状態を変えない")
    func staleFinishAfterChangeWithoutMotionIsIgnored() {
        var state = PanelMotionState()

        let closeToken = state.beginClosing()
        state.showWithoutMotion()
        #expect(state.phase == .shown)
        let afterShow = state.finish(closeToken)
        #expect(afterShow == false)
        #expect(state.phase == .shown)

        let openToken = state.beginOpening()
        state.hideWithoutMotion()
        #expect(state.phase == .hidden)
        let afterHide = state.finish(openToken)
        #expect(afterHide == false)
        #expect(state.phase == .hidden)
    }

    @Test("AC-5: 同じ知らせを二度受けても二度目は状態を変えない")
    func finishTwiceChangesOnlyOnce() {
        var state = PanelMotionState()

        let token = state.beginOpening()

        let first = state.finish(token)
        let second = state.finish(token)
        #expect(first)
        #expect(second == false)
        #expect(state.phase == .shown)
    }

    @Test("AC-5: 始める・動きなしで変えるたびに番号が進み、終わりの知らせでは進まない")
    func generationAdvancesOnlyOnStartsAndChanges() {
        var state = PanelMotionState()
        #expect(state.generation == 0)

        let first = state.beginOpening()
        #expect(first == 1)
        #expect(state.generation == 1)

        let advanced = state.finish(first)
        #expect(advanced)
        #expect(state.generation == 1)

        let second = state.beginClosing()
        #expect(second == 2)

        state.showWithoutMotion()
        #expect(state.generation == 3)

        state.hideWithoutMotion()
        #expect(state.generation == 4)
    }

    @Test("AC-14: ⌘H の判定は ⌘+H だけに当たる(大文字の H も同じ)")
    func hideKeyMatchesCommandH() {
        #expect(PanelHideKey.matches(modifiers: [.command], charactersIgnoringModifiers: "h"))
        #expect(PanelHideKey.matches(modifiers: [.command], charactersIgnoringModifiers: "H"))
    }

    @Test("AC-14: Caps Lock・fn などの印が混ざっていても ⌘H に当たる")
    func hideKeyIgnoresIrrelevantModifierBits() {
        #expect(PanelHideKey.matches(modifiers: [.command, .capsLock], charactersIgnoringModifiers: "h"))
        #expect(PanelHideKey.matches(modifiers: [.command, .function], charactersIgnoringModifiers: "h"))
    }

    @Test("AC-14: ⇧⌘H・⌥⌘H・⌃⌘H・修飾なしの H・⌘J には当たらない")
    func hideKeyRejectsOtherCombinations() {
        #expect(PanelHideKey.matches(modifiers: [.command, .shift], charactersIgnoringModifiers: "h") == false)
        #expect(PanelHideKey.matches(modifiers: [.command, .option], charactersIgnoringModifiers: "h") == false)
        #expect(PanelHideKey.matches(modifiers: [.command, .control], charactersIgnoringModifiers: "h") == false)
        #expect(PanelHideKey.matches(modifiers: [], charactersIgnoringModifiers: "h") == false)
        #expect(PanelHideKey.matches(modifiers: [.command], charactersIgnoringModifiers: "j") == false)
        #expect(PanelHideKey.matches(modifiers: [.command], charactersIgnoringModifiers: nil) == false)
    }

    @Test("AC-14: パネルは作った直後に key になれて、acceptsKey を false にすると key になれない")
    func panelCanBecomeKeyFollowsAcceptsKey() {
        let panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))

        #expect(panel.canBecomeKey)

        panel.acceptsKey = false
        #expect(panel.canBecomeKey == false)

        panel.acceptsKey = true
        #expect(panel.canBecomeKey)
    }

    @Test("AC-14: onHideKey が無いとき・false を返すときは、パネルは ⌘H を処理しない")
    func panelDoesNotHandleHideKeyWithoutHandler() throws {
        let panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
        let event = try #require(keyDown("h", modifiers: [.command], in: panel))

        #expect(panel.onHideKey == nil)
        #expect(panel.performKeyEquivalent(with: event) == false)

        var calls = 0
        panel.onHideKey = {
            calls += 1
            return false
        }
        #expect(panel.performKeyEquivalent(with: event) == false)
        #expect(calls == 1)
    }

    @Test("AC-14: onHideKey が true を返すと、パネルは ⌘H を処理する。⌘H 以外のキーでは呼ばない")
    func panelHandlesHideKeyWhenHandlerReturnsTrue() throws {
        let panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
        var calls = 0
        panel.onHideKey = {
            calls += 1
            return true
        }

        let commandH = try #require(keyDown("h", modifiers: [.command], in: panel))
        #expect(panel.performKeyEquivalent(with: commandH))
        #expect(calls == 1)

        let shiftCommandH = try #require(keyDown("h", modifiers: [.command, .shift], in: panel))
        let commandJ = try #require(keyDown("j", modifiers: [.command], in: panel))
        let plainH = try #require(keyDown("h", modifiers: [], in: panel))
        #expect(panel.performKeyEquivalent(with: shiftCommandH) == false)
        #expect(panel.performKeyEquivalent(with: commandJ) == false)
        #expect(panel.performKeyEquivalent(with: plainH) == false)
        #expect(calls == 1)
    }
}
