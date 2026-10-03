import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
private final class EditorPanelHarness {
    let settings: AppSettings
    let model = PanelModel()
    let panel: PromptPanel
    let hostingView: NSHostingView<PanelView>
    private let suiteName = UUID().uuidString
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        settings = AppSettings(store: SettingsStore(defaults: defaults))
        panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
        hostingView = NSHostingView(
            rootView: PanelView(model: model, settings: settings, onKeyInput: { _ in false }, onClose: {})
        )
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setContentSize(PanelMetrics.defaultSize)
        hostingView.layoutSubtreeIfNeeded()
    }

    func removeDefaults() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func settleAsync() async {
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(10))
            hostingView.layoutSubtreeIfNeeded()
        }
    }

    @discardableResult
    func settle(until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        await settleAsync()
        while !condition() && Date() < deadline {
            await settleAsync()
        }
        return condition()
    }

    var textView: PromptTextView? {
        Self.firstSubview(of: PromptTextView.self, in: hostingView)
    }

    private static func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let match = firstSubview(of: type, in: subview) {
                return match
            }
        }
        return nil
    }
}

@MainActor
struct EditorTextViewTests {
    private final class TextBox {
        var value = ""
    }

    private struct Fixture {
        var window: NSWindow
        var textView: PromptTextView
        var box: TextBox
        var coordinator: EditorTextCoordinator
    }

    private let noReplacement = NSRange(location: NSNotFound, length: 0)

    private func withFixture(initialText: String = "", _ body: (Fixture) async throws -> Void) async rethrows {
        let box = TextBox()
        box.value = initialText
        let coordinator = EditorTextCoordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let textView = PromptTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        defer {
            textView.inputContext?.discardMarkedText()
            window.makeFirstResponder(nil)
            window.close()
        }
        textView.delegate = coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = initialText
        window.contentView = textView
        window.makeFirstResponder(textView)
        try await body(Fixture(window: window, textView: textView, box: box, coordinator: coordinator))
    }

    private func pumpRunLoop() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func startComposing(_ marked: String, in textView: NSTextView) {
        textView.setMarkedText(
            marked,
            selectedRange: NSRange(location: (marked as NSString).length, length: 0),
            replacementRange: noReplacement
        )
    }

    // MARK: - 同期

    @Test("AC-7: 入力欄で打つと、SwiftUI 側の文章がその文字列になる")
    func typingUpdatesBinding() async {
        await withFixture { fixture in
            fixture.textView.insertText("abc", replacementRange: noReplacement)
            #expect(fixture.box.value == "abc")
            #expect(fixture.coordinator.lastSyncedText == "abc")

            fixture.textView.insertText("def", replacementRange: noReplacement)
            #expect(fixture.box.value == "abcdef")
        }
    }

    @Test("AC-7: SwiftUI 側の文章を別の値にすると、入力欄の文字列がその値になり、取り消しの履歴が消える")
    func externalChangeReplacesTextAndClearsUndo() async {
        await withFixture { fixture in
            fixture.textView.insertText("typed", replacementRange: noReplacement)
            await pumpRunLoop()
            #expect(fixture.textView.undoManager?.canUndo == true)

            fixture.box.value = "draft"
            fixture.coordinator.syncText(fixture.box.value, to: fixture.textView)
            #expect(fixture.textView.string == "draft")
            #expect(fixture.coordinator.lastSyncedText == "draft")
            #expect(fixture.textView.undoManager?.canUndo == false)

            fixture.box.value = ""
            fixture.coordinator.syncText(fixture.box.value, to: fixture.textView)
            #expect(fixture.textView.string.isEmpty)
        }
    }

    @Test("AC-7: 変換中に SwiftUI 側の文章を変えても入力欄は書き換わらず、変換が終わった後の同期で入る")
    func externalChangeWaitsForComposition() async {
        await withFixture { fixture in
            fixture.textView.insertText("abc", replacementRange: noReplacement)
            startComposing("にほんご", in: fixture.textView)
            #expect(fixture.textView.hasMarkedText())

            fixture.box.value = "other"
            fixture.coordinator.syncText("other", to: fixture.textView)
            #expect(fixture.textView.string == "abcにほんご")
            #expect(fixture.coordinator.lastSyncedText != "other")

            fixture.textView.commitMarkedText()
            #expect(!fixture.textView.hasMarkedText())
            fixture.box.value = "other"
            fixture.coordinator.syncText("other", to: fixture.textView)
            #expect(fixture.textView.string == "other")
            #expect(fixture.coordinator.lastSyncedText == "other")
        }
    }

