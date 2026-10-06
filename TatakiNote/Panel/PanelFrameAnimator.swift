import AppKit

/// 動きの速さの変え方。
enum PanelMotionCurve {
    case easeOut
    case easeIn
}

/// 窓の枠を動かす。
protocol PanelFrameAnimating {
    /// `window` の枠を `duration` 秒で `frame` まで動かし、終わったら `completion` を呼ぶ。
    func animate(_ window: NSWindow, to frame: NSRect, duration: TimeInterval, curve: PanelMotionCurve, completion: @escaping () -> Void)
    /// 走っている動きを止めて、`window` の枠をすぐに `frame` にする。
    func jump(_ window: NSWindow, to frame: NSRect)
}

/// AppKit のアニメーションで窓の枠を動かす。
struct AppKitPanelFrameAnimator: PanelFrameAnimating {
    func animate(_ window: NSWindow, to frame: NSRect, duration: TimeInterval, curve: PanelMotionCurve, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: curve == .easeOut ? .easeOut : .easeIn)
            window.animator().setFrame(frame, display: true)
        }, completionHandler: completion)
    }

    func jump(_ window: NSWindow, to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.animator().setFrame(frame, display: false)
        }
        window.setFrame(frame, display: false)
    }
}
