import AppKit

/// 書き出しに失敗したことの知らせ。
enum ExportFailureAlert {
    /// 理由の文を添えた警告を出す。窓があればその窓のシート、無ければ単独で出し、閉じたら completion を呼ぶ。
    static func show(message: String, attachedTo window: NSWindow?, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "書き出せませんでした")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        if let window {
            alert.beginSheetModal(for: window) { _ in completion() }
        } else {
            NSApp.activate()
            alert.runModal()
            completion()
        }
    }
}
