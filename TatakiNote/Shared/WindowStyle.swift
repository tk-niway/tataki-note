import AppKit
import SwiftUI

/// 載せた窓に外観(テーマ)と透明度を当てる、大きさを持たないビュー。
final class WindowStyleApplierView: NSView {
    static let alphaTolerance: CGFloat = 0.001

    var appearanceName: NSAppearance.Name?

    var windowAlphaValue: CGFloat?

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

/// `WindowStyleApplierView` を SwiftUI に置くための部品。
struct WindowStyleApplier: NSViewRepresentable {
    let appearanceName: NSAppearance.Name?
    let windowAlphaValue: CGFloat?

    func makeNSView(context: Context) -> WindowStyleApplierView {
        let view = WindowStyleApplierView()
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
