import Foundation

/// 開き直しで残す書きかけのファイルの読み書き。`directory` が `nil` ならメモリだけで、ファイルに触れない。
struct RelaunchDraftStore {
    static let fileName = "relaunch-draft.json"

    let directory: URL?

    /// 書きかけをファイルに書く。書けなければ投げる。
    func save(_ draft: RelaunchDraft) throws {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.makeEncoder().encode(draft)
            try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
        } catch {
            throw DraftLibraryStoreError.writeFailed(fileName: Self.fileName)
        }
    }

    /// 残した書きかけを読んでファイルを消す。無い・読めない・形の版が違うときは `nil`。
    func take() -> RelaunchDraft? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url),
              let draft = try? JSONDecoder().decode(RelaunchDraft.self, from: data),
              draft.version == RelaunchDraft.currentVersion else { return nil }
        return draft
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

}
