import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct OpeningTargetLookupTests {
    private let editor = MonitorFixture.editor
    private let browser = MonitorFixture.browser
    private let fieldA = MonitorFixture.fieldA
    private let fieldB = MonitorFixture.fieldB
    private let frameA = MonitorFixture.frameA
    private let frameB = MonitorFixture.frameB

    private func probe(
        _ element: AXUIElement?,
        frame: CGRect?,
        lookup: FocusedElementLookup = MonitorFixture.textField
    ) -> FocusedElementProbe {
        FocusedElementProbe(element: element, lookup: lookup, frame: frame)
    }

    private func request(
        observedProbe: FocusedElementProbe? = nil,
        readsMissingFrame: Bool = true,
        shouldExposeWebContent: Bool = false
    ) -> OpeningTargetLookupRequest {
        OpeningTargetLookupRequest(
            app: editor,
            observedProbe: observedProbe,
            readsMissingFrame: readsMissingFrame,
            shouldExposeWebContent: shouldExposeWebContent
        )
    }

    private func finished(_ outcome: OpeningTargetLookupOutcome) throws -> OpeningTargetLookupResult {
        guard case .finished(let result) = outcome else {
            throw OutcomeError.notFinished
        }
        return result
    }

    private enum OutcomeError: Error {
        case notFinished
    }

    // MARK: - AC-12

    @Test("AC-12: 見張りの結果は、同じアプリのものだけ依頼に入れる")
    func makeUsesObservedFocusOnlyForSameApp() {
        let observed = probe(fieldA, frame: frameA)
        let cases: [(observedFocus: ObservedFocus?, expectsProbe: Bool)] = [
            (ObservedFocus(processIdentifier: editor.processIdentifier, probe: observed), true),
            (ObservedFocus(processIdentifier: browser.processIdentifier, probe: observed), false),
            (nil, false),
        ]
        for (observedFocus, expectsProbe) in cases {
            let made = OpeningTargetLookupRequest.make(
                app: editor,
                observedFocus: observedFocus,
                isOutlineEnabled: true,
                panelScreen: .main,
                isTrusted: true,
                shouldExposeWebContent: false
            )
            #expect(made.app == editor)
            #expect((made.observedProbe != nil) == expectsProbe)
            if expectsProbe {
                #expect(made.observedProbe?.frame == frameA)
            }
        }
    }

    @Test("AC-12: 欠けた枠を読むのは、枠線がオン、または入力欄の近く+許可ありのとき")
    func makeReadsMissingFrameTable() {
        let cases: [(isOutlineEnabled: Bool, panelScreen: PanelScreen, isTrusted: Bool, expected: Bool)] = [
            (true, .main, false, true),
            (true, .nearFocusedField, false, true),
            (false, .nearFocusedField, true, true),
            (false, .nearFocusedField, false, false),
            (false, .main, true, false),
            (false, .mouse, true, false),
            (false, .targetWindow, true, false),
        ]
        for (isOutlineEnabled, panelScreen, isTrusted, expected) in cases {
            let made = OpeningTargetLookupRequest.make(
                app: editor,
                observedFocus: nil,
                isOutlineEnabled: isOutlineEnabled,
                panelScreen: panelScreen,
                isTrusted: isTrusted,
                shouldExposeWebContent: true
            )
            #expect(
                made.readsMissingFrame == expected,
                "outline=\(isOutlineEnabled) screen=\(panelScreen) trusted=\(isTrusted)"
            )
            #expect(made.shouldExposeWebContent)
        }
    }

    @Test("AC-12: 枠を読み直すのは、読む設定で、枠が無く、要素があり、入力欄のときだけ")
    func needsFrameReadTable() {
        let cases: [(readsMissingFrame: Bool, probe: FocusedElementProbe, expected: Bool)] = [
            (true, probe(fieldA, frame: nil), true),
            (false, probe(fieldA, frame: nil), false),
            (true, probe(fieldA, frame: frameA), false),
            (true, probe(nil, frame: nil), false),
            (true, probe(fieldA, frame: nil, lookup: MonitorFixture.button), false),
            (true, probe(fieldA, frame: nil, lookup: MonitorFixture.unknownGroup), false),
        ]
        for (readsMissingFrame, candidate, expected) in cases {
            #expect(request(readsMissingFrame: readsMissingFrame).needsFrameRead(of: candidate) == expected)
        }
    }

    @Test("AC-12: 見張りの結果が同じアプリのもので枠もあれば、問い合わせも枠の読み直しもしない")
    func usesObservedProbeAsIs() throws {
        let stub = PerAppProbeStub()
        let lookup = SynchronousOpeningTargetLookup(probe: stub, exposeWebContent: { _ in })
        let observed = probe(fieldA, frame: frameA)

        let result = try finished(lookup.lookUp(request(observedProbe: observed), waitingUpTo: .seconds(1)))

        #expect(result.didQuery == false)
        #expect(result.probe.frame == frameA)
        #expect(stub.targets.isEmpty)
        #expect(stub.frameRequests.isEmpty)
    }

    @Test("AC-12: 見張りの結果に枠が無く入力欄なら、フォーカスのある要素は問い合わせ直さず枠を1回だけ読む")
    func readsMissingFrameOnce() throws {
        let stub = PerAppProbeStub()
        stub.elementFrames[7001] = frameA
        let lookup = SynchronousOpeningTargetLookup(probe: stub, exposeWebContent: { _ in })
        let observed = probe(fieldA, frame: nil)

        let result = try finished(lookup.lookUp(request(observedProbe: observed), waitingUpTo: .seconds(1)))

        #expect(result.didQuery)
        #expect(result.probe.frame == frameA)
        #expect(result.probe.lookup == MonitorFixture.textField)
        #expect(stub.targets.isEmpty)
        #expect(stub.frameRequests.count == 1)
    }

    @Test("AC-12: 枠を読まない設定のときや入力欄でないときは、見張りの結果に枠が無くても読まない")
    func doesNotReadFrameWhenNotNeeded() throws {
        let cases: [(readsMissingFrame: Bool, observed: FocusedElementProbe)] = [
            (false, probe(fieldA, frame: nil)),
            (true, probe(fieldA, frame: nil, lookup: MonitorFixture.button)),
            (true, probe(nil, frame: nil, lookup: .noFocusedElement)),
        ]
        for (readsMissingFrame, observed) in cases {
            let stub = PerAppProbeStub()
            stub.elementFrame = frameA
            let lookup = SynchronousOpeningTargetLookup(probe: stub, exposeWebContent: { _ in })

            let result = try finished(
                lookup.lookUp(
                    request(observedProbe: observed, readsMissingFrame: readsMissingFrame),
                    waitingUpTo: .seconds(1)
                )
            )

            #expect(result.didQuery == false)
            #expect(result.probe.frame == nil)
            #expect(stub.targets.isEmpty)
            #expect(stub.frameRequests.isEmpty)
        }
    }

    @Test("AC-12: 見張りの結果が無ければ1回問い合わせ、枠の読み直しはしない")
    func queriesOnceWithoutObservedProbe() throws {
        let stub = PerAppProbeStub()
        stub.results[editor.processIdentifier] = probe(fieldA, frame: frameA)
        let lookup = SynchronousOpeningTargetLookup(probe: stub, exposeWebContent: { _ in })

        let result = try finished(lookup.lookUp(request(), waitingUpTo: .seconds(1)))

        #expect(result.didQuery)
        #expect(result.probe.frame == frameA)
        #expect(stub.targets == [editor])
        #expect(stub.readsFrameValues == [true])
        #expect(stub.frameRequests.isEmpty)
    }

    @Test("AC-12: 問い合わせ直した結果の入力欄に枠が無くても、枠を読み直さない")
    func doesNotRereadFrameAfterQuery() throws {
        let stub = PerAppProbeStub()
        stub.results[editor.processIdentifier] = probe(fieldA, frame: nil)
        stub.elementFrame = frameB
        let lookup = SynchronousOpeningTargetLookup(probe: stub, exposeWebContent: { _ in })

        let result = try finished(lookup.lookUp(request(readsMissingFrame: true), waitingUpTo: .seconds(1)))

        #expect(result.didQuery)
        #expect(result.probe.frame == nil)
        #expect(stub.targets == [editor])
        #expect(stub.frameRequests.isEmpty)
    }

    @Test("AC-12: 見張りの結果が別のアプリのものとして作られた依頼では、問い合わせる")
    func queriesWhenObservedFocusIsForAnotherApp() throws {
        let stub = PerAppProbeStub()
        stub.results[editor.processIdentifier] = probe(fieldA, frame: frameA)
        let lookup = SynchronousOpeningTargetLookup(probe: stub, exposeWebContent: { _ in })
        let made = OpeningTargetLookupRequest.make(
            app: editor,
            observedFocus: ObservedFocus(processIdentifier: browser.processIdentifier, probe: probe(fieldB, frame: frameB)),
            isOutlineEnabled: true,
            panelScreen: .main,
            isTrusted: true,
            shouldExposeWebContent: false
        )

        let result = try finished(lookup.lookUp(made, waitingUpTo: .seconds(1)))

        #expect(result.probe.frame == frameA)
        #expect(stub.targets == [editor])
    }

    @Test("AC-12: Web の中身の依頼は、問い合わせより先に行う")
    func exposesWebContentBeforeQuery() throws {
        let stub = PerAppProbeStub()
        var log: [String] = []
        stub.onProbe = { log.append("probe") }
        let lookup = SynchronousOpeningTargetLookup(probe: stub, exposeWebContent: { _ in log.append("expose") })

        _ = try finished(lookup.lookUp(request(shouldExposeWebContent: true), waitingUpTo: .seconds(1)))

        #expect(log == ["expose", "probe"])
    }

    @Test("AC-12: Web の中身の依頼は、見張りの結果を使うときも枠を読む前に行う")
    func exposesWebContentBeforeFrameRead() throws {
        let stub = PerAppProbeStub()
        stub.elementFrame = frameA
        var log: [String] = []
        stub.onFrameRequest = { log.append("frame") }
        let lookup = SynchronousOpeningTargetLookup(probe: stub, exposeWebContent: { _ in log.append("expose") })

        _ = try finished(
            lookup.lookUp(
                request(observedProbe: probe(fieldA, frame: nil), shouldExposeWebContent: true),
                waitingUpTo: .seconds(1)
            )
        )

        #expect(log == ["expose", "frame"])
    }

    @Test("AC-12: 頼まない依頼では、Web の中身の依頼をしない")
    func doesNotExposeWhenNotRequested() throws {
        let stub = PerAppProbeStub()
        var exposed: [InsertionTarget] = []
        let lookup = SynchronousOpeningTargetLookup(probe: stub, exposeWebContent: { exposed.append($0) })

        _ = try finished(lookup.lookUp(request(shouldExposeWebContent: false), waitingUpTo: .seconds(1)))
        #expect(exposed.isEmpty)

        _ = try finished(lookup.lookUp(request(shouldExposeWebContent: true), waitingUpTo: .seconds(1)))
        #expect(exposed == [editor])
    }

    @Test("AC-12: かかった時間は、調べの前後の時刻の差")
    func measuresDuration() throws {
        let stub = PerAppProbeStub()
        var current = Date(timeIntervalSinceReferenceDate: 1_000)
        stub.onProbe = { current = current.addingTimeInterval(0.25) }
        let lookup = SynchronousOpeningTargetLookup(
            probe: stub,
            exposeWebContent: { _ in },
            now: { current }
        )

        let result = try finished(lookup.lookUp(request(), waitingUpTo: .seconds(1)))

        #expect(result.duration == 0.25)
    }
}
