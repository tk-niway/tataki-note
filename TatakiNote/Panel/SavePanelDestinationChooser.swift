import AppKit
import UniformTypeIdentifiers

/// 名前の欄で ⌘ の編集のキーが効く保存ダイアログ。
final class ExportSavePanel: NSSavePanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let action = SavePanelEditKey.action(
                  modifiers: event.modifierFlags,
                  character: event.charactersIgnoringModifiers?.lowercased() ?? ""
              ),
              NSApp.sendAction(Self.selector(for: action), to: nil, from: self) else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    private static func selector(for action: SavePanelEditAction) -> Selector {
        switch action {
        case .cut: return #selector(NSText.cut(_:))
        case .copy: return #selector(NSText.copy(_:))
        case .paste: return #selector(NSText.paste(_:))
        case .selectAll: return #selector(NSText.selectAll(_:))
        case .undo: return Selector(("undo:"))
        case .redo: return Selector(("redo:"))
        }
    }
}

/// 本物の保存ダイアログを、パネルを止めずに(モーダルにせず)開く。
final class SavePanelDestinationChooser: ExportDestinationChoosing {
    private var openPanel: NSSavePanel?

    nonisolated init() {}

    func chooseDestination(initialName: String, directory: URL, completion: @escaping (URL?) -> Void) {
        let savePanel = ExportSavePanel()
        savePanel.nameFieldStringValue = initialName
        savePanel.directoryURL = directory
        savePanel.allowedContentTypes = [.plainText]
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        savePanel.canCreateDirectories = true
        savePanel.identifier = NSUserInterfaceItemIdentifier("export.savePanel")
        savePanel.setAccessibilityIdentifier("export.savePanel")
        savePanel.level = .modalPanel
        openPanel = savePanel
        NSApp.activate()
        savePanel.begin { [weak self] response in
            self?.openPanel = nil
            completion(response == .OK ? savePanel.url : nil)
        }
    }

    func bringToFront() {
        guard let openPanel else { return }
        NSApp.activate()
        openPanel.makeKeyAndOrderFront(nil)
    }
}
