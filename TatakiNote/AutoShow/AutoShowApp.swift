/// 「選んだアプリのみ」で選んだアプリ。
struct AutoShowApp: Codable, Equatable, Identifiable, Sendable {
    var bundleIdentifier: String
    var name: String

    var id: String { bundleIdentifier }

    static func normalized(_ apps: [AutoShowApp]) -> [AutoShowApp] {
        var seen: Set<String> = []
        return apps.filter { app in
            !app.bundleIdentifier.isEmpty && seen.insert(app.bundleIdentifier).inserted
        }
    }

    static func contains(_ apps: [AutoShowApp], bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return apps.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}
