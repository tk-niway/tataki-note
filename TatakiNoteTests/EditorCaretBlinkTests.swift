import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct EditorCaretBlinkTests {
    private let periods = EditorCaretBlink.Periods(on: 0.6, off: 0.4)

    private func makeBlink(after events: [EditorCaretBlink.Event] = []) -> EditorCaretBlink {
        var blink = EditorCaretBlink(periods: periods)
        for event in events {
            _ = blink.handle(event)
        }
        return blink
    }

    @Test("AC-18: 最初は消えていて、点滅を始めると点いた状態から数え始める")
    func activateStartsBlinkingFromOn() {
        var blink = makeBlink()
        #expect(blink.phase == .hidden)
        #expect(blink.handle(.activate) == .schedule(after: 0.6))
        #expect(blink.phase == .on)
    }

    @Test("AC-18: 時計が進むたびに、点灯と消灯を交互に繰り返し、それぞれの時間を数える")
    func tickAlternatesBetweenOnAndOff() {
        var blink = makeBlink(after: [.activate])
        #expect(blink.handle(.tick) == .schedule(after: 0.4))
        #expect(blink.phase == .off)
        #expect(blink.handle(.tick) == .schedule(after: 0.6))
        #expect(blink.phase == .on)
    }

    @Test("AC-18: 打つ・動かすと、消えていても点いた状態から数え直す")
    func resetRestartsFromOn() {
        var blink = makeBlink(after: [.activate, .tick])
        #expect(blink.phase == .off)
        #expect(blink.handle(.reset) == .schedule(after: 0.6))
        #expect(blink.phase == .on)
    }

    @Test("AC-18: 点滅中にもう一度 activate を受けても、点いた状態から数え直す")
    func activateAgainRestartsFromOn() {
        var blink = makeBlink(after: [.activate, .tick])
        #expect(blink.handle(.activate) == .schedule(after: 0.6))
        #expect(blink.phase == .on)
    }

    @Test("AC-18: 選択中・フォーカスが外れたときは消え、時計を止める")
    func deactivateHidesAndCancels() {
        for events in [[EditorCaretBlink.Event.activate], [.activate, .tick]] {
            var blink = makeBlink(after: events)
            #expect(blink.handle(.deactivate) == .cancel)
            #expect(blink.phase == .hidden)
        }
    }

    @Test("AC-18: 消えている間は、reset・tick・deactivate を受けても点かず、時計も動かさない")
    func hiddenIgnoresEverythingButActivate() {
        for event in [EditorCaretBlink.Event.reset, .tick, .deactivate] {
            var blink = makeBlink()
            #expect(blink.handle(event) == .none)
            #expect(blink.phase == .hidden)
        }
    }

    @Test("AC-18: 点滅の時間は、システムの保存があればミリ秒を秒にして使い、無ければ 0.5 秒")
    func systemPeriodsReadFromDefaults() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        #expect(EditorCaretBlink.Periods.system(defaults: temporary.defaults) == .init(on: 0.5, off: 0.5))

        temporary.defaults.set(800, forKey: "NSTextInsertionPointBlinkPeriodOn")
        temporary.defaults.set(250, forKey: "NSTextInsertionPointBlinkPeriodOff")
        #expect(EditorCaretBlink.Periods.system(defaults: temporary.defaults) == .init(on: 0.8, off: 0.25))

        temporary.defaults.set(0, forKey: "NSTextInsertionPointBlinkPeriodOn")
        temporary.defaults.set("速い", forKey: "NSTextInsertionPointBlinkPeriodOff")
        #expect(EditorCaretBlink.Periods.system(defaults: temporary.defaults) == .init(on: 0.5, off: 0.5))
    }
}
