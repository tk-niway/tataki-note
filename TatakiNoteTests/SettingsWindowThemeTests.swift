import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
struct SettingsWindowThemeTests {
    private func waitUntil(_ window: NSWindow, _ condition: () -> Bool) async throws {
        var attempts = 0
        while attempts < 40 {
            window.contentView?.layoutSubtreeIfNeeded()
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
            attempts += 1
        }
    }

    private func settingsView(settings: AppSettings) -> SettingsView {
        SettingsView(
            settings: settings,
            model: SettingsWindowModel(),
            launchAtLogin: LaunchAtLoginModel(service: InMemoryLoginItemService()),
            appInfo: AppInfoModel(
                infoDictionary: [:],
                permissionStatus: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: true))
            ),
            panelDefaultSize: PanelDefaultSizeModel(settings: settings, currentPanelSize: { nil }),
            onShowFontPanel: {},
            onQuit: {}
        )
    }

    @Test("AC-6: テーマを変えると、開き直さずに設定画面の窓の外観がそのテーマになり、「システム」なら窓の外観の指定が外れる")
    func settingsWindowFollowsTheme() async throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.theme = .dark

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        #expect(window.appearance == nil)
        window.contentView = NSHostingView(rootView: settingsView(settings: settings))

        try await waitUntil(window) { window.appearance?.name == .darkAqua }
        #expect(window.appearance?.name == .darkAqua)

        settings.theme = .light
        try await waitUntil(window) { window.appearance?.name == .aqua }
        #expect(window.appearance?.name == .aqua)

        settings.theme = .system
        try await waitUntil(window) { window.appearance == nil }
        #expect(window.appearance == nil)

        settings.theme = .dark
        try await waitUntil(window) { window.appearance?.name == .darkAqua }
        #expect(window.appearance?.name == .darkAqua)
    }

    @Test("AC-6: テーマを変えると、開き直さずに権限の案内の窓の外観がそのテーマになり、「システム」なら窓の外観の指定が外れる")
    func permissionGuideWindowFollowsTheme() async throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.theme = .light

        let controller = PermissionGuideWindowController(
            model: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: false)),
            settings: settings
        )
        let window = controller.makeWindow()
        #expect(window.isVisible == false)

        try await waitUntil(window) { window.appearance?.name == .aqua }
        #expect(window.appearance?.name == .aqua)

        settings.theme = .dark
        try await waitUntil(window) { window.appearance?.name == .darkAqua }
        #expect(window.appearance?.name == .darkAqua)

        settings.theme = .system
        try await waitUntil(window) { window.appearance == nil }
        #expect(window.appearance == nil)
        #expect(controller.model.isPresented == false)
    }
}
