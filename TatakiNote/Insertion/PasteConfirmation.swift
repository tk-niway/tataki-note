import Foundation

/// ⌘V の前に読んだ入力欄の中身と確定した文章から、貼り付けの後に文章が入ったかを決める。
struct PasteConfirmation: Equatable {
    let normalizedText: String
    let occurrencesBefore: Int

    /// 確かめられるときだけ作る。中身が読めない・文章が空白と改行だけなら nil。
    init?(text: String, valueBefore: String?) {
        guard let valueBefore else { return nil }
        let normalizedText = Self.normalized(text)
        guard !normalizedText.isEmpty else { return nil }
        self.normalizedText = normalizedText
        self.occurrencesBefore = Self.occurrences(of: normalizedText, in: Self.normalized(valueBefore))
    }

    /// 貼り付けの後の中身で、文章が入ったと言えるか。
    func isConfirmed(by valueAfter: String?) -> Bool {
        guard let valueAfter else { return false }
        return Self.occurrences(of: normalizedText, in: Self.normalized(valueAfter)) > occurrencesBefore
    }

    /// 比べるための形。空白・改行(`CharacterSet.whitespacesAndNewlines`)と U+FFFC・U+200B を取り除き、NFC にそろえる。
    static func normalized(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars where !ignoredScalars.contains(scalar) {
            scalars.append(scalar)
        }
        return String(scalars).precomposedStringWithCanonicalMapping
    }

    /// `value` の中に `part` が重ならずに出てくる回数。`part` が空なら 0。
    static func occurrences(of part: String, in value: String) -> Int {
        let needle = Array(part.unicodeScalars)
        let haystack = Array(value.unicodeScalars)
        guard !needle.isEmpty, haystack.count >= needle.count else { return 0 }
        var count = 0
        var index = 0
        while index <= haystack.count - needle.count {
            if haystack[index..<(index + needle.count)].elementsEqual(needle) {
                count += 1
                index += needle.count
            } else {
                index += 1
            }
        }
        return count
    }

    private static let ignoredScalars: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\u{FFFC}\u{200B}")
        return set
    }()
}
