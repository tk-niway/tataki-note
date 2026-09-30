import CoreGraphics
import Observation

/// @note p0-412
@Observable final class PanelSizing {
    /// @note p0-413
    static let minimumSize = PanelMetrics.minimumSize
    /// @note p0-414
    static let dividerThickness: CGFloat = 1

    /// @note p0-415
    private(set) var heldSize: CGSize?

    /// @note p0-416
    private(set) var openedDefaultSize: CGSize = PanelMetrics.defaultSize

    /// @note p0-417
    var baseSize: CGSize { heldSize ?? openedDefaultSize }

    /// @note p0-418
    func beginOpening(defaultSize: CGSize) {
        openedDefaultSize = defaultSize
    }

    /// @note p0-419
    func userDidResize(from startSize: CGSize, to endSize: CGSize) {
        guard endSize != startSize else { return }
        var size = baseSize
        if endSize.width != startSize.width {
            size.width = max(endSize.width, Self.minimumSize.width)
        }
        if endSize.height != startSize.height {
            size.height = max(endSize.height, Self.minimumSize.height)
        }
        if heldSize != size {
            heldSize = size
        }
    }

    /// @note p0-420
    func handleCommitOutcome(_ outcome: CommitOutcome) {
        guard outcome == .inserted, heldSize != nil else { return }
        heldSize = nil
    }

    // MARK: - 計算

    /// @note p0-421
    static func chromeHeight(titleBarHeight: CGFloat, isStatusBarVisible: Bool) -> CGFloat {
        titleBarHeight + (isStatusBarVisible ? dividerThickness + PanelMetrics.statusBarHeight : 0)
    }

    /// @note p0-422
    func openingSize(in visibleFrame: CGRect) -> CGSize {
        CGSize(width: min(baseSize.width, visibleFrame.width), height: min(baseSize.height, visibleFrame.height))
    }
}
