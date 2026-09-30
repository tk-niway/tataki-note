// @note p0-1509
import AppKit

let iconDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let outDir = iconDir.appendingPathComponent("promo")
guard let icon = NSImage(contentsOf: iconDir.appendingPathComponent("AppIcon.svg")) else { exit(1) }
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let appName = "TatakiNote"
let tagline = "Enterで誤送信 対策アプリ"
let sublines = ["ホットキーで呼び出して、好きなだけEnterで変換・改行。", "⌘+Enterで送信"]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let ink = color(0x1E3A22)
let inkSub = color(0x4F6B52)

func text(_ string: String, font: NSFont, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
}
func hiragino(_ weight: String, _ size: CGFloat) -> NSFont {
    NSFont(name: "HiraginoSans-\(weight)", size: size) ?? .systemFont(ofSize: size)
}

/// @note p0-1510
func render(_ name: String, width: Int, height: Int, draw: (CGSize) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGSize(width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print("書き出しました: \(outDir.appendingPathComponent(name).path)")
}

/// @note p0-1511
func drawIcon(in rect: CGRect) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x1F4D22, 0.28)
    shadow.shadowOffset = CGSize(width: 0, height: -rect.height * 0.025)
    shadow.shadowBlurRadius = rect.height * 0.05
    shadow.set()
    icon.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

/// @note p0-1512
func drawBackground(_ size: CGSize, sheets: [(center: CGPoint, scale: CGFloat, degrees: CGFloat)]) {
    NSGradient(starting: color(0xF7FCEC), ending: color(0xE2F2CC))!
        .draw(in: CGRect(origin: .zero, size: size), angle: -35)
    for sheet in sheets {
        let w = 380 * sheet.scale, h = 460 * sheet.scale
        let path = NSBezierPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                                xRadius: 70 * sheet.scale, yRadius: 70 * sheet.scale)
        var t = AffineTransform(translationByX: sheet.center.x, byY: sheet.center.y)
        t.rotate(byDegrees: sheet.degrees)
        path.transform(using: t)
        color(0xFFFFFF, 0.55).setFill()
        path.fill()
    }
}

// @note p0-1513
try render("icon-1024.png", width: 1024, height: 1024) { size in
    drawIcon(in: CGRect(origin: .zero, size: size))
}

// @note p0-1514
try render("banner-1200x630.png", width: 1200, height: 630) { size in
    drawBackground(size, sheets: [
        (CGPoint(x: 1120, y: 560), 0.9, 18),
        (CGPoint(x: 1110, y: -30), 0.7, -12),
    ])
    let iconSize: CGFloat = 400
    drawIcon(in: CGRect(x: 60, y: (size.height - iconSize) / 2 + 6, width: iconSize, height: iconSize))
    let x: CGFloat = 480
    text(appName, font: .systemFont(ofSize: 84, weight: .bold), color: ink).draw(at: CGPoint(x: x - 4, y: 340))
    text(tagline, font: hiragino("W6", 40), color: ink).draw(at: CGPoint(x: x, y: 268))
    for (i, line) in sublines.enumerated() {
        text(line, font: hiragino("W3", 24), color: inkSub).draw(at: CGPoint(x: x, y: 214 - CGFloat(i) * 36))
    }
}

// @note p0-1515
try render("square-1080.png", width: 1080, height: 1080) { size in
    drawBackground(size, sheets: [
        (CGPoint(x: 990, y: 980), 0.9, 18),
        (CGPoint(x: -10, y: -60), 0.8, -14),
    ])
    let iconSize: CGFloat = 560
    drawIcon(in: CGRect(x: (size.width - iconSize) / 2, y: 440, width: iconSize, height: iconSize))
    for (line, y) in [
        (text(appName, font: .systemFont(ofSize: 88, weight: .bold), color: ink), CGFloat(328)),
        (text(tagline, font: hiragino("W6", 44), color: ink), CGFloat(252)),
        (text(sublines[0], font: hiragino("W3", 28), color: inkSub), CGFloat(192)),
        (text(sublines[1], font: hiragino("W3", 28), color: inkSub), CGFloat(150)),
    ] {
        line.draw(at: CGPoint(x: (size.width - line.size().width) / 2, y: y))
    }
}