    @Test("AC-7: 変換中に外から入れた値は、変換を外した(unmarkText)後の同期で、入れ直さなくてもそのまま入る")
    func externalChangeAppliesAfterUnmarkText() async {
        await withFixture { fixture in
            fixture.textView.insertText("abc", replacementRange: noReplacement)
            startComposing("にほんご", in: fixture.textView)
            #expect(fixture.textView.hasMarkedText())

            fixture.coordinator.syncText("other", to: fixture.textView)
            #expect(fixture.textView.string == "abcにほんご")
            #expect(fixture.coordinator.lastSyncedText != "other")

            fixture.textView.unmarkText()
            #expect(!fixture.textView.hasMarkedText())
            fixture.coordinator.syncText("other", to: fixture.textView)
            #expect(fixture.textView.string == "other")
            #expect(fixture.coordinator.lastSyncedText == "other")
        }
    }

    @Test("AC-8: 打った後に同じ文章で同期を呼んでも、入力欄の文字列・選択の位置・取り消しの履歴は変わらず、⌘Z で戻せる")
    func syncWithSameTextKeepsSelectionAndUndo() async {
        await withFixture { fixture in
            fixture.textView.insertText("abc", replacementRange: noReplacement)
            await pumpRunLoop()
            let selection = fixture.textView.selectedRange()
            #expect(fixture.textView.undoManager?.canUndo == true)

            fixture.coordinator.syncText(fixture.box.value, to: fixture.textView)

            #expect(fixture.textView.string == "abc")
            #expect(fixture.textView.selectedRange() == selection)
            #expect(fixture.textView.undoManager?.canUndo == true)

            fixture.textView.undoManager?.undo()
            #expect(fixture.textView.string.isEmpty)
        }
    }

    @Test("AC-8: 最初の文章と同じ文章での同期は、入力欄を入れ直さない")
    func syncWithInitialTextDoesNothing() async {
        await withFixture(initialText: "draft") { fixture in
            fixture.textView.setSelectedRange(NSRange(location: 2, length: 1))

            fixture.coordinator.syncText("draft", to: fixture.textView)

            #expect(fixture.textView.string == "draft")
            #expect(fixture.textView.selectedRange() == NSRange(location: 2, length: 1))
        }
    }

    // MARK: - フォーカス

    @Test("AC-9: フォーカスの要求が来ると、入力欄がファーストレスポンダになり、カーソルが末尾に置かれる。同じ番号ではもう一度動かない")
    func focusRequestRunsOncePerNumber() async {
        await withFixture(initialText: "one\ntwo\nthree") { fixture in
            fixture.window.makeFirstResponder(nil)
            fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))

            fixture.coordinator.focusIfRequested(1, textView: fixture.textView)
            await pumpRunLoop()
            #expect(fixture.window.firstResponder === fixture.textView)
            #expect(fixture.textView.selectedRange() == NSRange(location: 13, length: 0))

            fixture.window.makeFirstResponder(nil)
            fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))
            fixture.coordinator.focusIfRequested(1, textView: fixture.textView)
            await pumpRunLoop()
            #expect(fixture.window.firstResponder !== fixture.textView)
            #expect(fixture.textView.selectedRange() == NSRange(location: 0, length: 0))

            fixture.coordinator.focusIfRequested(2, textView: fixture.textView)
            await pumpRunLoop()
            #expect(fixture.window.firstResponder === fixture.textView)
            #expect(fixture.textView.selectedRange() == NSRange(location: 13, length: 0))
        }
    }

    @Test("AC-9: パネルを開く present() で、入力欄がファーストレスポンダになり、カーソルが末尾に置かれ、末尾が見える位置までスクロールする")
    func presentFocusesAndScrollsToEnd() async throws {
        let harness = try EditorPanelHarness()
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)
        harness.model.text = Array(repeating: "line", count: 60).joined(separator: "\n")
        let textArrived = await harness.settle { textView.string.hasPrefix("line\nline") }
        #expect(textArrived)

        harness.panel.makeFirstResponder(nil)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        #expect(harness.panel.firstResponder !== textView)

        harness.model.present()

        let focused = await harness.settle { harness.panel.firstResponder === textView }
        #expect(focused)
        let end = (textView.string as NSString).length
        let cursorAtEnd = await harness.settle { textView.selectedRange() == NSRange(location: end, length: 0) }
        #expect(cursorAtEnd)
        let endVisible = await harness.settle {
            guard let textContainer = textView.textContainer else { return false }
            let rect = textView.layoutManager?.boundingRect(
                forGlyphRange: NSRange(location: end - 1, length: 1),
                in: textContainer
            ) ?? .zero
            return textView.visibleRect.intersects(rect)
        }
        #expect(endVisible)
    }
}
