import AppKit
import SwiftUI

/// シェアのメニューの位置に使うボタンの `NSView` を覚えておく。
@MainActor
final class SharingAnchorRegistry {
    weak var view: NSView?
}

/// 中身の無い `NSView` を作り、レジストリに登録する。
struct SharingAnchorView: NSViewRepresentable {
    let registry: SharingAnchorRegistry

    func makeNSView(context: Context) -> NSView {
        let view = AnchorNSView()
        registry.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        registry.view = nsView
    }

    private final class AnchorNSView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
