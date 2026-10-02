import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelControllerTests {
    private func makeController(settings: AppSettings) -> PanelController {
        PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: InserterStub(result: .inserted),
            permission: PermissionStub(isTrusted: true),
            notifier: NotifierStub(),
            fieldProbe: FocusedElementProbeStub()
        )
    }

    private func withSettings(_ body: (AppSettings) throws -> Void) throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(AppSettings(store: SettingsStore(defaults: defaults)))
    }

    @Test("AC-14: タイトルバーのダブルクリックなどでズームさせない")
    func windowShouldNotZoom() throws {
        try withSettings { settings in
            let controller = makeController(settings: settings)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
                styleMask: [.titled, .resizable],
                backing: .buffered,
                defer: true
            )

            #expect(controller.windowShouldZoom(window, toFrame: NSRect(x: 0, y: 0, width: 1440, height: 875)) == false)
        }
    }

    @Test("AC-1: ドラッグの途中の大きさは 320×160 より小さくならず、それ以上ならそのまま")
    func windowWillResizeKeepsMinimumSize() throws {
        try withSettings { settings in
            let controller = makeController(settings: settings)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
                styleMask: [.titled, .resizable],
                backing: .buffered,
                defer: true
            )

            #expect(controller.windowWillResize(window, to: NSSize(width: 27, height: 33)) == NSSize(width: 320, height: 160))
            #expect(controller.windowWillResize(window, to: NSSize(width: 27, height: 400)) == NSSize(width: 320, height: 400))
            #expect(controller.windowWillResize(window, to: NSSize(width: 600, height: 100)) == NSSize(width: 600, height: 160))
            #expect(controller.windowWillResize(window, to: NSSize(width: 600, height: 400)) == NSSize(width: 600, height: 400))
        }
    }

    @Test("AC-1, AC-14: パネルは端のドラッグで大きさを変えられ、非アクティブ化しないまま、最小は 320×160、信号のボタンは隠れている")
    func promptPanelIsResizableAndNonactivating() {
        let panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))

        #expect(panel.styleMask.contains(.resizable))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.contentMinSize == CGSize(width: 320, height: 160))
        #expect(panel.standardWindowButton(.zoomButton)?.isHidden ?? true)
    }

    @Test("AC-7, AC-18: 作った直後は保っている大きさが無い(設定の既定の大きさを変えた suite で作っても)")
    func heldPanelSizeIsNilAfterLaunch() throws {
        try withSettings { settings in
            #expect(makeController(settings: settings).heldPanelSize == nil)
        }
        try withSettings { settings in
            settings.panelDefaultWidth = 600
            settings.panelDefaultHeight = 400
            #expect(makeController(settings: settings).heldPanelSize == nil)
        }
    }

    @Test("AC-18: ドラッグの開始が無い終了・大きさの変わらないドラッグでは、保っている大きさを作らない")
    func liveResizeWithoutSizeChangeKeepsNothing() throws {
        try withSettings { settings in
            let controller = makeController(settings: settings)

            controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
            #expect(controller.heldPanelSize == nil)

            controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification))
            controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
            #expect(controller.heldPanelSize == nil)
        }
    }

}
