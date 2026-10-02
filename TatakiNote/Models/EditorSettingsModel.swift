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
    /// @note p0-247
    static func make(
        families: [String],
        members: (String) -> [[Any]]?,
        localizedName: (String) -> String
    ) -> [FontChoice] {
        let familyChoices = families.compactMap { family -> FontChoice? in
            guard !family.hasPrefix("."),
                  let postScriptName = PanelTextStyle.regularPostScriptName(members: members(family) ?? [])
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
            guard let name, !PanelTextStyle.isSystemFontName(name) else { return FontChoice.systemID }
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

    /// 今のフォントの表示名。システムフォントのときは「システムフォント」。
    var fontDisplayName: String {
        guard let font = settings.resolvedPanelFont else { return String(localized: "システムフォント") }
        return font.displayName ?? font.fontName
    }

    /// 書体を選んでいない(システムフォントを使っている)とき true。
    var isSystemFont: Bool {
        settings.resolvedPanelFont == nil
    }

    /// フォントをシステムフォントに戻す。
    func resetFontToSystem() {
        settings.resetPanelFontToSystem()
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
}
