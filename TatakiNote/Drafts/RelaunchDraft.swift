import Foundation

/// 開き直しのときに残すパネルの書きかけ。
struct RelaunchDraft: Codable, Equatable {
    enum Document: Codable, Equatable {
        case scratch
        case savedDraft(UUID)
        case fromHistory(UUID)
    }

    static let currentVersion = 1

    var version: Int
    var text: String
    var document: Document
    var mode: DraftMode
}
