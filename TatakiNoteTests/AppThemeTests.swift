import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct AppThemeTests {
    private let alphaTolerance: CGFloat = 0.001

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    @Test("AC-10: テーマの外観は、システムなら指定なし・ライトなら aqua・ダークなら darkAqua。初期値はシステム")
    func appearanceNames() {
        #expect(AppTheme.allCases == [.system, .light, .dark])
        #expect(AppTheme.defaultValue == .system)
        #expect(AppTheme.system.appearanceName == nil)
        #expect(AppTheme.light.appearanceName == .aqua)
        #expect(AppTheme.dark.appearanceName == .darkAqua)
        #expect(AppTheme.allCases.map(\.displayName) == ["システム", "ライト", "ダーク"])
    }

    @Test("AC-10: 部品を載せた窓の外観と透明度がその値になり、値を変えると変わり、システムに戻すと窓の外観の指定が外れる")
    func appliesAppearanceAndAlphaToWindow() throws {
        let window = makeWindow()
        let contentView = try #require(window.contentView)
        #expect(window.appearance == nil)

        let applier = WindowStyleApplierView()
        applier.appearanceName = AppTheme.dark.appearanceName
        applier.windowAlphaValue = 0.6
        contentView.addSubview(applier)
        #expect(window.appearance?.name == .darkAqua)
        #expect(abs(window.alphaValue - 0.6) < alphaTolerance)
        #expect(applier.alphaValue == 1.0)

        applier.appearanceName = AppTheme.light.appearanceName
        applier.windowAlphaValue = 0.4
        applier.apply()
        #expect(window.appearance?.name == .aqua)
        #expect(abs(window.alphaValue - 0.4) < alphaTolerance)

        applier.windowAlphaValue = nil
        applier.apply()
        #expect(abs(window.alphaValue - 0.4) < alphaTolerance)
        #expect(applier.alphaValue == 1.0)

        applier.apply()
        #expect(window.appearance?.name == .aqua)

        applier.appearanceName = AppTheme.system.appearanceName
        applier.apply()
        #expect(window.appearance == nil)
        #expect(abs(window.alphaValue - 0.4) < alphaTolerance)
    }

    @Test("AC-10: 透明度を指定しなければ窓の透明度に触れず、窓に載っていなければ何もしない")
    func leavesWindowAlphaWhenNotSpecified() throws {
        let window = makeWindow()
        let contentView = try #require(window.contentView)
        window.alphaValue = 0.8

        let applier = WindowStyleApplierView()
        applier.appearanceName = AppTheme.dark.appearanceName
        applier.apply()
        #expect(window.appearance == nil)

        contentView.addSubview(applier)
        #expect(window.appearance?.name == .darkAqua)
        #expect(abs(window.alphaValue - 0.8) < alphaTolerance)
        #expect(applier.alphaValue == 1.0)

        applier.removeFromSuperview()
        applier.appearanceName = AppTheme.light.appearanceName
        applier.windowAlphaValue = 0.5
        applier.apply()
        #expect(window.appearance?.name == .darkAqua)
        #expect(abs(window.alphaValue - 0.8) < alphaTolerance)
    }
}
