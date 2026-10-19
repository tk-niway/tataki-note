import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct DraftLibraryTests {
    private final class Clock {
        private var current = Date(timeIntervalSince1970: 1_700_000_000)

        func tick() -> Date {
            defer { current = current.addingTimeInterval(1) }
            return current
        }
    }

    private func makeLibrary(
        in directory: DraftLibraryTestDirectory,
        clock: Clock = Clock(),
        historyLimit: Int = HistoryLimit.defaultValue
    ) -> DraftLibrary {
        DraftLibrary(
            store: DraftLibraryStore(directory: directory.dataDirectory),
            historyLimit: historyLimit,
            now: { clock.tick() }
        )
    }

    private func blockDataDirectory(in directory: DraftLibraryTestDirectory) throws {
        try FileManager.default.createDirectory(at: directory.root, withIntermediateDirectories: true)
        try Data("file".utf8).write(to: directory.dataDirectory)
    }

    private func unblockDataDirectory(in directory: DraftLibraryTestDirectory) throws {
        try FileManager.default.removeItem(at: directory.dataDirectory)
    }

    // MARK: - 下書き

    @Test("AC-1: 保存した下書きは、新しい DraftLibrary で読み直しても同じ本文・同じ並びで残る")
    func draftsSurviveRecreation() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory)

        library.addDraft(text: "first")
        library.addDraft(text: "second\nline")

        let reloaded = makeLibrary(in: directory)
        #expect(reloaded.drafts.map(\.text) == ["second\nline", "first"])
        #expect(reloaded.drafts == library.drafts)
        #expect(reloaded.problems.isEmpty)
    }

    @Test("AC-1: 本文が空のときは下書きを足さず、何も書き出さない")
    func emptyTextIsNotAdded() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory)

        #expect(library.addDraft(text: "") == nil)
        #expect(library.drafts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.dataDirectory.path))
    }

    @Test("AC-2: 下書きは最後に保存・書き換えたものが上に並び、書き換えると先頭に移る")
    func draftsAreOrderedByLastUpdate() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory)
        let first = try #require(library.addDraft(text: "A"))
        let second = try #require(library.addDraft(text: "B"))
        let third = try #require(library.addDraft(text: "C"))
        #expect(library.drafts.map(\.id) == [third.id, second.id, first.id])

        library.updateDraft(id: first.id, text: "A2")

        #expect(library.drafts.map(\.id) == [first.id, third.id, second.id])
        #expect(library.drafts.map(\.text) == ["A2", "C", "B"])
        let updated = try #require(library.draft(id: first.id))
        #expect(updated.updatedAt > third.updatedAt)
    }

    @Test("AC-2: 書き換えた並びは、flush の後に読み直しても保たれる")
    func updatedOrderSurvivesFlushAndRecreation() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory)
        let first = try #require(library.addDraft(text: "A"))
        library.addDraft(text: "B")

        library.updateDraft(id: first.id, text: "A2")
        library.flush()

        let reloaded = makeLibrary(in: directory)
        #expect(reloaded.drafts.map(\.text) == ["A2", "B"])
        #expect(reloaded.drafts.first?.id == first.id)
    }

    @Test("AC-2: 書き換えは flush まで書き出されず、flush で書き出される")
    func updateIsDeferredUntilFlush() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory)
        let draft = try #require(library.addDraft(text: "before"))
        #expect(!library.hasPendingWrite)

        library.updateDraft(id: draft.id, text: "after")

        #expect(library.hasPendingWrite)
        #expect(makeLibrary(in: directory).drafts.map(\.text) == ["before"])
        library.flush()
        #expect(!library.hasPendingWrite)
        #expect(makeLibrary(in: directory).drafts.map(\.text) == ["after"])
    }

    @Test("AC-2: 無い下書きの書き換え・削除は何もしない")
    func unknownDraftIsIgnored() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory)
        library.addDraft(text: "keep")

        library.updateDraft(id: UUID(), text: "x")
        library.deleteDraft(id: UUID())

        #expect(library.drafts.map(\.text) == ["keep"])
        #expect(!library.hasPendingWrite)
    }

    @Test("AC-1: 下書きの削除はすぐ書き出され、読み直しても消えたまま")
    func deletedDraftStaysDeleted() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory)
        let first = try #require(library.addDraft(text: "A"))
        library.addDraft(text: "B")

        library.deleteDraft(id: first.id)

        #expect(library.draft(id: first.id) == nil)
        #expect(makeLibrary(in: directory).drafts.map(\.text) == ["B"])
    }

    // MARK: - 履歴

    @Test("AC-3: 履歴には本文・挿入日時・挿入先のアプリ名が残り、新しいものが上に並び、読み直しても残る")
    func historyRecordsInsertionsNewestFirst() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory)

        library.recordInsertion(text: "one", appName: "Safari", bundleIdentifier: "com.apple.Safari")
        library.recordInsertion(text: "two", appName: nil, bundleIdentifier: nil)

        #expect(library.history.map(\.text) == ["two", "one"])
        let oldest = try #require(library.history.last)
        #expect(oldest.appName == "Safari")
        #expect(oldest.bundleIdentifier == "com.apple.Safari")
        #expect(library.history[0].insertedAt > oldest.insertedAt)

        let reloaded = makeLibrary(in: directory)
        #expect(reloaded.history == library.history)
        #expect(reloaded.history.last?.appName == "Safari")
    }

    @Test("AC-3: 51 件目を足すと最も古いものが消えて 50 件になり、読み直しても 50 件")
    func historyKeepsLatestFifty() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory, historyLimit: 50)

        for number in 1...library.historyLimit {
            library.recordInsertion(text: "entry \(number)", appName: nil, bundleIdentifier: nil)
        }
        #expect(library.history.count == 50)
        #expect(library.history.last?.text == "entry 1")

        library.recordInsertion(text: "entry 51", appName: nil, bundleIdentifier: nil)

        #expect(library.historyLimit == 50)
        #expect(library.history.count == 50)
        #expect(library.history.first?.text == "entry 51")
        #expect(library.history.last?.text == "entry 2")
        #expect(makeLibrary(in: directory, historyLimit: 50).history.map(\.text) == library.history.map(\.text))
    }

    @Test("AC-3: 履歴の1件の削除と、すべての削除は書き出され、読み直しても消えたまま")
    func historyDeletionPersists() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let library = makeLibrary(in: directory)
        library.recordInsertion(text: "one", appName: nil, bundleIdentifier: nil)
        library.recordInsertion(text: "two", appName: nil, bundleIdentifier: nil)
        let newest = try #require(library.history.first)
        #expect(library.historyEntry(id: newest.id) == newest)

        library.deleteHistoryEntry(id: newest.id)

        #expect(library.historyEntry(id: newest.id) == nil)
        #expect(makeLibrary(in: directory).history.map(\.text) == ["one"])

        library.clearHistory()

        #expect(library.history.isEmpty)
        #expect(makeLibrary(in: directory).history.isEmpty)
    }

    // MARK: - 一覧の1行目

    @Test("AC-1: 一覧の1行目は先頭の空行を飛ばした最初の行で、前後の空白を除く。無ければ nil")
    func firstLineSkipsLeadingBlankLines() {
        #expect(DraftListing.firstLine(of: "hello") == "hello")
        #expect(DraftListing.firstLine(of: "\n\n  second \nthird") == "second")
        #expect(DraftListing.firstLine(of: "a\nb") == "a")
        #expect(DraftListing.firstLine(of: "") == nil)
        #expect(DraftListing.firstLine(of: " \n\t\n  ") == nil)
    }

    // MARK: - 読めないファイル

    @Test("AC-4: 下書きのファイルが読めないときは別名で残して空で始め、読み込みの失敗が分かる。次の保存でも別名は残り失敗の状態も消えない")
    func unreadableDraftsFileIsSetAside() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try directory.write("broken", named: DraftLibraryStore.draftsFileName)

        let library = makeLibrary(in: directory)

        #expect(library.drafts.isEmpty)
        #expect(library.problems == [.draftsUnreadable])
        #expect(directory.read(DraftLibraryStore.draftsFileName) == nil)
        let setAside = directory.fileNames().filter { $0.hasPrefix("drafts.unreadable-") }
        #expect(setAside.count == 1)
        #expect(directory.read(try #require(setAside.first)) == "broken")

        library.addDraft(text: "new")

        #expect(library.problems == [.draftsUnreadable])
        #expect(directory.fileNames().filter { $0.hasPrefix("drafts.unreadable-") } == setAside)
        #expect(directory.read(DraftLibraryStore.draftsFileName) != nil)
    }

    @Test("AC-4: 履歴のファイルが読めないとき(version が違う)も同じ。どちらの失敗かが分かる")
    func unreadableHistoryFileIsSetAside() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try directory.write("{\"version\": 2, \"history\": []}", named: DraftLibraryStore.historyFileName)

        let library = makeLibrary(in: directory)

        #expect(library.history.isEmpty)
        #expect(library.problems == [.historyUnreadable])
        #expect(directory.fileNames().contains { $0.hasPrefix("history.unreadable-") })

        library.recordInsertion(text: "x", appName: nil, bundleIdentifier: nil)

        #expect(library.problems == [.historyUnreadable])
        #expect(directory.fileNames().contains { $0.hasPrefix("history.unreadable-") })
        #expect(makeLibrary(in: directory).problems.isEmpty)
    }

    @Test("AC-4: 両方のファイルが読めないときは両方の失敗が分かり、どちらも別名で残る。次の起動では出ない")
    func bothUnreadableFilesAreReported() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try directory.write("{", named: DraftLibraryStore.draftsFileName)
        try directory.write("[]", named: DraftLibraryStore.historyFileName)

        let library = makeLibrary(in: directory)

        #expect(library.problems == [.draftsUnreadable, .historyUnreadable])
        #expect(directory.fileNames().count == 2)
        library.addDraft(text: "a")
        library.recordInsertion(text: "b", appName: nil, bundleIdentifier: nil)
        #expect(library.problems == [.draftsUnreadable, .historyUnreadable])

        let next = makeLibrary(in: directory)
        #expect(next.problems.isEmpty)
        #expect(next.drafts.map(\.text) == ["a"])
        #expect(next.history.map(\.text) == ["b"])
    }

    @Test("AC-4: 何も問題が無ければ problems は空")
    func noProblemsByDefault() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }

        #expect(makeLibrary(in: directory).problems.isEmpty)
        #expect(DraftLibrary(store: .inMemory).problems.isEmpty)
    }

    // MARK: - 書き出しの失敗

    @Test("AC-5: 保存先に書けないときは保存の失敗が分かり、一覧の中身は保たれる。書けるようになって保存できたら消える")
    func saveFailureIsReportedAndRecovers() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try blockDataDirectory(in: directory)
        let library = makeLibrary(in: directory)

        let draft = try #require(library.addDraft(text: "kept in memory"))

        #expect(library.problems == [.saveFailed])
        #expect(library.drafts == [draft])
        #expect(library.hasPendingWrite)

        try unblockDataDirectory(in: directory)
        library.flush()

        #expect(library.problems.isEmpty)
        #expect(!library.hasPendingWrite)
        #expect(makeLibrary(in: directory).drafts == [draft])
    }

    @Test("AC-5: 履歴の書き出しの失敗も同じ。ファイルごとに覚え、両方が成功するまで保存の失敗は消えない")
    func saveFailureIsTrackedPerFile() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try blockDataDirectory(in: directory)
        let library = makeLibrary(in: directory)
        library.addDraft(text: "draft")
        library.recordInsertion(text: "history", appName: nil, bundleIdentifier: nil)
        #expect(library.problems == [.saveFailed])
        #expect(library.history.map(\.text) == ["history"])

        try unblockDataDirectory(in: directory)
        library.flush()
        #expect(library.problems == [.saveFailed])

        library.recordInsertion(text: "history 2", appName: nil, bundleIdentifier: nil)

        #expect(library.problems.isEmpty)
        let reloaded = makeLibrary(in: directory)
        #expect(reloaded.drafts.map(\.text) == ["draft"])
        #expect(reloaded.history.map(\.text) == ["history 2", "history"])
    }

    @Test("AC-5: 読み込みの失敗は、書き出しが成功しても消えない(保存の失敗だけが消える)")
    func unreadableProblemSurvivesSuccessfulWrite() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try directory.write("broken", named: DraftLibraryStore.draftsFileName)
        let library = makeLibrary(in: directory)
        #expect(library.problems == [.draftsUnreadable])

        try FileManager.default.removeItem(at: directory.dataDirectory)
        try Data("file".utf8).write(to: directory.dataDirectory)
        library.recordInsertion(text: "x", appName: nil, bundleIdentifier: nil)
        #expect(library.problems == [.draftsUnreadable, .saveFailed])

        try unblockDataDirectory(in: directory)
        library.recordInsertion(text: "y", appName: nil, bundleIdentifier: nil)

        #expect(library.problems == [.draftsUnreadable])
    }

    @Test("AC-5: 保存先が無し(メモリだけ)でも一覧は動き、失敗にならない")
    func inMemoryLibraryWorks() {
        let library = DraftLibrary(store: .inMemory)

        library.addDraft(text: "a")
        library.recordInsertion(text: "b", appName: nil, bundleIdentifier: nil)
        library.flush()

        #expect(library.drafts.map(\.text) == ["a"])
        #expect(library.history.map(\.text) == ["b"])
        #expect(library.problems.isEmpty)
    }
}
