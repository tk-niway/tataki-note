import Foundation

/// 畳んだ URL で隠す範囲(URL の中の位置、UTF-16)。
struct EditorURLFold: Equatable {
    /// 先頭の `https://` など、何も描かずに隠す範囲。
    let schemeRange: NSRange
    /// 間の隠す範囲。最後の文字の位置に「…」を描く。無ければ nil。
    let middleRange: NSRange?

    /// 畳む URL の長さの境目。これを超える URL を畳む。
    static let foldThreshold = 30
    /// 末尾に残す部分の長さの上限。
    static let tailMaxLength = 16
    /// 「…」の文字。
    static let ellipsis = "…"

    /// 畳む URL なら、その隠す範囲。境目以下なら nil。
    static func make(for url: String) -> EditorURLFold? {
        let text = url as NSString
        guard text.length > foldThreshold else { return nil }
        let separator = text.range(of: "://")
        guard separator.location != NSNotFound else { return nil }
        let schemeEnd = NSMaxRange(separator)
        let schemeRange = NSRange(location: 0, length: schemeEnd)

        let delimiters = CharacterSet(charactersIn: "/?#")
        let hostSearch = NSRange(location: schemeEnd, length: text.length - schemeEnd)
        let hostEnd = text.rangeOfCharacter(from: delimiters, options: [], range: hostSearch).location
        guard hostEnd != NSNotFound else {
            return EditorURLFold(schemeRange: schemeRange, middleRange: nil)
        }

        if text.character(at: hostEnd) != 0x2F {
            let middle = NSRange(location: hostEnd, length: text.length - hostEnd)
            return EditorURLFold(schemeRange: schemeRange, middleRange: middle)
        }

        let pathStart = hostEnd + 1
        let path = text.substring(from: pathStart)
        let middleEnd: Int
        switch tailOffset(in: path) {
        case .none:
            middleEnd = text.length
        case .some(0):
            return EditorURLFold(schemeRange: schemeRange, middleRange: nil)
        case .some(let offset):
            middleEnd = pathStart + offset - 1
        }
        let middle = NSRange(location: pathStart, length: middleEnd - pathStart)
        return EditorURLFold(
            schemeRange: schemeRange,
            middleRange: middle.length > 0 ? middle : nil
        )
    }

    /// 畳んだときの見え方の文字列。
    func displayText(of url: String) -> String {
        let text = url as NSString
        let schemeEnd = min(NSMaxRange(schemeRange), text.length)
        guard let middleRange else {
            return text.substring(from: schemeEnd)
        }
        let head = text.substring(with: NSRange(location: schemeEnd, length: max(0, middleRange.location - schemeEnd)))
        let tail = text.substring(from: min(NSMaxRange(middleRange), text.length))
        return head + Self.ellipsis + tail
    }

    // MARK: - 末尾の区切り

    private static func tailOffset(in path: String) -> Int? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        var taken = 0
        var length = 0
        for component in components.reversed() {
            let joined = taken == 0 ? component.utf16.count : length + 1 + component.utf16.count
            if joined > tailMaxLength { break }
            length = joined
            taken += 1
        }
        if taken == 0 { return nil }
        if taken == components.count { return 0 }
        return (path as NSString).length - length
    }
}
