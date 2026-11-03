import AppKit

/// パネルの開閉の動き。開くときは線から広げ、閉じるときは窓の写しを線へ縮める。
final class PanelMotionController {
    private let panel: NSWindow
    private let animator: PanelFrameAnimating
    private let restoreMinimumSize: () -> Void
    private let makeGhost: (NSWindow) -> NSWindow?

    private var motion = PanelMotionState()
    private var restingFrame: NSRect?
    private var pendingCloseCompletion: (() -> Void)?
    private var closingGhost: NSWindow?

    /// 今の動きの段階。
    var phase: PanelMotionPhase { motion.phase }

    init(
        panel: NSWindow,
        animator: PanelFrameAnimating,
        restoreMinimumSize: @escaping () -> Void,
        makeGhost: @escaping (NSWindow) -> NSWindow? = { PanelClosingGhost.make(from: $0) }
    ) {
        self.panel = panel
        self.animator = animator
        self.restoreMinimumSize = restoreMinimumSize
        self.makeGhost = makeGhost
    }

    /// パネルを `restFrame` で前に出す。アニメーションがオンなら線から広げる。
    func present(at restFrame: NSRect, isAnimationEnabled: Bool) {
        guard isAnimationEnabled else {
            restoreMinimumSize()
            panel.makeKeyAndOrderFront(nil)
            motion.showWithoutMotion()
            pendingCloseCompletion = nil
            restingFrame = nil
            return
        }
        panel.contentMinSize = NSSize(width: 1, height: 1)
        restingFrame = restFrame
        panel.setFrame(PanelMotion.lineFrame(of: restFrame), display: false)
        panel.makeKeyAndOrderFront(nil)
        let token = motion.beginOpening()
        pendingCloseCompletion = nil
        animator.animate(panel, to: restFrame, duration: PanelMotion.duration, curve: .easeOut) { [weak self] in
            self?.finish(token)
        }
    }

    /// パネルを隠す。アニメーションがオンで見えていれば、写しを線へ縮めてから `completion` を呼ぶ。
    func hide(isAnimationEnabled: Bool, then completion: (() -> Void)? = nil) {
        guard isAnimationEnabled, motion.phase != .hidden else {
            hideWithoutMotion()
            completion?()
            return
        }
        if motion.phase == .closing { return }
        guard let ghost = makeGhost(panel) else {
            hideWithoutMotion()
            completion?()
            return
        }
        let wasOpening = motion.phase == .opening
        let panelFrame = wasOpening ? (restingFrame ?? panel.frame) : panel.frame
        let token = motion.beginClosing()
        pendingCloseCompletion = completion
        restingFrame = nil
        closingGhost = ghost
        ghost.orderFrontRegardless()
        panel.orderOut(nil)
        if wasOpening {
            animator.jump(panel, to: panelFrame)
        }
        restoreMinimumSize()
        animator.animate(
            ghost,
            to: PanelMotion.lineFrame(of: ghost.frame),
            duration: PanelMotion.duration,
            curve: .easeIn
        ) { [weak self] in
            if let self {
                self.finish(token)
            } else {
                ghost.orderOut(nil)
            }
        }
    }

    /// 動きなしでパネルを隠し、開く途中なら枠を本来の枠に戻す。
    func hideWithoutMotion() {
        discardGhost()
        motion.hideWithoutMotion()
        pendingCloseCompletion = nil
        panel.orderOut(nil)
        if let frame = restingFrame {
            restingFrame = nil
            animator.jump(panel, to: frame)
        }
        restoreMinimumSize()
    }

    /// 開く・閉じる動きの途中なら、動きなしで止める。開く途中なら本来の枠へ跳ばす。
    func stop() {
        guard motion.phase == .opening || motion.phase == .closing else { return }
        let wasOpening = motion.phase == .opening
        discardGhost()
        motion.hideWithoutMotion()
        pendingCloseCompletion = nil
        let frame = restingFrame ?? panel.frame
        restingFrame = nil
        if wasOpening {
            animator.jump(panel, to: frame)
        }
    }

    private func finish(_ token: Int) {
        guard motion.finish(token) else { return }
        switch motion.phase {
        case .shown:
            restingFrame = nil
            restoreMinimumSize()
        case .hidden:
            discardGhost()
            let completion = pendingCloseCompletion
            pendingCloseCompletion = nil
            completion?()
        case .opening, .closing:
            break
        }
    }

    private func discardGhost() {
        closingGhost?.orderOut(nil)
        closingGhost = nil
    }
}
