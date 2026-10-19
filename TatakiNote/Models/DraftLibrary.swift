import Foundation
import Observation

/// 保存した下書き。
struct SavedDraft: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    var updatedAt: Date
}

/// 履歴の1件。挿入した文章と、挿入していない文章がある。
struct HistoryEntry: Equatable, Identifiable {
    let id: UUID
    let text: String
    let insertedAt: Date
    let appName: String?
    let bundleIdentifier: String?
    let isInserted: Bool

    init(
        id: UUID,
        text: String,
        insertedAt: Date,
        appName: String?,
        bundleIdentifier: String?,
        isInserted: Bool = true
    ) {
        self.id = id
        self.text = text
        self.insertedAt = insertedAt
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.isInserted = isInserted
    }
}

extension HistoryEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, text, insertedAt, appName, bundleIdentifier, isInserted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        insertedAt = try container.decode(Date.self, forKey: .insertedAt)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        isInserted = try container.decodeIfPresent(Bool.self, forKey: .isInserted) ?? true
    }
}

/// 一覧の行に出す文字の取り出し。
enum DraftListing {
    /// 先頭の空行を飛ばした最初の行(前後の空白を除く)。無ければ `nil`。
    static func firstLine(of text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// `preview(of:)` が返す文字数の上限。
    nonisolated static let previewLimit = 200

    /// 最初の行より後の、空でない行を半角スペースでつないだ文字(先頭の `previewLimit` 文字まで)。無ければ `nil`。
    nonisolated static func preview(of text: String) -> String? {
        var joined = ""
        var hasFirstLine = false
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            var lineEnd = lineStart
            while lineEnd < text.endIndex, !text[lineEnd].isNewline {
                lineEnd = text.index(after: lineEnd)
            }
            let line = text[lineStart..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
            if line.isEmpty { continue }
            if !hasFirstLine {
                hasFirstLine = true
                continue
            }
            if !joined.isEmpty { joined += " " }
            joined += line
            if joined.count >= previewLimit { break }
        }
        return joined.isEmpty ? nil : String(joined.prefix(previewLimit))
    }
}

/// 下書き・履歴の保存と読み込みで今起きている問題。
enum DraftLibraryProblem: Equatable, Hashable {
    case draftsUnreadable
    case historyUnreadable
    case saveFailed
}

/// 保存した下書きと挿入の履歴の一覧。
@Observable final class DraftLibrary {
    private(set) var historyLimit: Int
    private(set) var drafts: [SavedDraft] = []
    private(set) var history: [HistoryEntry] = []
    private(set) var problems: Set<DraftLibraryProblem> = []

    private let store: DraftLibraryStore
    private let now: () -> Date
    private var unreadableProblems: Set<DraftLibraryProblem> = []
    private var failedFileNames: Set<String> = []
    private var isDraftsWritePending = false

    init(
        store: DraftLibraryStore,
        historyLimit: Int = HistoryLimit.defaultValue,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
        self.historyLimit = HistoryLimit.clamped(historyLimit)
        loadDrafts()
        loadHistory()
        refreshProblems()
    }

    /// 書き出しを遅らせている下書きがあるか。
    var hasPendingWrite: Bool { isDraftsWritePending }

    // MARK: - 下書き

    /// 文章を新しい下書きとして先頭に足してすぐ書き出す。空なら何もせず `nil`。
    @discardableResult
    func addDraft(text: String) -> SavedDraft? {
        guard !text.isEmpty else { return nil }
        let draft = SavedDraft(id: UUID(), text: text, updatedAt: now())
        drafts.insert(draft, at: 0)
        writeDrafts()
        return draft
    }

    /// 本文と更新日時を変えて先頭へ移す。書き出しは `flush()` まで遅らせる。
    func updateDraft(id: UUID, text: String) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        var draft = drafts.remove(at: index)
        draft.text = text
        draft.updatedAt = now()
        drafts.insert(draft, at: 0)
        isDraftsWritePending = true
    }

    /// 下書きを消してすぐ書き出す。
    func deleteDraft(id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts.remove(at: index)
        writeDrafts()
    }

    func draft(id: UUID) -> SavedDraft? {
        drafts.first { $0.id == id }
    }

    /// 遅らせている下書きの書き出しを今行う。
    func flush() {
        guard isDraftsWritePending else { return }
        writeDrafts()
    }

    // MARK: - 履歴

    /// 挿入に成功した文章を履歴の先頭に足し、上限の件数に切ってすぐ書き出す。
    func recordInsertion(text: String, appName: String?, bundleIdentifier: String?) {
        prepend(HistoryEntry(
            id: UUID(),
            text: text,
            insertedAt: now(),
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            isInserted: true
        ))
    }

    /// 挿入していない文章を履歴の先頭に足し、上限の件数に切ってすぐ書き出す。
    func recordUnsentText(_ text: String) {
        prepend(HistoryEntry(
            id: UUID(),
            text: text,
            insertedAt: now(),
            appName: nil,
            bundleIdentifier: nil,
            isInserted: false
        ))
    }

    /// 履歴の上限を範囲に丸めて変え、超えた古い履歴を消す。超えていなければ書き出さない。
    func setHistoryLimit(_ limit: Int) {
        historyLimit = HistoryLimit.clamped(limit)
        guard history.count > historyLimit else { return }
        history.removeLast(history.count - historyLimit)
        writeHistory()
    }

    /// 上限を `limit` にしたときに消える履歴の件数。
    func historyOverflow(forLimit limit: Int) -> Int {
        max(0, history.count - HistoryLimit.clamped(limit))
    }

    func historyEntry(id: UUID) -> HistoryEntry? {
        history.first { $0.id == id }
    }

    /// 履歴の1件を消してすぐ書き出す。
    func deleteHistoryEntry(id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history.remove(at: index)
        writeHistory()
    }

    /// 履歴をすべて消してすぐ書き出す。
    func clearHistory() {
        history.removeAll()
        writeHistory()
    }

    // MARK: - 読み込み

    private func loadDrafts() {
        do {
            drafts = try store.loadDrafts()
        } catch {
            store.setAsideUnreadableFile(named: DraftLibraryStore.draftsFileName, now: now())
            unreadableProblems.insert(.draftsUnreadable)
        }
    }

    private func loadHistory() {
        do {
            history = Array(try store.loadHistory().prefix(historyLimit))
        } catch {
            store.setAsideUnreadableFile(named: DraftLibraryStore.historyFileName, now: now())
            unreadableProblems.insert(.historyUnreadable)
        }
    }

    // MARK: - 書き出し

    private func writeDrafts() {
        do {
            try store.saveDrafts(drafts)
            isDraftsWritePending = false
            failedFileNames.remove(DraftLibraryStore.draftsFileName)
        } catch {
            isDraftsWritePending = true
            failedFileNames.insert(DraftLibraryStore.draftsFileName)
        }
        refreshProblems()
    }

    private func prepend(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > historyLimit {
            history.removeLast(history.count - historyLimit)
        }
        writeHistory()
    }

    private func writeHistory() {
        do {
            try store.saveHistory(history)
            failedFileNames.remove(DraftLibraryStore.historyFileName)
        } catch {
            failedFileNames.insert(DraftLibraryStore.historyFileName)
        }
        refreshProblems()
    }

    private func refreshProblems() {
        var current = unreadableProblems
        if !failedFileNames.isEmpty {
            current.insert(.saveFailed)
        }
        if problems != current {
            problems = current
        }
    }
}
