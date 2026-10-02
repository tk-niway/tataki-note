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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
