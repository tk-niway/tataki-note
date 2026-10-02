import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
struct PanelCloseButtonTests {
    private let noReplacement = NSRange(location: NSNotFound, length: 0)

    private func withSettings(_ body: (AppSettings) throws -> Void) throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(AppSettings(store: SettingsStore(defaults: defaults)))
    }

    private func makeController(settings: AppSettings) -> PanelController {
        PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: InserterStub(result: .inserted),
            permission: PermissionStub(isTrusted: true),
            notifier: NotifierStub(),
            fieldProbe: FocusedElementProbeStub()
        )
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

    @Test("AC-4: 変換中に commitMarkedText を呼ぶと、未確定の文字が確定されて文章に残り、下書きにも入る")
    func commitMarkedTextCommitsComposedText() {
        let textView = PromptTextView()
        textView.isRichText = false
        var draft = ""
        let coordinator = PromptTextEditor.Coordinator(text: Binding(get: { draft }, set: { draft = $0 }))
        textView.delegate = coordinator
        textView.string = "abc"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.setMarkedText(
            "にほんご",
            selectedRange: NSRange(location: 4, length: 0),
            replacementRange: noReplacement
        )
        #expect(textView.hasMarkedText())

        draft = ""

        textView.commitMarkedText()

        #expect(!textView.hasMarkedText())
        #expect(textView.markedRange().length == 0)
        #expect(textView.string == "abcにほんご")
        #expect(draft == "abcにほんご")
    }

    @Test("AC-4: 変換中でなければ commitMarkedText は文章も選択も変えない")
    func commitMarkedTextDoesNothingWithoutComposition() {
        let textView = PromptTextView()
        textView.isRichText = false
        textView.string = "abc"
        textView.setSelectedRange(NSRange(location: 1, length: 1))
        #expect(!textView.hasMarkedText())

        textView.commitMarkedText()

        #expect(textView.string == "abc")
        #expect(textView.selectedRange() == NSRange(location: 1, length: 1))
    }

    @Test("AC-4: パネルのファーストレスポンダの入力欄が変換中なら、commitMarkedText(in:) で確定される。入力欄以外なら何もしない")
    func commitMarkedTextInWindowFindsFocusedEditor() throws {
        try withSettings { settings in
            let model = PanelModel()
            let panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
            let hostingView = NSHostingView(
                rootView: PanelView(model: model, settings: settings, onKeyInput: { _ in false }, onClose: {})
            )
            hostingView.sizingOptions = []
            panel.contentView = hostingView
            panel.setContentSize(PanelMetrics.defaultSize)

            for _ in 0..<3 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                hostingView.layoutSubtreeIfNeeded()
            }

            let textView = try #require(Self.firstSubview(of: PromptTextView.self, in: hostingView))
            panel.makeFirstResponder(textView)
            textView.setMarkedText(
                "にほんご",
                selectedRange: NSRange(location: 4, length: 0),
                replacementRange: noReplacement
            )
            #expect(textView.hasMarkedText())

            PanelController.commitMarkedText(in: panel)

            #expect(!textView.hasMarkedText())
            #expect(model.text == "にほんご")

            panel.makeFirstResponder(nil)
            PanelController.commitMarkedText(in: panel)
        }
    }

    @Test("AC-2: closeFromButton で閉じると、開いていない状態になり、書いた文章は下書きとして残る")
    func closeFromButtonClosesAndKeepsDraft() throws {
        try withSettings { settings in
            let controller = makeController(settings: settings)
            controller.model.present(target: nil)
            controller.model.text = "下書き"

            controller.closeFromButton()

            #expect(!controller.model.isPresented)
            #expect(controller.model.text == "下書き")
            #expect(controller.heldPanelSize == nil)
        }
    }
}
