import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct MenuBarIconTests {
    private let scale = 2

    private func render(_ image: NSImage) throws -> NSBitmapImageRep {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(image.size.width) * scale,
            pixelsHigh: Int(image.size.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = image.size
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func alpha(_ rep: NSBitmapImageRep, x: Int, y: Int) throws -> CGFloat {
        try #require(rep.colorAt(x: x, y: y)).alphaComponent
    }

    @Test("AC-8: 新しいバージョンが無いときは、テンプレートで18ptのふだんの画像になる")
    func plainImage() throws {
        let image = MenuBarIcon.image(isUpdatePending: false)

        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
    }

    @Test("AC-8: 新しいバージョンがあるときは、テンプレートでふだんと同じ大きさの印の付いた画像になる")
    func badgedImageIsTemplateWithSameSize() throws {
        let plain = MenuBarIcon.image(isUpdatePending: false)
        let badged = MenuBarIcon.image(isUpdatePending: true)

        #expect(badged.isTemplate)
        #expect(badged.size == plain.size)
        #expect(MenuBarIcon.badgedImage().isTemplate)
        #expect(MenuBarIcon.badgedImage().size == plain.size)
    }

    @Test("AC-8: 印の画像は、右上に点があり、その周りは透明に抜けていて、ふだんの画像と画素が違う")
    func badgedImageDrawsDotWithClearRing() throws {
        let plain = try render(MenuBarIcon.image(isUpdatePending: false))
        let badged = try render(MenuBarIcon.image(isUpdatePending: true))

        #expect(try alpha(badged, x: 30, y: 6) > 0.9)
        #expect(try alpha(badged, x: 23, y: 6) == 0)
        let plainBytes = Data(bytes: try #require(plain.bitmapData), count: plain.bytesPerRow * plain.pixelsHigh)
        let badgedBytes = Data(bytes: try #require(badged.bitmapData), count: badged.bytesPerRow * badged.pixelsHigh)
        #expect(plainBytes != badgedBytes)
    }

    @Test("AC-8: どちらの画像を作った後も、共有のアセットの画像の大きさとテンプレートの設定は元のまま")
    func sharedAssetImageIsUntouched() throws {
        let source = try #require(NSImage(named: MenuBarIcon.assetName))
        let originalSize = source.size
        let originalIsTemplate = source.isTemplate

        let plain = MenuBarIcon.image(isUpdatePending: false)
        let badged = MenuBarIcon.image(isUpdatePending: true)
        plain.size = NSSize(width: 40, height: 40)
        plain.isTemplate = !originalIsTemplate
        _ = try render(badged)

        let sourceAfter = try #require(NSImage(named: MenuBarIcon.assetName))
        #expect(sourceAfter === source)
        #expect(plain !== sourceAfter)
        #expect(badged !== sourceAfter)
        #expect(sourceAfter.size == originalSize)
        #expect(sourceAfter.size == NSSize(width: 18, height: 18))
        #expect(sourceAfter.isTemplate == originalIsTemplate)
    }
}
