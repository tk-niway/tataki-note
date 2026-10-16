import AppKit

/// プロンプトを書くパネル。
final class PromptPanel: NSPanel {
    /// ビューの階層が受けなかった `⌘K` `⌘S` `⌘N` を受け取る処理。処理したら `true` を返す。
    var onKeyEquivalent: ((PanelKeyInput) -> Bool)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        contentMinSize = PanelSizing.minimumSize

        title = "TatakiNote"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true

        identifier = NSUserInterfaceItemIdentifier("promptPanel")
        setAccessibilityIdentifier("promptPanel")
    }

    /// key のウィンドウになれるか。
    var acceptsKey = true
    /// ⌘H を受け取る処理。true を返すと標準の「隠す」には渡さない。
    var onHideKey: (() -> Bool)?

    /// 入力欄の外(一覧・検索欄)で押されたキーを受け取る処理。処理したら `true` を返す。
    var onKeyDownOutsideEditor: ((PanelKeyInput) -> Bool)?

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           !(firstResponder is PromptTextView),
           let handler = onKeyDownOutsideEditor {
            let input = PanelKeyInput(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                hasMarkedText: Self.firstResponderHasMarkedText(firstResponder),
                characters: event.charactersIgnoringModifiers?.lowercased() ?? ""
            )
            if handler(input) { return }
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           PanelHideKey.matches(modifiers: event.modifierFlags, charactersIgnoringModifiers: event.charactersIgnoringModifiers),
           onHideKey?() == true {
            return true
        }
        if super.performKeyEquivalent(with: event) {
            return true
        }
        let hasMarkedText = Self.firstResponderHasMarkedText(firstResponder)
        guard let input = Self.panelCommandInput(for: event, hasMarkedText: hasMarkedText) else {
            return false
        }
        return onKeyEquivalent?(input) ?? false
    }

    /// ファーストレスポンダーに未確定の文字があるか。
    static func firstResponderHasMarkedText(_ responder: NSResponder?) -> Bool {
        (responder as? NSTextInputClient)?.hasMarkedText() ?? false
    }

    /// `⌘K` `⌘S` `⌘N` `⌘B` `⌘,` のキーの値。どれでもなければ `nil`。
    static func panelCommandInput(for event: NSEvent, hasMarkedText: Bool) -> PanelKeyInput? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.intersection(PanelShortcut.relevantModifiers) == [.command] else { return nil }
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard ReservedPanelKeys.characters.contains(characters) else { return nil }
        return PanelKeyInput(
            keyCode: event.keyCode,
            modifiers: modifiers,
            hasMarkedText: hasMarkedText,
            characters: characters
        )
    }
}
