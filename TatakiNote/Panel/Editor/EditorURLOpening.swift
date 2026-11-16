import AppKit

/// URL を既定のブラウザで開く。
protocol EditorURLOpening: AnyObject {
    func open(_ url: URL)
}

/// `NSWorkspace` で開く。
final class WorkspaceEditorURLOpener: EditorURLOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
