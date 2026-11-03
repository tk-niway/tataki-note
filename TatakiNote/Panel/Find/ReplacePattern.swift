import Foundation

/// 置換語から、一致を置き換える文字列を組み立てる計算。
enum ReplacePattern {
    private enum CaseOperation {
        case upperFirst
        case lowerFirst
        case upperAll
        case lowerAll
    }

    /// 一致を置き換える文字列。正規表現オンなら置換語を解釈し、大文字と小文字の保持がオンなら合わせる。
    static func replacement(
        for match: TextMatch,
        in text: NSString,
        template: String,
        options: FindOptions
    ) -> String {
        let expanded = options.isRegex ? expand(template, for: match, in: text) : template
        guard options.preservesCase else { return expanded }
        return preservingCase(of: text.substring(with: match.range), in: expanded)
    }

    /// 一致した文字列の大文字・小文字の形を置換語に移す。
    static func preservingCase(of matched: String, in replacement: String) -> String {
        guard !matched.isEmpty, !replacement.isEmpty else { return replacement }

        let hasHyphens = hasMatchingSeparator("-", matched: matched, replacement: replacement)
        let hasUnderscores = hasMatchingSeparator("_", matched: matched, replacement: replacement)
        if hasHyphens, !hasUnderscores {
            return preservingCase(separatedBy: "-", matched: matched, replacement: replacement)
        }
        if !hasHyphens, hasUnderscores {
            return preservingCase(separatedBy: "_", matched: matched, replacement: replacement)
        }

        if matched.uppercased() == matched {
            return replacement.uppercased()
        }
        if matched.lowercased() == matched {
            return replacement.lowercased()
        }
        guard let first = matched.first else { return replacement }
        let firstText = String(first)
        if firstText.lowercased() != firstText {
            return uppercasingFirst(of: replacement)
        }
        if firstText.uppercased() != firstText {
            return lowercasingFirst(of: replacement)
        }
        return replacement
    }

    private static func hasMatchingSeparator(
        _ separator: String,
        matched: String,
        replacement: String
    ) -> Bool {
        matched.contains(separator)
            && replacement.contains(separator)
            && matched.components(separatedBy: separator).count
                == replacement.components(separatedBy: separator).count
    }

    private static func preservingCase(
        separatedBy separator: String,
        matched: String,
        replacement: String
    ) -> String {
        let matchedParts = matched.components(separatedBy: separator)
        let replacementParts = replacement.components(separatedBy: separator)
        return zip(matchedParts, replacementParts)
            .map { preservingCase(of: $0, in: $1) }
            .joined(separator: separator)
    }

    private static func uppercasingFirst(of text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }

    private static func lowercasingFirst(of text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).lowercased() + text.dropFirst()
    }

    private static func expand(_ template: String, for match: TextMatch, in text: NSString) -> String {
        let scalars = Array(template.unicodeScalars)
        var result = String.UnicodeScalarView()
        var pendingOperations: [CaseOperation] = []
        var index = 0

        func appendGroup(_ groupIndex: Int) {
            let substituted = substitution(for: groupIndex, in: match, text: text)
            result.append(contentsOf: apply(pendingOperations, to: substituted).unicodeScalars)
            pendingOperations.removeAll()
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\\", index + 1 < scalars.count {
                let next = scalars[index + 1]
                switch next {
                case "\\": result.append("\\")
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "u": pendingOperations.append(.upperFirst)
                case "l": pendingOperations.append(.lowerFirst)
                case "U": pendingOperations.append(.upperAll)
                case "L": pendingOperations.append(.lowerAll)
                default:
                    result.append(scalar)
                    result.append(next)
                }
                index += 2
                continue
            }
            if scalar == "$", index + 1 < scalars.count {
                let next = scalars[index + 1]
                if next == "$" {
                    result.append("$")
                    index += 2
                    continue
                }
                if next == "0" || next == "&" {
                    appendGroup(0)
                    index += 2
                    continue
                }
                if let digit = digitValue(next), digit >= 1 {
                    if index + 2 < scalars.count, let second = digitValue(scalars[index + 2]) {
                        appendGroup(digit * 10 + second)
                        index += 3
                    } else {
                        appendGroup(digit)
                        index += 2
                    }
                    continue
                }
            }
            result.append(scalar)
            index += 1
        }
        return String(result)
    }

    private static func digitValue(_ scalar: Unicode.Scalar) -> Int? {
        guard scalar.value >= 0x30, scalar.value <= 0x39 else { return nil }
        return Int(scalar.value - 0x30)
    }

    private static func substitution(for groupIndex: Int, in match: TextMatch, text: NSString) -> String {
        func groupText(_ index: Int) -> String {
            guard index < match.groups.count else { return "" }
            let range = match.groups[index]
            guard range.location != NSNotFound else { return "" }
            return text.substring(with: range)
        }

        if groupIndex == 0 { return groupText(0) }
        var remainder = ""
        var number = groupIndex
        while number > 0 {
            if number < match.groups.count {
                return groupText(number) + remainder
            }
            remainder = String(number % 10) + remainder
            number /= 10
        }
        return "$" + remainder
    }

    private static func apply(_ operations: [CaseOperation], to text: String) -> String {
        guard !operations.isEmpty else { return text }
        var result = ""
        var operationIndex = 0
        for (offset, character) in text.enumerated() {
            guard operationIndex < operations.count else {
                result += String(text.dropFirst(offset))
                break
            }
            let piece = String(character)
            switch operations[operationIndex] {
            case .upperAll:
                result += piece.uppercased()
            case .lowerAll:
                result += piece.lowercased()
            case .upperFirst:
                result += piece.uppercased()
                operationIndex += 1
            case .lowerFirst:
                result += piece.lowercased()
                operationIndex += 1
            }
        }
        return result
    }
}
