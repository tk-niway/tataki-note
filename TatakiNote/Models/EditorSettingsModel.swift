import AppKit
import Observation

/// @note p0-239
struct FontChoice: Identifiable, Equatable {
    /// @note p0-240
    static let systemID = "system"

    /// @note p0-241
    static var system: FontChoice {
        FontChoice(id: systemID, familyName: nil, postScriptName: nil, displayName: String(localized: "システムフォント"))
    }

    let id: String
    /// @note p0-242
    let familyName: String?
    /// @note p0-243
    let postScriptName: String?
    /// @note p0-244
    let displayName: String
}

/// @note p0-245
enum FontChoices {
    /// @note p0-246
    private static let regularWeight = 5

    /// @note p0-247
    static func make(
        families: [String],
        members: (String) -> [[Any]]?,
        localizedName: (String) -> String
    ) -> [FontChoice] {
        let familyChoices = families.compactMap { family -> FontChoice? in
            guard !family.hasPrefix("."),
                  let postScriptName = representativePostScriptName(of: members(family) ?? [])
            else { return nil }
            return FontChoice(
                id: "family:\(family)",
                familyName: family,
                postScriptName: postScriptName,
                displayName: localizedName(family)
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return [.system] + familyChoices
    }

    /// @note p0-248
    static func systemChoices() -> [FontChoice] {
        let manager = NSFontManager.shared
        return make(
            families: manager.availableFontFamilies,
            members: { manager.availableMembers(ofFontFamily: $0) },
            localizedName: { family in
                let name = manager.localizedName(forFamily: family, face: nil)
                return name.isEmpty ? family : name
            }
        )
    }

    /// @note p0-249
    private static func representativePostScriptName(of members: [[Any]]) -> String? {
        let candidates = members.compactMap { member -> FontMember? in
            guard let name = member.first as? String, !name.isEmpty, !name.hasPrefix(".") else { return nil }
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

/// @note p0-250
enum StatusItemNote: Equatable {
    /// @note p0-251
    case keyNotAssigned
}

/// @note p0-252
@Observable final class EditorSettingsModel {
    /// @note p0-253
    let fontChoices: [FontChoice]

    @ObservationIgnored private let settings: AppSettings

    /// @note p0-254
    init(settings: AppSettings, fontChoices: [FontChoice] = FontChoices.systemChoices()) {
        self.settings = settings
        self.fontChoices = fontChoices
    }

    /// @note p0-255
    var systemFontChoice: FontChoice {
        fontChoices.first ?? .system
    }

    /// @note p0-256
    var familyFontChoices: ArraySlice<FontChoice> {
        fontChoices.dropFirst()
    }

    /// @note p0-257
    var selectedFontChoiceID: String {
        get {
            let name = settings.panelFontName
            guard let name, !Self.isSystemFontName(name) else { return FontChoice.systemID }
            guard let familyName = NSFont(name: name, size: CGFloat(PanelTextStyle.defaultFontSize))?.familyName,
                  let choice = fontChoices.first(where: { $0.familyName == familyName })
            else { return FontChoice.systemID }
            return choice.id
        }
        set {
            guard newValue != selectedFontChoiceID,
                  let choice = fontChoices.first(where: { $0.id == newValue })
            else { return }
            settings.panelFontName = choice.postScriptName
        }
    }

    /// @note p0-258
    var fontSizeText: String {
        let points = Int(settings.panelFontSize.rounded())
        return String(localized: "\(points) pt")
    }

    /// @note p0-259
    var opacityPercentText: String {
        let percent = Int((settings.panelOpacity * 100).rounded())
        return String(localized: "\(percent)%")
    }

    func isStatusItemVisible(_ item: PanelStatusItem) -> Bool {
        !settings.hiddenPanelStatusItems.contains(item)
    }

    func setStatusItem(_ item: PanelStatusItem, isVisible: Bool) {
        settings.setPanelStatusItem(item, isVisible: isVisible)
    }

    /// @note p0-260
    func statusItemNote(_ item: PanelStatusItem) -> StatusItemNote? {
        // @note p0-261
        switch item {
        case .commit:
            settings.commitKey == nil ? .keyNotAssigned : nil
        case .commitAndSend:
            settings.commitAndSendKey == nil ? .keyNotAssigned : nil
        case .lineBreak, .close, .characterCount, .lineCount:
            nil
        }
    }

    /// @note p0-262
    private static func isSystemFontName(_ name: String?) -> Bool {
        guard let name else { return true }
        return name.isEmpty || name.hasPrefix(".")
    }
}
