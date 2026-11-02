import Foundation

/// 一致の行き来と、検索バーに出す件数の文字の計算。
enum FindNavigation {
    /// 正規表現が正しくないときの知らせ。
    static let invalidPatternMessage = String(localized: "正規表現が正しくありません")

    /// 選択の後ろの一致。選択が一致と同じならその次。末尾を越えたら先頭へ。一致が無ければ nil。
    static func nextIndex(in matches: [NSRange], after selection: NSRange) -> Int? {
        guard !matches.isEmpty else { return nil }
        if let current = currentIndex(in: matches, selection: selection) {
            return (current + 1) % matches.count
        }
        return matches.firstIndex { $0.location >= NSMaxRange(selection) } ?? 0
    }

    /// 選択の前の一致。選択が一致と同じならその前。先頭を越えたら末尾へ。一致が無ければ nil。
    static func previousIndex(in matches: [NSRange], before selection: NSRange) -> Int? {
        guard !matches.isEmpty else { return nil }
        if let current = currentIndex(in: matches, selection: selection) {
            return (current + matches.count - 1) % matches.count
        }
        return matches.lastIndex { $0.location < selection.location } ?? matches.count - 1
    }

    /// location 以降で最初の一致。無ければ先頭の一致。
    static func nearestIndex(in matches: [NSRange], from location: Int) -> Int? {
        guard !matches.isEmpty else { return nil }
        return matches.firstIndex { $0.location >= location } ?? 0
    }

    /// 選択とちょうど同じ範囲の一致。
    static func currentIndex(in matches: [NSRange], selection: NSRange) -> Int? {
        matches.firstIndex { $0 == selection }
    }

    /// 選択中の文字を検索語の種にする。空・改行を含むなら nil。正規表現オンならエスケープする。
    static func seed(selection: NSRange, in text: NSString, isRegex: Bool) -> String? {
        guard selection.location != NSNotFound,
              selection.length > 0,
              NSMaxRange(selection) <= text.length
        else { return nil }
        let selected = text.substring(with: selection)
        guard selected.rangeOfCharacter(from: .newlines) == nil else { return nil }
        return isRegex ? NSRegularExpression.escapedPattern(for: selected) : selected
    }

    /// 件数の表示。
    static func countText(for result: TextSearchResult, currentIndex: Int?) -> String {
        switch result {
        case .noQuery:
            return ""
        case .invalidPattern:
            return noResultText
        case let .found(matches, isTruncated):
            guard !matches.isEmpty else { return noResultText }
            let total = isTruncated ? "\(matches.count)+" : "\(matches.count)"
            guard let currentIndex else { return "?/\(total)" }
            return "\(currentIndex + 1)/\(total)"
        }
    }

    private static var noResultText: String {
        String(localized: "結果なし")
    }
}
