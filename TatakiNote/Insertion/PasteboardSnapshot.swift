import AppKit

/// @note p0-116
struct PasteboardSnapshot: Equatable {
    struct Entry: Equatable {
        var type: NSPasteboard.PasteboardType
        var data: Data
    }

    var items: [[Entry]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).compactMap { item -> [Entry]? in
            // @note p0-117
            let entries = item.types.compactMap { type in
                item.data(forType: type).map { Entry(type: type, data: $0) }
            }
            // @note p0-118
            return entries.isEmpty ? nil : entries
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let pasteboardItems = items.map { entries in
            let item = NSPasteboardItem()
            for entry in entries {
                item.setData(entry.data, forType: entry.type)
            }
            return item
        }
        pasteboard.writeObjects(pasteboardItems)
    }
}
