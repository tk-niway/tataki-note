import Foundation

/// 文章の1回の変更。
nonisolated struct EditorTextEdit: Equatable {
    /// 変更の後の文章での、入れ替わった範囲。
    let range: NSRange
    /// 長さの差。
    let changeInLength: Int

    /// 変更の前の文章での範囲。
    var originalRange: NSRange {
        NSRange(location: range.location, length: max(0, range.length - changeInLength))
    }

    /// 変更の前の文章の範囲を、変更の後の位置へ移す。変更の範囲に重なる・接するときは nil。
    func shifted(_ target: NSRange) -> NSRange? {
        let original = originalRange
        if NSMaxRange(target) < original.location { return target }
        if target.location > NSMaxRange(original) {
            return NSRange(location: target.location + changeInLength, length: target.length)
        }
        return nil
    }
}

/// `EditorURLIndex.update(in:)` の結果。
nonisolated struct EditorURLIndexChange: Equatable {
    /// 探し直した範囲(段落の境目にそろえた、今の文章の位置)。探し直していなければ nil。
    let redetectedRange: NSRange?
    /// 反映した変更(古い順)。
    let edits: [EditorTextEdit]
    /// 全文を探し直したか。
    let isWhole: Bool
}

/// 文章の URL の一覧を、変わった段落だけ探し直して保つ。
struct EditorURLIndex {
    /// 前から順の、重ならない URL。
    private(set) var urls: [EditorURL] = []

    private var knownLength: Int?
    private var pendingEdits: [EditorTextEdit] = []

    /// 記録してまだ反映していない変更があるか。
    var hasPendingEdits: Bool { !pendingEdits.isEmpty }

    /// 文章の変更を記録する。探し直しは `update(in:)` まで遅らせる。
    mutating func record(_ edit: EditorTextEdit) {
        pendingEdits.append(edit)
    }

    /// 次の `update(in:)` で全文を探し直させる。
    mutating func invalidate() {
        knownLength = nil
        pendingEdits = []
    }

    /// 記録した変更を反映し、探し直した範囲と反映した変更を返す。
    mutating func update(in text: NSString) -> EditorURLIndexChange {
        let length = text.length
        guard let knownLength else { return redetectWhole(in: text) }
        if pendingEdits.isEmpty {
            guard length == knownLength else { return redetectWhole(in: text) }
            return EditorURLIndexChange(redetectedRange: nil, edits: [], isWhole: false)
        }
        let expectedLength = pendingEdits.reduce(knownLength) { $0 + $1.changeInLength }
        guard expectedLength == length else { return redetectWhole(in: text) }

        var dirty: NSRange?
        for edit in pendingEdits {
            urls = urls.compactMap { url in
                edit.shifted(url.range).map { EditorURL(range: $0, text: url.text) }
            }
            dirty = Self.widened(dirty, by: edit)
        }
        let edits = pendingEdits
        pendingEdits = []
        self.knownLength = length

        guard let dirty else { return EditorURLIndexChange(redetectedRange: nil, edits: edits, isWhole: false) }
        let expanded = Self.expanded(dirty, toLength: length)
        let region = text.paragraphRange(for: expanded)
        let detected = EditorURLDetector.urls(in: text, range: region)
        urls.removeAll { NSLocationInRange($0.range.location, region) }
        let insertionIndex = urls.firstIndex { $0.range.location >= NSMaxRange(region) } ?? urls.count
        urls.insert(contentsOf: detected, at: insertionIndex)
        return EditorURLIndexChange(redetectedRange: region, edits: edits, isWhole: false)
    }

    // MARK: - 全文

    private mutating func redetectWhole(in text: NSString) -> EditorURLIndexChange {
        let edits = pendingEdits
        pendingEdits = []
        knownLength = text.length
        urls = EditorURLDetector.urls(in: text)
        return EditorURLIndexChange(
            redetectedRange: NSRange(location: 0, length: text.length),
            edits: edits,
            isWhole: true
        )
    }

    // MARK: - 変わった範囲

    private static func widened(_ dirty: NSRange?, by edit: EditorTextEdit) -> NSRange {
        guard let dirty else { return edit.range }
        if let moved = edit.shifted(dirty) {
            return union(moved, edit.range)
        }
        let original = edit.originalRange
        let dirtyEnd = NSMaxRange(dirty) > NSMaxRange(original)
            ? NSMaxRange(dirty) + edit.changeInLength
            : NSMaxRange(dirty)
        let start = min(dirty.location, edit.range.location)
        let end = max(dirtyEnd, NSMaxRange(edit.range))
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func union(_ first: NSRange, _ second: NSRange) -> NSRange {
        let start = min(first.location, second.location)
        let end = max(NSMaxRange(first), NSMaxRange(second))
        return NSRange(location: start, length: end - start)
    }

    private static func expanded(_ range: NSRange, toLength length: Int) -> NSRange {
        let start = max(0, min(range.location, length) - 1)
        let end = min(length, NSMaxRange(range) + 1)
        return NSRange(location: start, length: max(0, end - start))
    }
}
