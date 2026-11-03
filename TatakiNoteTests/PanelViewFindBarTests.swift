import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
private final class FindBarHarness {
    let settings: AppSettings
    let model = PanelModel()
    let findModel = FindModel()
    let panel: PromptPanel
    let hostingView: NSHostingView<PanelView>
    private let suiteName = UUID().uuidString
    private let defaults: InMemoryDefaults

    init() throws {
        defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.animationMode = .off
        panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
        hostingView = NSHostingView(
            rootView: PanelView(model: model, settings: settings, onKeyInput: { _ in false }, findModel: findModel)
        )
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setContentSize(PanelMetrics.defaultSize)
        settle()
    }

    func removeDefaults() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func settle() {
        for _ in 0..<3 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            hostingView.layoutSubtreeIfNeeded()
        }
    }

    func settle(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        settle()
        while !condition() && Date() < deadline {
            settle()
        }
    }

    var editorHeight: CGFloat? {
        textView?.enclosingScrollView?.frame.height
    }

    private var textView: PromptTextView? {
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
struct PanelViewFindBarTests {
    private let tolerance: CGFloat = 1

    @Test("AC-48: 検索の行が出ている間は、窓は同じまま入力欄が検索バーの高さだけ低くなり、閉じると戻る")
    func findRowNarrowsEditor() throws {
        let harness = try FindBarHarness()
        defer { harness.removeDefaults() }
        let frame = harness.panel.frame
        let base = try #require(harness.editorHeight)
        let barHeight = FindBarMetrics.height(isVisible: true, isReplaceShown: false)

        harness.findModel.open(revealsReplace: false, movesFocus: false, seed: nil)
        harness.settle { abs((harness.editorHeight ?? base) - (base - barHeight)) <= tolerance }

        #expect(harness.panel.frame == frame)
        let shown = try #require(harness.editorHeight)
        #expect(abs(shown - (base - barHeight)) <= tolerance)

        harness.findModel.close()
        harness.settle { abs((harness.editorHeight ?? 0) - base) <= tolerance }

        #expect(harness.panel.frame == frame)
        let closed = try #require(harness.editorHeight)
        #expect(abs(closed - base) <= tolerance)
    }

    @Test("AC-48: 置換の行まで出ている間は、入力欄が置換の行の分も低くなり、置換の行を閉じると検索の行の分に戻る")
    func replaceRowNarrowsEditorFurther() throws {
        let harness = try FindBarHarness()
        defer { harness.removeDefaults() }
        let frame = harness.panel.frame
        let base = try #require(harness.editorHeight)
        let findOnly = FindBarMetrics.height(isVisible: true, isReplaceShown: false)
        let withReplace = FindBarMetrics.height(isVisible: true, isReplaceShown: true)

        harness.findModel.open(revealsReplace: true, movesFocus: false, seed: nil)
        harness.settle { abs((harness.editorHeight ?? base) - (base - withReplace)) <= tolerance }

        #expect(harness.panel.frame == frame)
        let withReplaceHeight = try #require(harness.editorHeight)
        #expect(abs(withReplaceHeight - (base - withReplace)) <= tolerance)

        harness.findModel.toggleReplace()
        harness.settle { abs((harness.editorHeight ?? 0) - (base - findOnly)) <= tolerance }

        #expect(harness.panel.frame == frame)
        let findOnlyHeight = try #require(harness.editorHeight)
        #expect(abs(findOnlyHeight - (base - findOnly)) <= tolerance)

        harness.findModel.close()
        harness.settle { abs((harness.editorHeight ?? 0) - base) <= tolerance }

        let closedHeight = try #require(harness.editorHeight)
        #expect(abs(closedHeight - base) <= tolerance)
    }
}
