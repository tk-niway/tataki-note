import CoreGraphics
import Observation

/// @note p0-315
@Observable final class PanelDefaultSizeModel {
    /// @note p0-316
    static let initialSize: CGSize = PanelMetrics.defaultSize
    /// @note p0-317
    static let widthRange: ClosedRange<Int> = integerRange(PanelMetrics.defaultWidthRange)
    /// @note p0-318
    static let heightRange: ClosedRange<Int> = integerRange(PanelMetrics.defaultHeightRange)
    /// @note p0-319
    static let step = 10

    @ObservationIgnored private let settings: AppSettings
    /// @note p0-320
    @ObservationIgnored private let currentPanelSize: () -> CGSize?

    init(settings: AppSettings, currentPanelSize: @escaping () -> CGSize?) {
        self.settings = settings
        self.currentPanelSize = currentPanelSize
    }

    // @note p0-321

    /// @note p0-322
    var width: Int {
        get { Int(settings.panelDefaultWidth.rounded()) }
        set { settings.panelDefaultWidth = Double(newValue) }
    }

    /// @note p0-323
    var height: Int {
        get { Int(settings.panelDefaultHeight.rounded()) }
        set { settings.panelDefaultHeight = Double(newValue) }
    }

    /// @note p0-324
    var canUseCurrentPanelSize: Bool {
        currentPanelSize() != nil
    }

    /// @note p0-325
    func useCurrentPanelSize() {
        guard let size = currentPanelSize() else { return }
        // @note p0-326
        settings.panelDefaultWidth = Double(size.width).rounded()
        settings.panelDefaultHeight = Double(size.height).rounded()
    }

    /// @note p0-327
    func resetToInitial() {
        width = Int(Self.initialSize.width)
        height = Int(Self.initialSize.height)
    }

    /// @note p0-328
    private static func integerRange(_ range: ClosedRange<Double>) -> ClosedRange<Int> {
        Int(range.lowerBound.rounded(.up))...Int(range.upperBound.rounded(.down))
    }
}
