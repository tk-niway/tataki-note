import Foundation
import Observation
import Testing
@testable import TatakiNote

@Observable
private final class ObservedCounter {
    var value = 0
}

private final class ObservationCallLog {
    var values: [Int] = []
}

@MainActor
struct ObservationLoopTests {
    @Test("AC-9: 見張っている値が変わるたびに処理が呼ばれ、見張りが掛け直される")
    func callsOnChangeEachTimeAndRearms() async {
        let counter = ObservedCounter()
        let log = ObservationCallLog()
        observeRepeatedly(
            tracking: { _ = counter.value },
            onChange: {
                log.values.append(counter.value)
                return true
            }
        )

        counter.value = 1
        await yieldUntil { log.values.count == 1 }
        counter.value = 2
        await yieldUntil { log.values.count == 2 }
        counter.value = 3
        await yieldUntil { log.values.count == 3 }

        #expect(log.values == [1, 2, 3])
    }

    @Test("AC-9: 処理が false を返したあとは、値が変わっても呼ばれない")
    func stopsAfterOnChangeReturnsFalse() async throws {
        let counter = ObservedCounter()
        let log = ObservationCallLog()
        observeRepeatedly(
            tracking: { _ = counter.value },
            onChange: {
                log.values.append(counter.value)
                return counter.value < 2
            }
        )

        counter.value = 1
        await yieldUntil { log.values.count == 1 }
        counter.value = 2
        await yieldUntil { log.values.count == 2 }
        counter.value = 3
        try await Task.sleep(for: .milliseconds(100))

        #expect(log.values == [1, 2])
    }

    @Test("AC-9: チュートリアルを閉じると、パネルの変化を追わなくなる")
    func tutorialStopsFollowingPanelAfterClose() async throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let own = InsertionTarget(processIdentifier: ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
        let panelModel = PanelModel()
        let controller = TutorialWindowController(
            settings: defaults.makeSettings(),
            panelModel: panelModel,
            ownProcessIdentifier: ownPid,
            focusWindow: { _ in }
        )
        defer { controller.close() }

        controller.show()
        #expect(controller.model.currentStep == .openPanel)
        panelModel.present(target: own)
        await yieldUntil { controller.model.currentStep == .writeWithNewline }
        #expect(controller.model.currentStep == .writeWithNewline)

        controller.close()
        panelModel.text = "1行目\n2行目"
        try await Task.sleep(for: .milliseconds(100))

        #expect(controller.model.currentStep == .writeWithNewline)
    }
}
