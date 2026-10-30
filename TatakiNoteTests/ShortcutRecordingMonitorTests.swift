import AppKit
import Testing
@testable import TatakiNote

@MainActor
@Suite(.serialized)
struct ShortcutRecordingMonitorTests {
    @Test("AC-24: 記録を始めると「どこかで記録中」になり、やめると戻る")
    func recordingStateFollowsView() {
        let view = ShortcutRecordingMonitorView()
        #expect(!ShortcutRecordingMonitorView.isRecordingAnywhere)

        view.setRecording(true)
        #expect(ShortcutRecordingMonitorView.isRecordingAnywhere)

        view.setRecording(false)
        #expect(!ShortcutRecordingMonitorView.isRecordingAnywhere)
    }

    @Test("AC-24: 2つの記録欄が重なっても、両方やめるまで記録中")
    func overlappingRecordingsStayRecordingUntilBothStop() {
        let first = ShortcutRecordingMonitorView()
        let second = ShortcutRecordingMonitorView()

        first.setRecording(true)
        second.setRecording(true)
        first.setRecording(false)
        #expect(ShortcutRecordingMonitorView.isRecordingAnywhere)

        second.setRecording(false)
        #expect(!ShortcutRecordingMonitorView.isRecordingAnywhere)
    }

    @Test("AC-24: 記録を終えると、記録中でなくなる")
    func finishRecordingClearsState() {
        let view = ShortcutRecordingMonitorView()
        view.setRecording(true)

        view.finishRecording()

        #expect(!ShortcutRecordingMonitorView.isRecordingAnywhere)
    }

    @Test("AC-24: 記録中のまま view が破棄されると、「どこかで記録中」ではなくなる")
    func destroyedViewIsNotRecording() {
        autoreleasepool {
            let view = ShortcutRecordingMonitorView()
            view.setRecording(true)
            #expect(ShortcutRecordingMonitorView.isRecordingAnywhere)
        }

        #expect(!ShortcutRecordingMonitorView.isRecordingAnywhere)
    }
}
