import AppKit
import SwiftUI

/// 挿入先の入力欄を囲む枠線を描く、クリックを受けない透明な窓。
class InsertionTargetOutlineWindow: NSPanel {
    /// 枠線が入力欄の外へ出る幅。
    static let outset: CGFloat = 4

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        identifier = NSUserInterfaceItemIdentifier("insertionTargetOutline")

        let hostingView = NSHostingView(rootView: InsertionTargetOutlineView())
        hostingView.sizingOptions = []
        contentView = hostingView
    }
}
