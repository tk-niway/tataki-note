import AppKit

/// 閉じる動きの間だけ出す、パネルの見た目を写した窓。キーにもマウスにも反応しない。
final class PanelClosingGhost: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `panel` の今の見た目を、同じ枠の窓に写す。写せないときは `nil`。
    static func make(from panel: NSWindow) -> PanelClosingGhost? {
        guard let image = snapshot(of: panel) else { return nil }
        let ghost = PanelClosingGhost(
            contentRect: panel.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        ghost.isOpaque = false
        ghost.backgroundColor = .clear
        ghost.hasShadow = panel.hasShadow
        ghost.alphaValue = panel.alphaValue
        ghost.appearance = panel.appearance
        ghost.isFloatingPanel = true
        ghost.level = panel.level
        ghost.collectionBehavior = panel.collectionBehavior
        ghost.hidesOnDeactivate = false
        ghost.isReleasedWhenClosed = false
        ghost.animationBehavior = .none
        ghost.ignoresMouseEvents = true

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: panel.frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        ghost.contentView = imageView
        ghost.setFrame(panel.frame, display: false)
        return ghost
    }

    private static func snapshot(of window: NSWindow) -> NSImage? {
        guard let view = window.contentView?.superview ?? window.contentView else { return nil }
        let bounds = view.bounds
        guard bounds.width >= 1, bounds.height >= 1,
              let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }
}
