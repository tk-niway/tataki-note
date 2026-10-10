import AppKit

/// メニューバーのアイコンの画像。
enum MenuBarIcon {
    /// アセットカタログでの名前。
    static let assetName = "MenuBarIcon"

    /// 文中に並べるための、指定の高さのテンプレート画像。アセットが無ければ `nil`。
    static func inlineImage(height: CGFloat) -> NSImage? {
        guard let source = NSImage(named: assetName), let image = source.copy() as? NSImage else { return nil }
        image.size = NSSize(width: height, height: height)
        image.isTemplate = true
        return image
    }
}
