import AppKit
import SwiftUI

/// @note p0-708
final class WindowStyleApplierView: NSView {
    /// @note p0-709
    static let alphaTolerance: CGFloat = 0.001

    /// @note p0-710
    var appearanceName: NSAppearance.Name?

    /// @note p0-711
    var windowAlphaValue: CGFloat?

    /// @note p0-712
    func apply() {
        guard let window else { return }
        if window.appearance?.name != appearanceName {
            window.appearance = appearanceName.flatMap { NSAppearance(named: $0) }
        }
        if let windowAlphaValue, abs(window.alphaValue - windowAlphaValue) >= Self.alphaTolerance {
            window.alphaValue = windowAlphaValue
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }
}

/// @note p0-713
struct WindowStyleApplier: NSViewRepresentable {
    let appearanceName: NSAppearance.Name?
    let windowAlphaValue: CGFloat?

    func makeNSView(context: Context) -> WindowStyleApplierView {
        let view = WindowStyleApplierView()
        // @note p0-714
        view.appearanceName = appearanceName
        view.windowAlphaValue = windowAlphaValue
        return view
    }

    func updateNSView(_ nsView: WindowStyleApplierView, context: Context) {
        nsView.appearanceName = appearanceName
        nsView.windowAlphaValue = windowAlphaValue
        nsView.apply()
    }
}

extension View {
    /// @note p0-715
    func windowStyle(theme: AppTheme, opacity: Double? = nil) -> some View {
        background {
            WindowStyleApplier(
                appearanceName: theme.appearanceName,
                windowAlphaValue: opacity.map { CGFloat(PanelTextStyle.clampedOpacity($0)) }
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }
}
