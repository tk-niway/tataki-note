import AppKit
import Testing
@testable import TatakiNote

struct PanelPointerModifierTests {
    @Test("AC-4: ⌘ だけのフラグは command だけの集合になる")
    func commandOnly() {
        #expect(PanelPointerModifier.set(from: [.command]) == [.command])
    }

    @Test("AC-4: caps lock が入っていても ⌘ だけなら command だけの集合になる")
    func capsLockIgnored() {
        #expect(PanelPointerModifier.set(from: [.command, .capsLock]) == [.command])
    }

    @Test("AC-4: テンキー・help は無視する")
    func numericPadAndHelpIgnored() {
        #expect(PanelPointerModifier.set(from: [.option, .numericPad, .help]) == [.option])
    }

    @Test("AC-4: ⌃⌘ は2つの集合になり ⌘ だけとは一致しない")
    func controlCommandIsNotCommandOnly() {
        let set = PanelPointerModifier.set(from: [.control, .command])
        #expect(set == [.control, .command])
        #expect(set != [.command])
    }

    @Test("AC-4: 修飾キーが無ければ空の集合になる")
    func emptyFlags() {
        #expect(PanelPointerModifier.set(from: []).isEmpty)
        #expect(PanelPointerModifier.set(from: [.capsLock]).isEmpty)
    }

    @Test("AC-4: 5つの修飾キーがすべて読める")
    func allFiveRead() {
        let flags: NSEvent.ModifierFlags = [.shift, .function, .control, .option, .command]
        #expect(PanelPointerModifier.set(from: flags) == Set(PanelPointerModifier.allCases))
    }
}
