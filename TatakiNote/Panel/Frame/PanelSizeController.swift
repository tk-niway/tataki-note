import AppKit

/// パネルの窓の大きさ。サイドバーの開閉に合わせて枠を変え、利用者のドラッグで決めた大きさを覚える。
final class PanelSizeController {
    /// ドラッグで決めた大きさと、開くときの大きさ。
    let sizing: PanelSizing
    /// サイドバーの開閉で窓の枠を変えている間か。
    var isAdjustingFrameForSidebar = false
    /// 検索バーの高さに合わせて窓の枠を変えている間か。
    var isAdjustingFrameForFindBar = false
    /// 窓を実際に伸ばしている検索バーの高さ。
    private(set) var findBarHeight: CGFloat = 0

    private let panel: NSWindow
    private let sidebarModel: SidebarModel
    private let animator: PanelFrameAnimating
    private let visibleFrame: (NSWindow) -> CGRect
    private var liveResizeStartSize: CGSize?
    private var resizeStartSize: CGSize?
    private var sidebarSlide: SidebarSlide?
    private var sidebarSlideGeneration = 0
    private var findBarUpwardShift: CGFloat = 0

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
            panel.contentMinSize = minimumWindowSize(isSidebarOpen: false)
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
        panel.contentMinSize = minimumWindowSize(isSidebarOpen: sidebarModel.isOpen)
    }

    // MARK: - 検索バー

    /// 窓の高さを、検索バーの高さに合わせる。足りない分は下へ伸ばし、収まらなければ上へずらす。ドラッグで決めた大きさとしては覚えない。
    func syncFindBarHeight(_ desired: CGFloat) {
        let delta = desired - findBarHeight
        guard delta != 0 else { return }
        finishSidebarSlide()
        isAdjustingFrameForFindBar = true
        defer { isAdjustingFrameForFindBar = false }
        let change = FindBarFrame.resized(
            panel.frame,
            by: delta,
            upwardShift: findBarUpwardShift,
            visibleFrame: visibleFrame(panel)
        )
        findBarUpwardShift = change.upwardShift
        if change.appliedDelta < 0 {
            findBarHeight += change.appliedDelta
            applyMinimumSize()
            panel.setFrame(change.frame, display: true, animate: false)
        } else {
            findBarHeight += change.appliedDelta
            panel.setFrame(change.frame, display: true, animate: false)
            applyMinimumSize()
        }
    }

    /// 上へずらした量を忘れる。窓を新しい位置に置き直すときに呼ぶ。
    func resetFindBarShift() {
        findBarUpwardShift = 0
    }

    /// 開くときの窓の大きさ。覚えた大きさに検索バーの分を足す。
    func openingSize(in visibleFrame: CGRect, findBarHeight desired: CGFloat) -> CGSize {
        let result = FindBarFrame.openingSize(
            bodySize: sizing.openingSize(in: visibleFrame),
            barHeight: desired,
            visibleFrame: visibleFrame
        )
        findBarHeight = result.appliedBarHeight
        findBarUpwardShift = 0
        return result.size
    }

    // MARK: - 大きさ

    func windowWillStartLiveResize(motionPhase: PanelMotionPhase) {
        guard !isAdjustingFrameForSidebar, !isAdjustingFrameForFindBar,
              motionPhase != .opening, motionPhase != .closing else { return }
        liveResizeStartSize = bodySize(of: panel.frame.size)
    }

    func windowDidEndLiveResize() {
        defer { liveResizeStartSize = nil }
        guard !isAdjustingFrameForSidebar, !isAdjustingFrameForFindBar, let startSize = liveResizeStartSize else { return }
        sizing.userDidResize(from: startSize, to: bodySize(of: panel.frame.size))
    }

    /// 修飾キーでのサイズ変更で窓の大きさが変わったことを、ドラッグで決めた大きさとして覚える。
    func recordPointerResize(fromWindowSize: CGSize, toWindowSize: CGSize) {
        sizing.userDidResize(from: bodySize(of: fromWindowSize), to: bodySize(of: toWindowSize))
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize, motionPhase: PanelMotionPhase) -> NSSize {
        if motionPhase == .opening || isSidebarSliding {
            return frameSize
        }
        if !sender.inLiveResize, motionPhase == .shown, !isAdjustingFrameForSidebar, !isAdjustingFrameForFindBar,
           resizeStartSize == nil {
            resizeStartSize = bodySize(of: sender.frame.size)
        }
        let minimum = minimumWindowSize(isSidebarOpen: sidebarModel.isOpen)
        return NSSize(
            width: max(frameSize.width, minimum.width),
            height: max(frameSize.height, minimum.height)
        )
    }

    func windowDidResize(motionPhase: PanelMotionPhase) {
        guard let startSize = resizeStartSize else { return }
        resizeStartSize = nil
        guard motionPhase == .shown, !isAdjustingFrameForSidebar, !isAdjustingFrameForFindBar, !isSidebarSliding else { return }
        sizing.userDidResize(from: startSize, to: bodySize(of: panel.frame.size))
    }

    private func bodySize(of windowSize: CGSize) -> CGSize {
        var body = SidebarLayout.bodySize(windowSize: windowSize, isSidebarOpen: sidebarModel.isOpen)
        body.height -= findBarHeight
        return body
    }

    private func minimumWindowSize(isSidebarOpen: Bool) -> CGSize {
        FindBarFrame.minimumSize(SidebarLayout.minimumWindowSize(isSidebarOpen: isSidebarOpen), barHeight: findBarHeight)
    }
}
