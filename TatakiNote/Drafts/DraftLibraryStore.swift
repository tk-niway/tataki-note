import Foundation

/// 下書きと履歴のファイルの読み書きで起きる失敗。
nonisolated enum DraftLibraryStoreError: Error, Equatable {
    case unreadable(fileName: String)
    case writeFailed(fileName: String)
}

/// 下書きと履歴の JSON ファイルの読み書き。`directory` が `nil` ならメモリだけで、ファイルに触れない。
nonisolated struct DraftLibraryStore: Sendable {
    static let draftsFileName = "drafts.json"
    static let historyFileName = "history.json"
    static let inMemory = DraftLibraryStore(directory: nil)

    private static let currentVersion = 1

    let directory: URL?

    func loadDrafts() throws -> [SavedDraft] {
        try load(DraftsEnvelope.self, fileName: Self.draftsFileName)?.drafts ?? []
    }

    func saveDrafts(_ drafts: [SavedDraft]) throws {
        try save(DraftsEnvelope(version: Self.currentVersion, drafts: drafts), fileName: Self.draftsFileName)
    }

    func loadHistory() throws -> [HistoryEntry] {
        try load(HistoryEnvelope.self, fileName: Self.historyFileName)?.history ?? []
    }

    func saveHistory(_ history: [HistoryEntry]) throws {
        try save(HistoryEnvelope(version: Self.currentVersion, history: history), fileName: Self.historyFileName)
    }

    /// 読めなかったファイルを `drafts.unreadable-yyyyMMdd-HHmmss.json` のような別名に変えて残す。
    func setAsideUnreadableFile(named fileName: String, now: Date) {
        guard let directory else { return }
        let source = directory.appendingPathComponent(fileName)
        let base = (fileName as NSString).deletingPathExtension
        let stamp = Self.timestampFormatter.string(from: now)
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent("\(base).unreadable-\(stamp).json")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base).unreadable-\(stamp)-\(suffix).json")
            suffix += 1
        }
        try? fileManager.moveItem(at: source, to: candidate)
    }

    // MARK: - 読み書き

    private func load<Envelope: VersionedEnvelope>(_ type: Envelope.Type, fileName: String) throws -> Envelope? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let envelope = try Self.makeDecoder().decode(Envelope.self, from: data)
            guard envelope.version == Self.currentVersion else {
                throw DraftLibraryStoreError.unreadable(fileName: fileName)
            }
            return envelope
        } catch {
            throw DraftLibraryStoreError.unreadable(fileName: fileName)
        }
    }

    private func save<Envelope: Encodable>(_ envelope: Envelope, fileName: String) throws {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.makeEncoder().encode(envelope)
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        } catch {
            throw DraftLibraryStoreError.writeFailed(fileName: fileName)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var timestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }
}

// MARK: - 封筒

private nonisolated protocol VersionedEnvelope: Decodable {
    var version: Int { get }
}

private nonisolated struct DraftsEnvelope: VersionedEnvelope, Codable {
    var version: Int
    var drafts: [SavedDraft]
}

private nonisolated struct HistoryEnvelope: VersionedEnvelope, Codable {
    var version: Int
    var history: [HistoryEntry]
}
