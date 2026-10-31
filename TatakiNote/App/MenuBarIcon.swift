import AppKit

/// メニューバーのアイコンの画像。
enum MenuBarIcon {
    /// アセットカタログでの名前。
    static let assetName = "MenuBarIcon"

    private static let iconSize = NSSize(width: 18, height: 18)
    private static let badgeCenter = NSPoint(x: 15, y: 3)
    private static let badgeRadius: CGFloat = 3
    private static let badgeGap: CGFloat = 1

    /// 文中に並べるための、指定の高さのテンプレート画像。アセットが無ければ `nil`。
    static func inlineImage(height: CGFloat) -> NSImage? {
        guard let source = NSImage(named: assetName), let image = source.copy() as? NSImage else { return nil }
        image.size = NSSize(width: height, height: height)
        image.isTemplate = true
        return image
    }

    /// 新しい版があるかに応じたメニューバーのアイコン。共有のアセットの画像は変えない。
    static func image(isUpdatePending: Bool) -> NSImage {
        isUpdatePending ? badgedImage() : plainImage()
    }

    /// 右上に印の点を重ねたテンプレート画像。点の周りは透明に抜く。
    static func badgedImage() -> NSImage {
        let base = plainImage()
        let image = NSImage(size: base.size, flipped: true) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.current?.compositingOperation = .clear
            circle(radius: badgeRadius + badgeGap).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            circle(radius: badgeRadius).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func plainImage() -> NSImage {
        guard let source = NSImage(named: assetName), let image = source.copy() as? NSImage else {
            let empty = NSImage(size: iconSize)
            empty.isTemplate = true
            return empty
        }
        image.isTemplate = true
        return image
    }

    private static func circle(radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(
            x: badgeCenter.x - radius,
            y: badgeCenter.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}
