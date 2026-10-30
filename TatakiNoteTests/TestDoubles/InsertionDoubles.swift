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
