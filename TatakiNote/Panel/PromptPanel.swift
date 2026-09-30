import AppKit

/// @note p0-508
final class PromptPanel: NSPanel {
    init(contentRect: NSRect) {
        // @note p0-509
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        // @note p0-510
        contentMinSize = PanelSizing.minimumSize

        title = "TatakiNote"
        titlebarAppearsTransparent = true
        // @note p0-511
        titleVisibility = .hidden
        // @note p0-512
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
