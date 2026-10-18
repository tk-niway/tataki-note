import AppKit

/// `NSSharingServicePicker` でシェアのメニューを出す。
@MainActor
final class SharingServicePresenter: TextSharing {
    private weak var panel: NSPanel?
    private let anchorRegistry: SharingAnchorRegistry
    private var picker: NSSharingServicePicker?

    init(panel: NSPanel, anchorRegistry: SharingAnchorRegistry) {
        self.panel = panel
        self.anchorRegistry = anchorRegistry
    }

    func share(_ text: String, from anchor: SharingAnchor) {
        guard let contentView = panel?.contentView else { return }
        let picker = NSSharingServicePicker(items: [text])
        self.picker = picker
        if anchor == .titleBarButton,
           let view = anchorRegistry.view,
           view.window === panel {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            return
        }
        let location = contentView.convert(panel?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        picker.show(relativeTo: NSRect(origin: location, size: NSSize(width: 1, height: 1)), of: contentView, preferredEdge: .minY)
    }
}
