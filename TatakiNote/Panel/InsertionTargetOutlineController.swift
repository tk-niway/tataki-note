import AppKit

/// 挿入先の入力欄を囲む枠線の窓を出し入れする。
final class InsertionTargetOutlineController {
    private let outline: InsertionTargetOutlineModel
    private let settings: AppSettings
    private let panelModel: PanelModel
    private let panel: NSWindow
    private let window: InsertionTargetOutlineWindow
    private let primaryScreenHeight: () -> CGFloat?

    init(
        outline: InsertionTargetOutlineModel,
        settings: AppSettings,
        panelModel: PanelModel,
        panel: NSWindow,
        window: InsertionTargetOutlineWindow = InsertionTargetOutlineWindow(),
        primaryScreenHeight: @escaping () -> CGFloat? = { ScreenCoordinates.primaryScreenFrame?.height }
    ) {
        self.outline = outline
        self.settings = settings
        self.panelModel = panelModel
        self.panel = panel
        self.window = window
        self.primaryScreenHeight = primaryScreenHeight
        observeChanges()
    }

    /// 枠線の窓を出すか。
    static func shouldShow(isPanelPresented: Bool, isOutlineEnabled: Bool, rect: CGRect?) -> Bool {
        isPanelPresented && isOutlineEnabled && rect != nil
    }

    /// 今の状態に合わせて窓を出す・動かす・消す。
    func update() {
        guard Self.shouldShow(
            isPanelPresented: panelModel.isPresented,
            isOutlineEnabled: settings.isInsertionTargetOutlineActive,
            rect: outline.rect
        ), let rect = outline.rect, let screenHeight = primaryScreenHeight() else {
            window.orderOut(nil)
            return
        }
        let frame = InsertionTargetOutlineGeometry.windowFrame(
            outlineRect: rect,
            primaryScreenHeight: screenHeight,
            outset: InsertionTargetOutlineWindow.outset
        )
        if window.frame != frame {
            window.setFrame(frame, display: true, animate: false)
        }
        if panel.isVisible {
            window.order(.below, relativeTo: panel.windowNumber)
        } else {
            window.orderFrontRegardless()
        }
    }

    private func observeChanges() {
        observeRepeatedly(
            tracking: { [weak self] in
                _ = self?.outline.rect
                _ = self?.settings.appMode
                _ = self?.settings.isInsertionTargetOutlineShown
                _ = self?.panelModel.isPresented
            },
            onChange: { [weak self] in
                guard let self else { return false }
                self.update()
                return true
            }
        )
    }
}
