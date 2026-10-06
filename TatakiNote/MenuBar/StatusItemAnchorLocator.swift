import AppKit

/// メニューバーの TatakiNote のアイコンを載せた窓の中身を、吹き出しの出どころとして探す。
struct StatusItemAnchorLocator: StatusItemAnchorLocating {
    static let statusBarWindowClassName = "NSStatusBarWindow"

    func locateAnchor() -> NSView? {
        let windows = NSApplication.shared.windows.filter {
            String(describing: type(of: $0)) == Self.statusBarWindowClassName
                && $0.isVisible
                && !$0.frame.isEmpty
        }
        let index = StatusItemWindowChoice.index(
            windowFrames: windows.map(\.frame),
            screenFrames: NSScreen.screens.map(\.frame),
            mouseLocation: NSEvent.mouseLocation
        )
        return index.flatMap { windows[$0].contentView }
    }
}
