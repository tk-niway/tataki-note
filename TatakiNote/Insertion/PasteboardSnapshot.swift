import AppKit

/// 写し取りと書き戻しに使う、クリップボードの読み書き。
nonisolated protocol PasteboardAccessing: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    @discardableResult func clearContents() -> Int
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: nonisolated PasteboardAccessing {}

/// クリップボードの内容を、全ての項目と全てのデータ型ごと写し取ったもの。
nonisolated struct PasteboardSnapshot: Equatable, Sendable {
    nonisolated struct Entry: Equatable, Sendable {
        var type: NSPasteboard.PasteboardType
        var data: Data
    }

    var items: [[Entry]]

    static func capture(from pasteboard: some PasteboardAccessing) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).compactMap { item -> [Entry]? in
            let entries = item.types.compactMap { type in
                item.data(forType: type).map { Entry(type: type, data: $0) }
            }
            return entries.isEmpty ? nil : entries
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: some PasteboardAccessing) {
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

/// 写し取った内容と、写し取ったときのクリップボードの変更回数。
nonisolated struct CapturedPasteboard: Equatable, Sendable {
    var snapshot: PasteboardSnapshot
    var changeCount: Int
}

/// クリップボードの写し取りと書き戻し。
protocol PasteboardSnapshotting {
    func capture() async -> CapturedPasteboard
    /// クリップボードの変更回数が `changeCount` のままなら書き戻し、書き戻したかを返す。
    func restore(_ snapshot: PasteboardSnapshot, ifChangeCountIs changeCount: Int) async -> Bool
}

/// クリップボードの写し取りと書き戻しを、メインスレッドの外で行う。
struct BackgroundPasteboardSnapshotter: PasteboardSnapshotting {
    private let box: PasteboardBox

    init(pasteboard: any PasteboardAccessing) {
        box = PasteboardBox(pasteboard: pasteboard)
    }

    func capture() async -> CapturedPasteboard {
        let box = box
        return await Task.detached(priority: .userInitiated) {
            let changeCount = box.pasteboard.changeCount
            let snapshot = PasteboardSnapshot.capture(from: box.pasteboard)
            return CapturedPasteboard(snapshot: snapshot, changeCount: changeCount)
        }.value
    }

    func restore(_ snapshot: PasteboardSnapshot, ifChangeCountIs changeCount: Int) async -> Bool {
        let box = box
        return await Task.detached(priority: .userInitiated) {
            guard box.pasteboard.changeCount == changeCount else { return false }
            snapshot.restore(to: box.pasteboard)
            return true
        }.value
    }
}

private nonisolated final class PasteboardBox: @unchecked Sendable {
    let pasteboard: any PasteboardAccessing

    init(pasteboard: any PasteboardAccessing) {
        self.pasteboard = pasteboard
    }
}
