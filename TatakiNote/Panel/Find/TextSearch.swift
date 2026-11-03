import Foundation

/// 検索のオプション。
struct FindOptions: Equatable {
    var isCaseSensitive = false
    var isWholeWord = false
    var isRegex = false
    var preservesCase = false

    /// 指定のオプションがオンか。
    func isOn(_ option: FindOption) -> Bool {
        switch option {
        case .caseSensitive: isCaseSensitive
        case .wholeWord: isWholeWord
        case .regex: isRegex
        case .preserveCase: preservesCase
        }
    }

    /// 指定のオプションのオンとオフを切り替える。
    mutating func toggle(_ option: FindOption) {
        switch option {
        case .caseSensitive: isCaseSensitive.toggle()
        case .wholeWord: isWholeWord.toggle()
        case .regex: isRegex.toggle()
        case .preserveCase: preservesCase.toggle()
        }
    }
}

/// 切り替えられる検索のオプション。
enum FindOption: CaseIterable, Equatable {
    case caseSensitive
    case wholeWord
    case regex
    case preserveCase
}

/// 1つの一致。groups[0] は一致の全体、1 以降はキャプチャ(一致しなかったグループは location が NSNotFound)。
struct TextMatch: Equatable {
    let range: NSRange
    let groups: [NSRange]
}

/// 検索の結果。
enum TextSearchResult: Equatable {
    case noQuery
    case invalidPattern
    case found([TextMatch], isTruncated: Bool)
}

/// 文章の中の検索語の一致を求める計算。範囲はすべて UTF-16 の NSRange。
enum TextSearch {
    static let matchLimit = 19_999

    private static let wordSeparators: Set<unichar> = Set(
        "`~!@#$%^&*()-=+[{]}\\|;:'\",.<>/? \t".utf16
    )
    private static let carriageReturn: unichar = 0x0D
    private static let lineFeed: unichar = 0x0A

    /// 文章の中の一致を位置の順に返す。limit が nil なら打ち切らない。
    static func search(
        _ query: String,
        options: FindOptions,
        in text: String,
        limit: Int? = matchLimit
    ) -> TextSearchResult {
        guard !query.isEmpty else { return .noQuery }

        let pattern = options.isRegex ? query : NSRegularExpression.escapedPattern(for: query)
        var regexOptions: NSRegularExpression.Options = [.anchorsMatchLines]
        if !options.isCaseSensitive {
            regexOptions.insert(.caseInsensitive)
        }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: regexOptions)
        } catch {
            return .invalidPattern
        }

        let nsText = text as NSString
        var matches: [TextMatch] = []
        var isTruncated = false
        regex.enumerateMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        ) { result, _, stop in
            guard let result else { return }
            if options.isWholeWord, !isWholeWordMatch(result.range, in: nsText) {
                return
            }
            if let limit, matches.count >= limit {
                isTruncated = true
                stop.pointee = true
                return
            }
            let groups = (0..<result.numberOfRanges).map { result.range(at: $0) }
            matches.append(TextMatch(range: result.range, groups: groups))
        }
        return .found(matches, isTruncated: isTruncated)
    }

    /// 一致の前後が単語の区切りか。
    static func isWholeWordMatch(_ range: NSRange, in text: NSString) -> Bool {
        isLeftBoundary(range, in: text) && isRightBoundary(range, in: text)
    }

    private static func isLeftBoundary(_ range: NSRange, in text: NSString) -> Bool {
        if range.location == 0 { return true }
        let before = text.character(at: range.location - 1)
        if wordSeparators.contains(before) || before == carriageReturn || before == lineFeed {
            return true
        }
        if range.length > 0, wordSeparators.contains(text.character(at: range.location)) {
            return true
        }
        return false
    }

    private static func isRightBoundary(_ range: NSRange, in text: NSString) -> Bool {
        let end = NSMaxRange(range)
        if end == text.length { return true }
        let after = text.character(at: end)
        if wordSeparators.contains(after) || after == carriageReturn || after == lineFeed {
            return true
        }
        if range.length > 0, wordSeparators.contains(text.character(at: end - 1)) {
            return true
        }
        return false
    }
}
