// @note p0-1500
import AppKit

let iconDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let outDir = iconDir.deletingLastPathComponent()
    .appendingPathComponent("TatakiNote/Assets.xcassets/MenuBarIcon.imageset")

// @note p0-1501
let canvas: CGFloat = 18
let sheet = CGSize(width: 10, height: 12.5)
let backCenter = CGPoint(x: 7.6, y: 7.9) // @note p0-1502
let frontCenter = CGPoint(x: 9.9, y: 9.7)
let corner: CGFloat = 2.2
let gap: CGFloat = 0.9
let dotOffset = CGPoint(x: 1.4, y: 2.4) // @note p0-1503
let dotRadius: CGFloat = 1.5

func sheetPath(center: CGPoint, rotation degrees: CGFloat, outset: CGFloat = 0) -> CGPath {
    let rect = CGRect(x: -sheet.width / 2 - outset, y: -sheet.height / 2 - outset,
                      width: sheet.width + outset * 2, height: sheet.height + outset * 2)
    var transform = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: degrees * .pi / 180)
    return CGPath(roundedRect: rect, cornerWidth: corner + outset, cornerHeight: corner + outset, transform: &transform)
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var images: [[String: String]] = []
for scale in [1, 2] {
    let pixels = Int(canvas) * scale
    let name = scale == 1 ? "menubar.png" : "menubar@2x.png"
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { exit(1) }
    // @note p0-1504
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
    ctx.setShouldAntialias(true)

    // @note p0-1505
    ctx.setFillColor(CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(sheetPath(center: backCenter, rotation: -12))
    ctx.fillPath()

    // @note p0-1506
    ctx.setBlendMode(.clear)
    ctx.addPath(sheetPath(center: frontCenter, rotation: 6, outset: gap))
    ctx.fillPath()

    // @note p0-1507
    ctx.setBlendMode(.normal)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(sheetPath(center: frontCenter, rotation: 6))
    ctx.fillPath()

    // @note p0-1508
    ctx.saveGState()
    ctx.translateBy(x: frontCenter.x, y: frontCenter.y)
    ctx.rotate(by: 6 * .pi / 180)
    ctx.setBlendMode(.clear)
    ctx.fillEllipse(in: CGRect(x: dotOffset.x - dotRadius, y: dotOffset.y - dotRadius,
                               width: dotRadius * 2, height: dotRadius * 2))
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!
        .write(to: outDir.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x"])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["author": "xcode", "version": 1],
    "properties": ["template-rendering-intent": "template"],
]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
print("書き出しました: \(outDir.path)")
