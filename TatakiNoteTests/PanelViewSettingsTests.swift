import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
private final class PanelViewHarness {
    let settings: AppSettings
    let model = PanelModel()
    let panel: PromptPanel
    let hostingView: NSHostingView<PanelView>
    private let suiteName = UUID().uuidString
    private let defaults: UserDefaults

    init(configure: (AppSettings) -> Void = { _ in }) throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
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

@MainActor
struct PanelViewSettingsTests {
    private let alphaTolerance: CGFloat = 0.001

    @Test("AC-1: 何も設定していなければ、入力欄の文字はシステムフォント 14pt")
    func defaultFontIsSystem14() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)

        #expect(textView.font == NSFont.systemFont(ofSize: 14))
        #expect(textView.typingAttributes[.font] as? NSFont == NSFont.systemFont(ofSize: 14))
    }

    @Test("AC-1: 設定のフォント・文字サイズが、入力欄の文字に当たる")
    func configuredFontIsApplied() throws {
        let menlo = try #require(NSFont(name: "Menlo-Regular", size: 20))
        let harness = try PanelViewHarness { settings in
            settings.panelFontName = "Menlo-Regular"
            settings.panelFontSize = 20
        }
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)

        #expect(textView.font == menlo)
        #expect(textView.typingAttributes[.font] as? NSFont == menlo)
    }

    @Test("AC-2: 設定のフォントが Mac に無いときは、システムフォント(設定の文字サイズ)で表示する")
    func missingFontFallsBackToSystem() throws {
        let harness = try PanelViewHarness { settings in
            settings.panelFontName = "TatakiNoteNoSuchFont-Regular"
            settings.panelFontSize = 20
        }
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)

        #expect(textView.font == NSFont.systemFont(ofSize: 20))
        #expect(textView.typingAttributes[.font] as? NSFont == NSFont.systemFont(ofSize: 20))
    }

    @Test("AC-3: 開いたままフォント・文字サイズを変えると、書いてある文章も含めてすぐに変わり、文章は変わらない")
    func fontChangesWhileOpen() throws {
        let menlo = try #require(NSFont(name: "Menlo-Regular", size: 20))
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        harness.model.text = "abc\nxyz"
        let textView = try #require(harness.textView)
        #expect(harness.settle { textView.string == "abc\nxyz" })
        #expect(harness.textFonts == [NSFont.systemFont(ofSize: 14)])

        harness.settings.panelFontName = "Menlo-Regular"
        harness.settings.panelFontSize = 20
        #expect(harness.settle { textView.font == menlo })
        #expect(harness.textFonts == [menlo])
        #expect(textView.typingAttributes[.font] as? NSFont == menlo)
        #expect(textView.string == "abc\nxyz")
        #expect(harness.model.text == "abc\nxyz")

        harness.settings.panelFontName = nil
        #expect(harness.settle { textView.font == NSFont.systemFont(ofSize: 20) })
        #expect(harness.textFonts == [NSFont.systemFont(ofSize: 20)])
    }

    @Test("AC-3: 入力欄に収まらない文章でも入力欄の高さは変わらず、文章は入力欄の中でスクロールできる")
    func overflowingTextKeepsEditorHeightAndScrolls() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)
        let heightBefore = try #require(harness.editorHeight)

        harness.model.text = Array(repeating: "line", count: 60).joined(separator: "\n")
        #expect(harness.settle { textView.string.hasPrefix("line\nline") })

        #expect(harness.editorHeight == heightBefore)
        let scrollView = try #require(textView.enclosingScrollView)
        #expect(harness.settle { textView.frame.height > scrollView.contentView.bounds.height })
    }

    @Test("AC-3: 末尾に文字を打つと、カーソルの位置が見える範囲まで入力欄がスクロールする")
    func typingAtEndScrollsCursorIntoView() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)
        harness.model.text = Array(repeating: "line", count: 60).joined(separator: "\n")
        #expect(harness.settle { textView.string.hasPrefix("line\nline") })

        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        #expect(harness.settle { !textView.visibleRect.contains(CGPoint(x: 0, y: textView.frame.height - 1)) })

        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.insertText("z", replacementRange: NSRange(location: end, length: 0))

        #expect(harness.settle {
            let newEnd = (textView.string as NSString).length
            guard newEnd > 0, let textContainer = textView.textContainer else { return false }
            let rect = textView.layoutManager?.boundingRect(
                forGlyphRange: NSRange(location: newEnd - 1, length: 1),
                in: textContainer
            ) ?? .zero
            return textView.visibleRect.intersects(rect)
        })
    }

    @Test("AC-4: 透明度の初期値 100% では窓は透けず、開いたまま変えると窓全体の透明度がすぐに変わる")
    func opacityIsAppliedToWindow() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        #expect(harness.textView != nil)
        #expect(abs(harness.panel.alphaValue - 1.0) < alphaTolerance)

        harness.settings.panelOpacity = 0.4
        #expect(harness.settle { abs(harness.panel.alphaValue - 0.4) < alphaTolerance })

        harness.settings.panelOpacity = 0.7
        #expect(harness.settle { abs(harness.panel.alphaValue - 0.7) < alphaTolerance })

        harness.settings.panelOpacity = 1.0
        #expect(harness.settle { abs(harness.panel.alphaValue - 1.0) < alphaTolerance })
    }

    @Test("AC-4: 保存されていた透明度は、開いたときからパネルに当たる")
    func savedOpacityIsAppliedOnOpen() throws {
        let harness = try PanelViewHarness { settings in
            settings.panelOpacity = 0.5
        }
        defer { harness.removeDefaults() }

        #expect(harness.settle { abs(harness.panel.alphaValue - 0.5) < alphaTolerance })
    }

    @Test("AC-5: テーマは、システムなら窓に外観を指定せず、ライト・ダークならその外観。開いたまま変えるとすぐに変わる")
    func themeIsAppliedToWindow() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        #expect(harness.textView != nil)
        #expect(harness.panel.appearance == nil)

        harness.settings.theme = .dark
        #expect(harness.settle { harness.panel.appearance?.name == .darkAqua })

        harness.settings.theme = .light
        #expect(harness.settle { harness.panel.appearance?.name == .aqua })

        harness.settings.theme = .system
        #expect(harness.settle { harness.panel.appearance == nil })
    }

    @Test("AC-5: 保存されていたテーマは、開いたときからパネルに当たる")
    func savedThemeIsAppliedOnOpen() throws {
        let harness = try PanelViewHarness { settings in
            settings.theme = .dark
        }
        defer { harness.removeDefaults() }

        #expect(harness.settle { harness.panel.appearance?.name == .darkAqua })
    }


    @Test("AC-10: 開いたまますべて非表示にすると、帯と区切り線ごと消えて入力欄が帯の高さ + 1 だけ広がり、1つ戻すと帯が戻る")
    func hidingAllItemsRemovesStatusBar() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let heightWithBar = try #require(harness.editorHeight)

        harness.settings.hiddenPanelStatusItems = Set(PanelStatusItem.allCases)
        let expectedHeight = heightWithBar + PanelMetrics.statusBarHeight + 1
        #expect(harness.settle { abs((harness.editorHeight ?? 0) - expectedHeight) < 0.5 })

        harness.settings.setPanelStatusItem(.lineCount, isVisible: true)
        #expect(harness.settle { abs((harness.editorHeight ?? 0) - heightWithBar) < 0.5 })
    }

    @Test("AC-10: キーが登録なしの確定・確定+送信だけを残して非表示にしても、帯と区切り線ごと消える")
    func unassignedKeysOnlyRemovesStatusBar() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let heightWithBar = try #require(harness.editorHeight)

        harness.settings.hiddenPanelStatusItems = [.lineBreak, .close, .characterCount, .lineCount]
        #expect(harness.settle { abs((harness.editorHeight ?? 0) - heightWithBar) < 0.5 })

        harness.settings.commitAndSendKey = nil
        let expectedHeight = heightWithBar + PanelMetrics.statusBarHeight + 1
        #expect(harness.settle { abs((harness.editorHeight ?? 0) - expectedHeight) < 0.5 })

        harness.settings.commitKey = .commandReturn
        #expect(harness.settle { abs((harness.editorHeight ?? 0) - heightWithBar) < 0.5 })
    }

    @Test("AC-7: 閉じるボタンを付けても、入力欄の高さはパネルの高さから入力欄以外の高さ(タイトルバー・区切り線・帯)を引いた高さのまま")
    func closeButtonDoesNotChangeEditorHeight() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let titleBarHeight = harness.panel.frame.height - harness.panel.contentLayoutRect.height

        let expectedWithBar = harness.panel.frame.height
            - PanelSizing.chromeHeight(titleBarHeight: titleBarHeight, isStatusBarVisible: true)
        #expect(abs((harness.editorHeight ?? 0) - expectedWithBar) < 0.5)

        harness.settings.hiddenPanelStatusItems = Set(PanelStatusItem.allCases)
        let expectedWithoutBar = harness.panel.frame.height
            - PanelSizing.chromeHeight(titleBarHeight: titleBarHeight, isStatusBarVisible: false)
        #expect(harness.settle { abs((harness.editorHeight ?? 0) - expectedWithoutBar) < 0.5 })
    }
}
