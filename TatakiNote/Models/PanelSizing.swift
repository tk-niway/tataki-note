import CoreGraphics
import Observation

/// パネルの大きさの状態(ドラッグで決めた大きさ・開いたときの既定の大きさ)と、大きさの計算。
@Observable final class PanelSizing {
    static let minimumSize = PanelMetrics.minimumSize
    static let dividerThickness: CGFloat = 1

    private(set) var heldSize: CGSize?

    private(set) var openedDefaultSize: CGSize = PanelMetrics.defaultSize

    var baseSize: CGSize { heldSize ?? openedDefaultSize }

    func beginOpening(defaultSize: CGSize) {
        openedDefaultSize = defaultSize
    }

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

    func handleCommitOutcome(_ outcome: CommitOutcome) {
        guard outcome == .inserted, heldSize != nil else { return }
        heldSize = nil
    }

    // MARK: - 計算

    static func chromeHeight(titleBarHeight: CGFloat, isStatusBarVisible: Bool) -> CGFloat {
        titleBarHeight + (isStatusBarVisible ? dividerThickness + PanelMetrics.statusBarHeight : 0)
    }

    func openingSize(in visibleFrame: CGRect) -> CGSize {
        PanelPlacement.fittedSize(baseSize, in: visibleFrame)
    }
}
