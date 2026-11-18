import Foundation

/// 1つの URL の今の見え方。
struct EditorURLPresentation: Equatable {
    let url: EditorURL
    /// 畳んでいるときの隠す範囲(文章の中の位置)。開いている・短いときは nil。
    let fold: EditorURLFold?

    /// URL を開いて(全文で)見せるか。
    static func isRevealed(_ url: NSRange, selection: NSRange, findRanges: [NSRange]) -> Bool {
        if selection.location != NSNotFound {
            let urlEnd = NSMaxRange(url)
            let selectionEnd = NSMaxRange(selection)
            for position in [selection.location, selectionEnd]
            where position >= url.location && position <= urlEnd {
                return true
            }
        }
        return findRanges.contains { NSIntersectionRange(url, $0).length > 0 }
    }

    /// 文章・選択・検索の一致から、URL ごとの見え方を作る。
    static func make(urls: [EditorURL], selection: NSRange, findRanges: [NSRange]) -> [EditorURLPresentation] {
        urls.map { url in
            guard !isRevealed(url.range, selection: selection, findRanges: findRanges),
                  let fold = EditorURLFold.make(for: url.text) else {
                return EditorURLPresentation(url: url, fold: nil)
            }
            let origin = url.range.location
            let shifted = EditorURLFold(
                schemeRange: NSRange(location: fold.schemeRange.location + origin, length: fold.schemeRange.length),
                middleRange: fold.middleRange.map {
                    NSRange(location: $0.location + origin, length: $0.length)
                }
            )
            return EditorURLPresentation(url: url, fold: shifted)
        }
    }
}
