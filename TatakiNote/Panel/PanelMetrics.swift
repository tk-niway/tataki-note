import AppKit

/// パネルの寸法と、パネルの既定の大きさの範囲。
enum PanelMetrics {
    static let defaultSize = CGSize(width: 520, height: 340)

    static let minimumSize = CGSize(width: 320, height: 160)

    static let maximumDefaultSize = CGSize(width: 4000, height: 4000)

    static let defaultWidthRange: ClosedRange<Double> = Double(minimumSize.width)...Double(maximumDefaultSize.width)

    static let defaultHeightRange: ClosedRange<Double> = Double(minimumSize.height)...Double(maximumDefaultSize.height)

    static let titleBarHeight: CGFloat = 28
    static let statusBarHeight: CGFloat = 28
    static let textContainerInset = NSSize(width: 11, height: 4)

    static func clampedDefaultWidth(_ width: Double) -> Double {
        defaultWidthRange.clamping(width, nonFiniteFallback: Double(defaultSize.width))
    }

    static func clampedDefaultHeight(_ height: Double) -> Double {
        defaultHeightRange.clamping(height, nonFiniteFallback: Double(defaultSize.height))
    }
}
