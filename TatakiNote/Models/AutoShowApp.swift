/// @note p0-184
struct AutoShowApp: Codable, Equatable, Identifiable, Sendable {
    /// @note p0-185
    var bundleIdentifier: String
    /// @note p0-186
    var name: String

    var id: String { bundleIdentifier }

    /// @note p0-187
    static func normalized(_ apps: [AutoShowApp]) -> [AutoShowApp] {
        var seen: Set<String> = []
        return apps.filter { app in
            !app.bundleIdentifier.isEmpty && seen.insert(app.bundleIdentifier).inserted
        }
    }

    /// @note p0-188
    static func contains(_ apps: [AutoShowApp], bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return apps.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}
