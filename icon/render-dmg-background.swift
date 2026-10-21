import AppKit

let canvas = NSSize(width: 660, height: 400)
let arrowColor = NSColor(srgbRed: 0x7A / 255, green: 0x9A / 255, blue: 0x52 / 255, alpha: 1)
let captionColor = NSColor(srgbRed: 0x3F / 255, green: 0x4A / 255, blue: 0x33 / 255, alpha: 1)
let gradientTop = NSColor(srgbRed: 0xFB / 255, green: 0xFC / 255, blue: 0xF6 / 255, alpha: 1)
let gradientBottom = NSColor(srgbRed: 0xEE / 255, green: 0xF3 / 255, blue: 0xE3 / 255, alpha: 1)
let caption = "TatakiNote を「アプリケーション」フォルダへドラッグしてください"

func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status)
}

func render(scale: Int) -> Data? {
    let pixelsWide = Int(canvas.width) * scale
    let pixelsHigh = Int(canvas.height) * scale
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let bitmapContext = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    rep.size = canvas

    let cg = bitmapContext.cgContext
    cg.translateBy(x: 0, y: CGFloat(pixelsHigh))
    cg.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    if let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [gradientTop.cgColor, gradientBottom.cgColor] as CFArray,
        locations: [0, 1]
    ) {
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: canvas.height),
            options: []
        )
    }

    cg.setStrokeColor(arrowColor.cgColor)
    cg.setLineWidth(5)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)

    cg.saveGState()
    cg.setLineDash(phase: 0, lengths: [0.1, 12])
    cg.move(to: CGPoint(x: 262, y: 190))
    cg.addCurve(
        to: CGPoint(x: 398, y: 190),
        control1: CGPoint(x: 300, y: 165),
        control2: CGPoint(x: 360, y: 165)
    )
    cg.strokePath()
    cg.restoreGState()

    cg.move(to: CGPoint(x: 384, y: 176))
    cg.addLine(to: CGPoint(x: 400, y: 191))
    cg.addLine(to: CGPoint(x: 380, y: 197))
    cg.strokePath()

    let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: captionColor]
    let text = NSAttributedString(string: caption, attributes: attributes)
    let textSize = text.size()
    text.draw(at: NSPoint(x: canvas.width / 2 - textSize.width / 2, y: 330 - font.ascender))

    return rep.representation(using: .png, properties: [:])
}

guard CommandLine.arguments.count == 2 else {
    fail("使い方: swift render-dmg-background.swift <出力先のフォルダ>", status: 2)
}
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    for (scale, name) in [(1, "background.png"), (2, "background@2x.png")] {
        guard let png = render(scale: scale) else { fail("背景を描けませんでした(\(scale)x)") }
        let url = outputDirectory.appendingPathComponent(name)
        try png.write(to: url)
        print("書き出しました: \(url.path)")
    }
} catch {
    fail("背景を書き出せませんでした: \(error.localizedDescription)")
}
