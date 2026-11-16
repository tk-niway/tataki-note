import AppKit

extension NSAttributedString.Key {
    /// 畳んだ URL の隠す文字に付ける印。
    static let editorURLHidden = NSAttributedString.Key("TatakiNoteEditorURLHidden")
    /// 畳んだ URL の「…」を描く文字に付ける印。
    static let editorURLEllipsis = NSAttributedString.Key("TatakiNoteEditorURLEllipsis")
}

/// 隠す1文字の字間。
struct EditorHiddenKern: Equatable {
    let location: Int
    let kern: CGFloat
    /// 「…」を描く文字なら true。
    let isEllipsis: Bool
}

/// 畳んだ URL の隠す文字に、幅を 0 にする字間と印を付け外しする。文字は変えない。
struct EditorURLFoldStyler {
    let font: NSFont
    /// 字間の設定の値。
    let baseKern: CGFloat
    var measure: (String) -> CGFloat

    /// URL の色。
    static let urlColor: NSColor = .linkColor

    init(font: NSFont, baseKern: CGFloat, measure: ((String) -> CGFloat)? = nil) {
        self.font = font
        self.baseKern = baseKern
        self.measure = measure ?? { NSAttributedString(string: $0, attributes: [.font: font]).size().width }
    }

    /// 見え方から、隠す文字ごとの字間を作る。
    func hiddenKerns(for presentations: [EditorURLPresentation], in text: NSString) -> [EditorHiddenKern] {
        var result: [EditorHiddenKern] = []
        var widths: [String: CGFloat] = [:]
        func width(of character: String) -> CGFloat {
            if let cached = widths[character] { return cached }
            let value = measure(character)
            widths[character] = value
            return value
        }
        for presentation in presentations {
            guard let fold = presentation.fold else { continue }
            var ranges = [fold.schemeRange]
            if let middle = fold.middleRange {
                ranges.append(middle)
            }
            let middleLast = fold.middleRange.map { NSMaxRange($0) - 1 }
            for range in ranges {
                let clamped = LineEditing.clamped(range, toLength: text.length)
                for location in clamped.location..<NSMaxRange(clamped) {
                    let character = text.substring(with: NSRange(location: location, length: 1))
                    var kern = -width(of: character)
                    let isEllipsis = location == middleLast
                    if isEllipsis {
                        kern += width(of: EditorURLFold.ellipsis) + baseKern
                    }
                    result.append(EditorHiddenKern(location: location, kern: kern, isEllipsis: isEllipsis))
                }
            }
        }
        return result
    }

    /// 前の印を外して字間を `baseKern` に戻し、新しい字間と印・`.ligature = 0` を付ける。変えたら true。
    @discardableResult
    func apply(_ kerns: [EditorHiddenKern], to storage: NSTextStorage) -> Bool {
        let length = storage.length
        var wanted: [Int: EditorHiddenKern] = [:]
        for item in kerns where item.location >= 0 && item.location < length {
            wanted[item.location] = item
        }

        var marked: [Int] = []
        storage.enumerateAttribute(.editorURLHidden, in: NSRange(location: 0, length: length), options: []) { value, range, _ in
            guard value != nil else { return }
            marked.append(contentsOf: range.location..<NSMaxRange(range))
        }

        var restores: [Int] = []
        for location in marked where wanted[location] == nil {
            restores.append(location)
        }
        var additions: [EditorHiddenKern] = []
        for (_, item) in wanted.sorted(by: { $0.key < $1.key }) where !isApplied(item, in: storage) {
            additions.append(item)
        }
        guard !restores.isEmpty || !additions.isEmpty else { return false }

        storage.beginEditing()
        for location in restores {
            let range = NSRange(location: location, length: 1)
            storage.removeAttribute(.editorURLHidden, range: range)
            storage.removeAttribute(.editorURLEllipsis, range: range)
            storage.removeAttribute(.ligature, range: range)
            if baseKern > 0 {
                storage.addAttribute(.kern, value: baseKern, range: range)
            } else {
                storage.removeAttribute(.kern, range: range)
            }
        }
        for item in additions {
            let range = NSRange(location: item.location, length: 1)
            storage.addAttributes(
                [.kern: item.kern, .ligature: 0, .editorURLHidden: true],
                range: range
            )
            if item.isEllipsis {
                storage.addAttribute(.editorURLEllipsis, value: true, range: range)
            } else {
                storage.removeAttribute(.editorURLEllipsis, range: range)
            }
        }
        storage.endEditing()
        return true
    }

    private func isApplied(_ item: EditorHiddenKern, in storage: NSTextStorage) -> Bool {
        let attributes = storage.attributes(at: item.location, effectiveRange: nil)
        return attributes[.editorURLHidden] != nil
            && (attributes[.editorURLEllipsis] != nil) == item.isEllipsis
            && (attributes[.kern] as? NSNumber)?.doubleValue == Double(item.kern)
            && (attributes[.ligature] as? NSNumber)?.intValue == 0
    }
}
