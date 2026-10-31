import AppKit

/// パネルの窓の大きさ。サイドバーの開閉に合わせて枠を変え、利用者のドラッグで決めた大きさを覚える。
final class PanelSizeController {
    /// ドラッグで決めた大きさと、開くときの大きさ。
    let sizing: PanelSizing
    /// サイドバーの開閉で窓の枠を変えている間か。
    var isAdjustingFrameForSidebar = false

    private let panel: NSWindow
    private let sidebarModel: SidebarModel
    private let animator: PanelFrameAnimating
    private let visibleFrame: (NSWindow) -> CGRect
    private var liveResizeStartSize: CGSize?
    private var resizeStartSize: CGSize?
    private var sidebarSlide: SidebarSlide?
    private var sidebarSlideGeneration = 0

    private struct SidebarSlide {
        let generation: Int
        let frame: NSRect
        let isOpen: Bool
    }

    /// サイドバーの開閉の動きの途中か。
    var isSidebarSliding: Bool { sidebarSlide != nil }

    init(
        panel: NSWindow,
        sidebarModel: SidebarModel,
        animator: PanelFrameAnimating,
        sizing: PanelSizing = PanelSizing(),
        visibleFrame: @escaping (NSWindow) -> CGRect = {
            $0.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? $0.frame.insetBy(dx: -SidebarLayout.width, dy: 0)
        }
    ) {
        self.panel = panel
        self.sidebarModel = sidebarModel
        self.animator = animator
        self.sizing = sizing
        self.visibleFrame = visibleFrame
    }

    // MARK: - サイドバー

    /// サイドバーを開閉する。パネルが開いていれば窓の枠をサイドバーの幅だけ変え、動きが表示中でアニメーションがオンなら滑らせる。
    func setSidebarOpen(_ isOpen: Bool, isPanelPresented: Bool, isAnimationEnabled: Bool, motionPhase: PanelMotionPhase) {
        finishSidebarSlide()
        let wasOpen = sidebarModel.isOpen
        guard isOpen != wasOpen else { return }
        guard isPanelPresented else {
            sidebarModel.setOpen(isOpen)
            applyMinimumSize()
            return
        }
        if isAnimationEnabled, motionPhase == .shown {
            slideSidebar(open: isOpen)
            return
        }
        isAdjustingFrameForSidebar = true
        defer { isAdjustingFrameForSidebar = false }
        if isOpen {
            let frame = SidebarLayout.expandedFrame(bodyFrame: panel.frame, visibleFrame: visibleFrame(panel))
            panel.setFrame(frame, display: true, animate: false)
            sidebarModel.setOpen(true)
            applyMinimumSize()
        } else {
            sidebarModel.setOpen(false)
            applyMinimumSize()
            panel.setFrame(SidebarLayout.collapsedFrame(expandedFrame: panel.frame), display: true, animate: false)
        }
    }

    private func slideSidebar(open isOpen: Bool) {
        let target = isOpen
            ? SidebarLayout.expandedFrame(bodyFrame: panel.frame, visibleFrame: visibleFrame(panel))
            : SidebarLayout.collapsedFrame(expandedFrame: panel.frame)
        sidebarSlideGeneration += 1
        let generation = sidebarSlideGeneration
        sidebarSlide = SidebarSlide(generation: generation, frame: target, isOpen: isOpen)
        isAdjustingFrameForSidebar = true
        sidebarModel.slidingBodyWidth = isOpen ? target.width - SidebarLayout.width : target.width
        if isOpen {
            sidebarModel.setOpen(true)
        } else {
            panel.contentMinSize = SidebarLayout.minimumWindowSize(isSidebarOpen: false)
        }
        animator.animate(panel, to: target, duration: PanelMotion.duration, curve: isOpen ? .easeOut : .easeIn) { [weak self] in
            guard let self, let slide = self.sidebarSlide, slide.generation == generation else { return }
            self.sidebarSlide = nil
            self.completeSidebarSlide(isOpen: slide.isOpen)
        }
    }

    /// サイドバーの開閉の動きの途中なら、最後の枠へ跳ばして終える。
    func finishSidebarSlide() {
        guard let slide = sidebarSlide else { return }
        sidebarSlide = nil
        animator.jump(panel, to: slide.frame)
        completeSidebarSlide(isOpen: slide.isOpen)
    }

    private func completeSidebarSlide(isOpen: Bool) {
        sidebarModel.setOpen(isOpen)
        sidebarModel.slidingBodyWidth = nil
        isAdjustingFrameForSidebar = false
        applyMinimumSize()
    }

    /// サイドバーの開閉に合わせた最小の大きさを窓に入れる。
    func applyMinimumSize() {
        panel.contentMinSize = SidebarLayout.minimumWindowSize(isSidebarOpen: sidebarModel.isOpen)
    }

    // MARK: - 大きさ

    func windowWillStartLiveResize(motionPhase: PanelMotionPhase) {
        guard !isAdjustingFrameForSidebar, motionPhase != .opening, motionPhase != .closing else { return }
        liveResizeStartSize = bodySize(of: panel.frame.size)
    }

    func windowDidEndLiveResize() {
        defer { liveResizeStartSize = nil }
        guard !isAdjustingFrameForSidebar, let startSize = liveResizeStartSize else { return }
        sizing.userDidResize(from: startSize, to: bodySize(of: panel.frame.size))
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize, motionPhase: PanelMotionPhase) -> NSSize {
        if motionPhase == .opening || isSidebarSliding {
            return frameSize
        }
        if !sender.inLiveResize, motionPhase == .shown, !isAdjustingFrameForSidebar, resizeStartSize == nil {
            resizeStartSize = bodySize(of: sender.frame.size)
        }
        let minimum = SidebarLayout.minimumWindowSize(isSidebarOpen: sidebarModel.isOpen)
        return NSSize(
            width: max(frameSize.width, minimum.width),
            height: max(frameSize.height, minimum.height)
        )
    }

    func windowDidResize(motionPhase: PanelMotionPhase) {
        guard let startSize = resizeStartSize else { return }
        resizeStartSize = nil
        guard motionPhase == .shown, !isAdjustingFrameForSidebar, !isSidebarSliding else { return }
        sizing.userDidResize(from: startSize, to: bodySize(of: panel.frame.size))
    }

    private func bodySize(of windowSize: CGSize) -> CGSize {
        SidebarLayout.bodySize(windowSize: windowSize, isSidebarOpen: sidebarModel.isOpen)
    }
}
