import Foundation

/// 1回の付け直しで決めた範囲。
struct EditorURLFoldUpdate: Equatable {
    let redetectedRange: NSRange?
    let restyleRanges: [NSRange]
    let recolorRanges: [NSRange]
}

/// 選択の変化で URL の見え方を決め直すかの規則。
enum EditorURLRefreshRule {
    /// 選択が確定していて、付け直しの中でなく、文字の変更の途中でなく、前回の決め直しから文章か選択が変わっていれば true。
    static func refreshesOnSelectionChange(
        isStillSelecting: Bool,
        isApplyingURLFolds: Bool,
        isChangingText: Bool,
        hasPendingEdits: Bool,
        isSelectionChanged: Bool
    ) -> Bool {
        !isStillSelecting
            && !isApplyingURLFolds
            && !(isChangingText && hasPendingEdits)
            && (hasPendingEdits || isSelectionChanged)
    }
}

/// 1回の付け直しで、隠す字間と色を付け直す範囲を決める。
enum EditorURLRestyleScope {
    /// 前回の見え方を、変更の後の位置へ移す。変更に重なる・接する URL は除く。
    static func shifted(_ presentations: [EditorURLPresentation], through edits: [EditorTextEdit]) -> [EditorURLPresentation] {
        presentations.compactMap { presentation in
            var presentation = presentation
            for edit in edits {
                guard let moved = edit.shifted(presentation.url.range) else { return nil }
                let delta = moved.location - presentation.url.range.location
                guard delta != 0 else { continue }
                presentation = EditorURLPresentation(
                    url: EditorURL(range: moved, text: presentation.url.text),
                    fold: presentation.fold.map { fold in
                        EditorURLFold(
                            schemeRange: offset(fold.schemeRange, by: delta),
                            middleRange: fold.middleRange.map { offset($0, by: delta) }
                        )
                    }
                )
            }
            return presentation
        }
    }

    /// 隠す字間と印を付け直す範囲(前から順、重ならない、隣り合うものはつなぐ)。
    static func restyleRanges(
        previous: [EditorURLPresentation],
        current: [EditorURLPresentation],
        redetectedRange: NSRange?,
        isWhole: Bool,
        textLength: Int
    ) -> [NSRange] {
        if isWhole {
            return normalized([NSRange(location: 0, length: textLength)], textLength: textLength)
        }
        var ranges: [NSRange] = []
        if let redetectedRange {
            ranges.append(redetectedRange)
        }
        func isInsideRedetected(_ range: NSRange) -> Bool {
            guard let redetectedRange else { return false }
            return range.location >= redetectedRange.location && NSMaxRange(range) <= NSMaxRange(redetectedRange)
        }
        var previousByRange: [RangeKey: EditorURLPresentation] = [:]
        for presentation in previous {
            previousByRange[RangeKey(presentation.url.range)] = presentation
        }
        var currentKeys = Set<RangeKey>()
        for presentation in current {
            let key = RangeKey(presentation.url.range)
            currentKeys.insert(key)
            guard !isInsideRedetected(presentation.url.range) else { continue }
            if let before = previousByRange[key], before.fold == presentation.fold { continue }
            ranges.append(presentation.url.range)
        }
        for presentation in previous where !isInsideRedetected(presentation.url.range) {
            if !currentKeys.contains(RangeKey(presentation.url.range)) {
                ranges.append(presentation.url.range)
            }
        }
        return normalized(ranges, textLength: textLength)
    }

    /// URL の色を付け直す範囲。`restyleRanges` に、色が文字と一緒に動かず長さの変わった変更があれば、
    /// 探し直した範囲の始まりから文末までを足す。
    static func recolorRanges(
        restyleRanges: [NSRange],
        change: EditorURLIndexChange,
        textLength: Int,
        colorsFollowText: Bool
    ) -> [NSRange] {
        guard !colorsFollowText,
              let redetectedRange = change.redetectedRange,
              change.edits.contains(where: { $0.changeInLength != 0 })
        else { return restyleRanges }
        let tail = NSRange(location: redetectedRange.location, length: textLength - redetectedRange.location)
        return normalized(restyleRanges + [tail], textLength: textLength)
    }

    // MARK: - 部品

    private struct RangeKey: Hashable {
        let location: Int
        let length: Int

        init(_ range: NSRange) {
            location = range.location
            length = range.length
        }
    }

    private static func offset(_ range: NSRange, by delta: Int) -> NSRange {
        NSRange(location: range.location + delta, length: range.length)
    }

    private static func normalized(_ ranges: [NSRange], textLength: Int) -> [NSRange] {
        let clamped = ranges
            .map { LineEditing.clamped($0, toLength: textLength) }
            .filter { textLength > 0 || $0.length > 0 }
            .sorted { $0.location < $1.location }
        var result: [NSRange] = []
        for range in clamped {
            if let last = result.last, range.location <= NSMaxRange(last) {
                let end = max(NSMaxRange(last), NSMaxRange(range))
                result[result.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
