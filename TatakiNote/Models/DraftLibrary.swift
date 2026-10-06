import Foundation
import Observation

/// 保存した下書き。
struct SavedDraft: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    var updatedAt: Date
}

/// 挿入に成功した文章の履歴の1件。
struct HistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let insertedAt: Date
    let appName: String?
    let bundleIdentifier: String?
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
}

/// 下書き・履歴の保存と読み込みで今起きている問題。
enum DraftLibraryProblem: Equatable, Hashable {
    case draftsUnreadable
    case historyUnreadable
    case saveFailed
}

/// 保存した下書きと挿入の履歴の一覧。
@Observable final class DraftLibrary {
    static let historyLimit = 50

    private(set) var drafts: [SavedDraft] = []
    private(set) var history: [HistoryEntry] = []
    private(set) var problems: Set<DraftLibraryProblem> = []

    private let store: DraftLibraryStore
    private let now: () -> Date
    private var unreadableProblems: Set<DraftLibraryProblem> = []
    private var failedFileNames: Set<String> = []
    private var isDraftsWritePending = false

    init(store: DraftLibraryStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
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

    /// 挿入に成功した文章を履歴の先頭に足し、最新 50 件に切ってすぐ書き出す。
    func recordInsertion(text: String, appName: String?, bundleIdentifier: String?) {
        let entry = HistoryEntry(
            id: UUID(),
            text: text,
            insertedAt: now(),
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        writeHistory()
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
            history = Array(try store.loadHistory().prefix(Self.historyLimit))
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
