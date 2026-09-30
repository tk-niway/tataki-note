import AppKit

/// @note p0-493
enum PanelMetrics {
    /// @note p0-494
    static let defaultSize = CGSize(width: 520, height: 340)

    /// @note p0-495
    static let minimumSize = CGSize(width: 320, height: 160)

    /// @note p0-496
    static let maximumDefaultSize = CGSize(width: 4000, height: 4000)

    /// @note p0-497
    static let defaultWidthRange: ClosedRange<Double> = Double(minimumSize.width)...Double(maximumDefaultSize.width)

    /// @note p0-498
    static let defaultHeightRange: ClosedRange<Double> = Double(minimumSize.height)...Double(maximumDefaultSize.height)

    /// @note p0-499
    static let titleBarHeight: CGFloat = 28
    /// @note p0-500
    static let statusBarHeight: CGFloat = 28
    /// @note p0-501
    static let textContainerInset = NSSize(width: 11, height: 4)

    /// @note p0-502
    static func clampedDefaultWidth(_ width: Double) -> Double {
        guard width.isFinite else { return Double(defaultSize.width) }
        return min(max(width, defaultWidthRange.lowerBound), defaultWidthRange.upperBound)
    }

    /// @note p0-503
    static func clampedDefaultHeight(_ height: Double) -> Double {
        guard height.isFinite else { return Double(defaultSize.height) }
        return min(max(height, defaultHeightRange.lowerBound), defaultHeightRange.upperBound)
    }
}
