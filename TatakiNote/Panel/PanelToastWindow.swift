import AppKit
import SwiftUI

/// 挿入・送信のトーストを描く、キーにならずクリックを受けない透明な窓。
final class PanelToastWindow: NSPanel {
    /// カプセルの外側に取る余白。影が切れないようにする。
    static let margin: CGFloat = 24

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
        identifier = NSUserInterfaceItemIdentifier("insertionToast")
    }

    /// 文を差し替えて表示を作り直し、窓に必要な大きさを返す。
    func present(message: String) -> CGSize {
        let hostingView = NSHostingView(rootView: PanelToastView(message: message).padding(Self.margin))
        let size = hostingView.fittingSize
        hostingView.sizingOptions = []
        contentView = hostingView
        return size
    }
}
