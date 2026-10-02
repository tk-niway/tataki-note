import AppKit

/// パネルの入力欄の文字(フォント・文字サイズ)と、パネルの透明度の決まり。
enum PanelTextStyle {
    static let defaultFontSize: Double = 14
    static let fontSizeRange: ClosedRange<Double> = 10...32

    static let defaultOpacity: Double = 1.0
    static let opacityRange: ClosedRange<Double> = 0.4...1.0

    static func clampedFontSize(_ size: Double) -> Double {
        guard size.isFinite else { return defaultFontSize }
        return min(max(size, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    static func clampedOpacity(_ opacity: Double) -> Double {
        guard opacity.isFinite else { return defaultOpacity }
        return min(max(opacity, opacityRange.lowerBound), opacityRange.upperBound)
    }

    private static let regularWeight = 5

    /// 名前が無い・空・先頭が「.」のとき、システムフォントの名前として扱う。
    static func isSystemFontName(_ name: String?) -> Bool {
        guard let name else { return true }
        return name.isEmpty || name.hasPrefix(".")
    }

    /// 入力欄に使うフォントを返す。システムフォントのとき、または使える書体が無いときは `nil`。
    static func resolvedFont(
        name: String?,
        familyName: String?,
        size: Double,
        members: (String) -> [[Any]]? = { NSFontManager.shared.availableMembers(ofFontFamily: $0) }
    ) -> NSFont? {
        guard let name, !isSystemFontName(name) else { return nil }
        let pointSize = CGFloat(clampedFontSize(size))
        if let font = NSFont(name: name, size: pointSize) {
            return font
        }
        guard let familyName, !isSystemFontName(familyName),
              let regularName = regularPostScriptName(members: members(familyName) ?? [])
        else { return nil }
        return NSFont(name: regularName, size: pointSize)
    }

    /// 入力欄に使うフォントを返す。書体が使えないときはシステムフォント。
    static func font(name: String?, familyName: String? = nil, size: Double) -> NSFont {
        resolvedFont(name: name, familyName: familyName, size: size)
            ?? .systemFont(ofSize: CGFloat(clampedFontSize(size)))
    }

    /// ファミリーの書体の一覧から、斜体でなく太さ 5 に最も近いものの PostScript 名を返す。
    static func regularPostScriptName(members: [[Any]]) -> String? {
        let candidates = members.compactMap { member -> FontMember? in
            guard let name = member.first as? String, !isSystemFontName(name) else { return nil }
            let weight = (member.count > 2 ? member[2] as? NSNumber : nil)?.intValue ?? regularWeight
            let traits = (member.count > 3 ? member[3] as? NSNumber : nil)?.uintValue ?? 0
            let isItalic = NSFontTraitMask(rawValue: traits).contains(.italicFontMask)
            return FontMember(postScriptName: name, weight: weight, isItalic: isItalic)
        }
        let upright = candidates.filter { !$0.isItalic }
        let best = upright.min { lhs, rhs in
            let lhsDistance = abs(lhs.weight - regularWeight)
            let rhsDistance = abs(rhs.weight - regularWeight)
            return lhsDistance != rhsDistance ? lhsDistance < rhsDistance : lhs.weight < rhs.weight
        }
        return (best ?? candidates.first)?.postScriptName
    }

    private struct FontMember {
        let postScriptName: String
        let weight: Int
        let isItalic: Bool
    }
}
