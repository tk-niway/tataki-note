import AppKit
import Testing
@testable import TatakiNote

@MainActor
final class InserterStub: TextInserting {
    var result: InsertionResult
    var onInsert: (() -> Void)?
    private(set) var calls: [(text: String, target: InsertionTarget, shouldSendAfterInsert: Bool)] = []

    init(result: InsertionResult) {
        self.result = result
    }

    func insert(_ text: String, into target: InsertionTarget, shouldSendAfterInsert: Bool) async -> InsertionResult {
        calls.append((text, target, shouldSendAfterInsert))
        onInsert?()
        return result
    }
}

@MainActor
final class ActivatorStub: ApplicationActivating {
    var result: Bool
    var onActivate: (() -> Void)?
    private(set) var targets: [InsertionTarget] = []

    init(result: Bool) {
        self.result = result
    }

    func activate(_ target: InsertionTarget) async -> Bool {
        targets.append(target)
        onActivate?()
        return result
    }
}

@MainActor
final class PasteShortcutPosterStub: PasteShortcutPosting {
    struct Record {
        var itemCount: Int
        var types: Set<NSPasteboard.PasteboardType>
        var string: String?
    }

    private let pasteboard: NSPasteboard
    var onPost: (() -> Void)?
    private(set) var records: [Record] = []

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func postPasteShortcut() {
        let items = pasteboard.pasteboardItems ?? []
        records.append(
            Record(
                itemCount: items.count,
                types: Set(items.flatMap(\.types)),
                string: pasteboard.string(forType: .string)
            )
        )
        onPost?()
    }
}

@MainActor
final class FocusInspectorStub: FocusedTextInputInspecting {
    var state: FocusedTextInputState
    var isSecureTextField: Bool
    var onInspect: (() -> Void)?
    var values: [String?] = []
    var onReadValue: (() -> Void)?
    private(set) var valueReadCount = 0
    private(set) var targets: [InsertionTarget] = []

    init(state: FocusedTextInputState, isSecureTextField: Bool = false) {
        self.state = state
        self.isSecureTextField = isSecureTextField
    }

    func focusedTextInputState(in target: InsertionTarget) -> FocusedTextInputState {
        targets.append(target)
        onInspect?()
        return state
    }

    func inspectFocusedInput(in target: InsertionTarget) -> FocusedInputInspection {
        FocusedInputInspection(state: focusedTextInputState(in: target), isSecureTextField: isSecureTextField)
    }

    func focusedTextValue(in target: InsertionTarget) -> String? {
        let index = valueReadCount
        valueReadCount += 1
        onReadValue?()
        guard !values.isEmpty else { return nil }
        return values[min(index, values.count - 1)]
    }
}

@MainActor
final class SubmitKeySenderStub: SubmitKeySending {
    struct Record {
        var target: InsertionTarget
        var pasteboardString: String?
    }

    private let pasteboard: NSPasteboard
    var onSend: (() -> Void)?
    private(set) var records: [Record] = []

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func sendSubmitKey(to target: InsertionTarget) async {
        records.append(Record(target: target, pasteboardString: pasteboard.string(forType: .string)))
        onSend?()
    }
}

@MainActor
final class FrontmostApplicationStub: FrontmostApplicationReading {
    private let provide: () -> pid_t?
    private(set) var readCount = 0

    init(_ provide: @escaping () -> pid_t?) {
        self.provide = provide
    }

    var frontmostProcessIdentifier: pid_t? {
        readCount += 1
        return provide()
    }
}

@MainActor
final class InsertionEventLog {
    private(set) var events: [String] = []

    func add(_ event: String) {
        events.append(event)
    }

    func index(of event: String, after start: Int = -1) -> Int? {
        events.indices.first { $0 > start && events[$0] == event }
    }
}

@MainActor
final class RecordingSnapshotter: PasteboardSnapshotting {
    private let inner: BackgroundPasteboardSnapshotter
    private let log: InsertionEventLog?
    var captureDelay: Duration = .zero
    var afterCapture: ((_ callNumber: Int) -> Void)?
    private(set) var captureCount = 0
    private(set) var returnedCaptures: [CapturedPasteboard] = []
    private(set) var restoreResults: [Bool] = []

    init(pasteboard: NSPasteboard, log: InsertionEventLog? = nil) {
        inner = BackgroundPasteboardSnapshotter(pasteboard: pasteboard)
        self.log = log
    }

    func capture() async -> CapturedPasteboard {
        captureCount += 1
        let callNumber = captureCount
        log?.add("captureStart")
        if captureDelay > .zero {
            try? await Task.sleep(for: captureDelay)
        }
        let captured = await inner.capture()
        returnedCaptures.append(captured)
        afterCapture?(callNumber)
        log?.add("captureEnd")
        return captured
    }

    func restore(_ snapshot: PasteboardSnapshot, ifChangeCountIs changeCount: Int) async -> Bool {
        let didRestore = await inner.restore(snapshot, ifChangeCountIs: changeCount)
        restoreResults.append(didRestore)
        log?.add("restore")
        return didRestore
    }
}
