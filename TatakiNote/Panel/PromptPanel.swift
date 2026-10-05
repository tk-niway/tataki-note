import AppKit

/// プロンプトを書くパネル。
final class PromptPanel: NSPanel {
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

    /// key のウィンドウになれるか。閉じる動きの間は false にする。
    var acceptsKey = true
    /// ⌘H を受け取る処理。true を返すと標準の「隠す」には渡さない。
    var onHideKey: (() -> Bool)?

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           PanelHideKey.matches(modifiers: event.modifierFlags, charactersIgnoringModifiers: event.charactersIgnoringModifiers),
           onHideKey?() == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
