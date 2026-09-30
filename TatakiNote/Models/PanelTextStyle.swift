import AppKit

/// @note p0-442
enum PanelTextStyle {
    static let defaultFontSize: Double = 14
    static let fontSizeRange: ClosedRange<Double> = 10...32

    static let defaultOpacity: Double = 1.0
    /// @note p0-443
    static let opacityRange: ClosedRange<Double> = 0.4...1.0

    /// @note p0-444
    static func clampedFontSize(_ size: Double) -> Double {
        guard size.isFinite else { return defaultFontSize }
        return min(max(size, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    /// @note p0-445
    static func clampedOpacity(_ opacity: Double) -> Double {
        guard opacity.isFinite else { return defaultOpacity }
        return min(max(opacity, opacityRange.lowerBound), opacityRange.upperBound)
    }

    /// @note p0-446
    static func font(name: String?, size: Double) -> NSFont {
        let pointSize = CGFloat(clampedFontSize(size))
        guard let name, !name.isEmpty, !name.hasPrefix(".") else {
            return .systemFont(ofSize: pointSize)
        }
        return NSFont(name: name, size: pointSize) ?? .systemFont(ofSize: pointSize)
    }
}
