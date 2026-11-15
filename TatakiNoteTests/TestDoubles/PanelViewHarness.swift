import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
final class PanelViewHarness {
    let settings: AppSettings
    let model = PanelModel()
    let panel: PromptPanel
    let hostingView: NSHostingView<PanelView>
    private let suiteName = UUID().uuidString
    private let defaults: InMemoryDefaults

    init(configure: (AppSettings) -> Void = { _ in }) throws {
        defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        settings = AppSettings(store: SettingsStore(defaults: defaults))
        configure(settings)
        panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
        hostingView = NSHostingView(
            rootView: PanelView(model: model, settings: settings, onKeyInput: { _ in false }, onClose: {})
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

    @discardableResult
    func settle(until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        settle()
        while !condition() && Date() < deadline {
            settle()
        }
        return condition()
    }

    var textView: PromptTextView? {
        Self.firstSubview(of: PromptTextView.self, in: hostingView)
    }

    var editorHeight: CGFloat? {
        textView?.enclosingScrollView?.frame.height
    }

    var textFonts: [NSFont?] {
        guard let storage = textView?.textStorage else { return [] }
        var fonts: [NSFont?] = []
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            fonts.append(value as? NSFont)
        }
        return fonts
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
