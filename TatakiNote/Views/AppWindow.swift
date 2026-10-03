import AppKit
import SwiftUI

/// 設定・許可の案内・チュートリアルの窓を作って前面に出す共通の処理。
enum AppWindow {
    /// 閉じても破棄しない窓を作り、SwiftUI の中身を載せる。
    static func make<Content: View>(
        title: String,
        identifier: String,
        styleMask: NSWindow.StyleMask,
        delegate: NSWindowDelegate,
        rootView: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.delegate = delegate
        window.contentView = NSHostingView(rootView: rootView)
        return window
    }

    /// `existing` があればそれを返す。無ければ `make` で作り、`initialContentSize` の大きさにして画面の中央に置いて返す。
    static func prepare(
        existing: NSWindow?,
        make: () -> NSWindow,
        initialContentSize: (NSWindow) -> NSSize?
    ) -> NSWindow {
        if let existing {
            return existing
        }
        let window = make()
        if let size = initialContentSize(window) {
            window.setContentSize(size)
        }
        window.center()
        return window
    }

    /// アプリを前面にして、窓を前に出す。
    static func bringToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

/// 窓の中身に、設定のテーマを当てる。
struct ThemedWindowContent<Content: View>: View {
    let settings: AppSettings
    @ViewBuilder let content: () -> Content

    var body: some View {
        content().windowStyle(theme: settings.theme)
    }
}
