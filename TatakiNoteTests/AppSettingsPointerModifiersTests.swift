import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AppSettingsPointerModifiersTests {
    @Test("AC-1: 移動の修飾キーの初期値は ⌘、サイズ変更は ⌥")
    func defaults() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        let settings = temp.makeSettings()
        #expect(settings.panelMoveModifiers == [.command])
        #expect(settings.panelResizeModifiers == [.option])
        #expect(settings.pointerModifiers(for: .move) == [.command])
        #expect(settings.pointerModifiers(for: .resize) == [.option])
    }

    @Test("AC-1: 変えた組み合わせ(全部外した「使えない」を含む)は起動し直しても残る")
    func changedCombinationsSurviveRestart() throws {
        let name = UUID().uuidString
        let temp = try TemporaryDefaults(name: name)
        defer { temp.remove() }

        let settings = temp.makeSettings()
        #expect(settings.selectPointerModifiers([.control, .command], for: .move))
        #expect(settings.selectPointerModifiers([], for: .resize))

        let reloaded = try TemporaryDefaults(name: name).makeSettings()
        #expect(reloaded.panelMoveModifiers == [.control, .command])
        #expect(reloaded.panelResizeModifiers.isEmpty)
        #expect(temp.defaults.array(forKey: "panelMoveModifiers") as? [String] == ["control", "command"])
        #expect(temp.defaults.array(forKey: "panelResizeModifiers") as? [String] == [String]())
    }

    @Test("AC-1: 保存の値が配列でない・キーが無いときは初期値")
    func nonArrayOrMissingValueFallsBackToDefault() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        temp.defaults.set("command", forKey: "panelMoveModifiers")
        temp.defaults.set(3, forKey: "panelResizeModifiers")
        let settings = temp.makeSettings()
        #expect(settings.panelMoveModifiers == [.command])
        #expect(settings.panelResizeModifiers == [.option])
    }

    @Test("AC-1: 知らない文字列は無視して読み、知らない文字列だけの配列は使えない状態になる")
    func unknownStringsAreIgnored() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        temp.defaults.set(["shift", "unknown", 3, "option"], forKey: "panelMoveModifiers")
        temp.defaults.set(["unknown"], forKey: "panelResizeModifiers")
        let settings = temp.makeSettings()
        #expect(settings.panelMoveModifiers == [.shift, .option])
        #expect(settings.panelResizeModifiers.isEmpty)
    }

    @Test("AC-1: 空の配列は使えない状態として読む")
    func emptyArrayMeansDisabled() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        temp.defaults.set([String](), forKey: "panelMoveModifiers")
        #expect(temp.makeSettings().panelMoveModifiers.isEmpty)
    }

    @Test("AC-1: もう一方と同じ(空でない)組み合わせは受け付けず、値も保存も変わらない")
    func sameCombinationIsRejected() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        let settings = temp.makeSettings()
        #expect(settings.selectPointerModifiers([.option], for: .move) == false)
        #expect(settings.panelMoveModifiers == [.command])
        #expect(temp.defaults.object(forKey: "panelMoveModifiers") == nil)

        #expect(settings.selectPointerModifiers([.command], for: .resize) == false)
        #expect(settings.panelResizeModifiers == [.option])
        #expect(temp.defaults.object(forKey: "panelResizeModifiers") == nil)
    }

    @Test("AC-1: 空の組み合わせは、もう一方も空でも受け付ける")
    func emptyCombinationIsAlwaysAccepted() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        let settings = temp.makeSettings()
        #expect(settings.selectPointerModifiers([], for: .move))
        #expect(settings.selectPointerModifiers([], for: .resize))
        #expect(settings.panelMoveModifiers.isEmpty)
        #expect(settings.panelResizeModifiers.isEmpty)
    }
}
