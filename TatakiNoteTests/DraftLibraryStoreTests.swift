import Foundation
import Testing
@testable import TatakiNote

/// テストごとの一時ディレクトリ。
final class DraftLibraryTestDirectory {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TatakiNoteTests-\(UUID().uuidString)", isDirectory: true)
    }

    var dataDirectory: URL { root.appendingPathComponent("data", isDirectory: true) }

    func fileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dataDirectory.path)) ?? []).sorted()
    }

    func write(_ contents: String, named fileName: String) throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: dataDirectory.appendingPathComponent(fileName))
    }

    func read(_ fileName: String) -> String? {
        (try? Data(contentsOf: dataDirectory.appendingPathComponent(fileName))).flatMap { String(data: $0, encoding: .utf8) }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
struct DraftLibraryStoreTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("AC-1: 保存した下書きは、同じ保存先から読み直すと同じ本文・同じ並びで返り、無いディレクトリは作られる")
    func draftsRoundTripAndCreateDirectory() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)
        let drafts = [
            SavedDraft(id: UUID(), text: "二つ目\n改行あり", updatedAt: date.addingTimeInterval(60)),
            SavedDraft(id: UUID(), text: "one", updatedAt: date),
        ]

        #expect(!FileManager.default.fileExists(atPath: directory.dataDirectory.path))
        try store.saveDrafts(drafts)

        #expect(FileManager.default.fileExists(atPath: directory.dataDirectory.path))
        #expect(try store.loadDrafts() == drafts)
    }

    @Test("AC-3: 履歴は本文・挿入日時・挿入先のアプリ名・bundle ID を保ったまま読み直せる")
    func historyRoundTrips() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)
        let history = [
            HistoryEntry(id: UUID(), text: "hello", insertedAt: date, appName: "Safari", bundleIdentifier: "com.apple.Safari"),
            HistoryEntry(id: UUID(), text: "名無し", insertedAt: date.addingTimeInterval(-5), appName: nil, bundleIdentifier: nil),
        ]

        try store.saveHistory(history)

        #expect(try store.loadHistory() == history)
    }

    @Test("AC-1: ファイルが無ければ空で返り、ファイルは作られない")
    func missingFilesLoadAsEmpty() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)

        #expect(try store.loadDrafts().isEmpty)
        #expect(try store.loadHistory().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.dataDirectory.path))
    }

    @Test("AC-1: 保存先が無し(メモリだけ)のときは、読み書きがファイルに触れない")
    func inMemoryStoreDoesNotTouchFiles() throws {
        let store = DraftLibraryStore.inMemory

        try store.saveDrafts([SavedDraft(id: UUID(), text: "x", updatedAt: date)])
        try store.saveHistory([])

        #expect(try store.loadDrafts().isEmpty)
        #expect(try store.loadHistory().isEmpty)
    }

    @Test("AC-1: ファイルは version 1 の封筒に入った ISO 8601 の日付の JSON")
    func fileFormatIsVersionedEnvelopeWithISODates() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)
        try store.saveDrafts([SavedDraft(id: UUID(), text: "x", updatedAt: Date(timeIntervalSince1970: 0))])
        try store.saveHistory([])

        let drafts = try #require(directory.read(DraftLibraryStore.draftsFileName))
        #expect(drafts.contains("\"version\" : 1"))
        #expect(drafts.contains("\"drafts\""))
        #expect(drafts.contains("1970-01-01T00:00:00Z"))
        let history = try #require(directory.read(DraftLibraryStore.historyFileName))
        #expect(history.contains("\"version\" : 1"))
        #expect(history.contains("\"history\""))
    }

    @Test("AC-4: 壊れたファイル・形式が違うファイル・version が違うファイルは読めないものとして扱う")
    func unreadableFilesThrow() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)
        let draftsName = DraftLibraryStore.draftsFileName

        for contents in [
            "not json",
            "[]",
            "{\"version\": 1}",
            "{\"version\": 2, \"drafts\": []}",
            "{\"version\": 1, \"drafts\": [{\"id\": \"x\"}]}",
        ] {
            try directory.write(contents, named: draftsName)
            #expect(throws: DraftLibraryStoreError.unreadable(fileName: draftsName), "\(contents)") {
                try store.loadDrafts()
            }
        }

        try directory.write("{\"version\": 9, \"history\": []}", named: DraftLibraryStore.historyFileName)
        #expect(throws: DraftLibraryStoreError.unreadable(fileName: DraftLibraryStore.historyFileName)) {
            try store.loadHistory()
        }
    }

    @Test("AC-4: 読めないファイルは unreadable-日時 の別名で残り、元の名前は空く")
    func setAsideRenamesTheFile() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)
        try directory.write("broken", named: DraftLibraryStore.draftsFileName)

        store.setAsideUnreadableFile(named: DraftLibraryStore.draftsFileName, now: date)

        let names = directory.fileNames()
        #expect(names.count == 1)
        let name = try #require(names.first)
        #expect(name.hasPrefix("drafts.unreadable-"))
        #expect(name.hasSuffix(".json"))
        #expect(directory.read(name) == "broken")
    }

    @Test("AC-4: 同じ秒に二度退避しても、先に残した別名を上書きしない")
    func setAsideDoesNotOverwriteEarlierCopy() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)

        try directory.write("first", named: DraftLibraryStore.draftsFileName)
        store.setAsideUnreadableFile(named: DraftLibraryStore.draftsFileName, now: date)
        try directory.write("second", named: DraftLibraryStore.draftsFileName)
        store.setAsideUnreadableFile(named: DraftLibraryStore.draftsFileName, now: date)

        let contents = Set(directory.fileNames().compactMap { directory.read($0) })
        #expect(directory.fileNames().count == 2)
        #expect(contents == ["first", "second"])
    }

    @Test("AC-5: 保存先のディレクトリを作れないときは writeFailed を投げる")
    func saveThrowsWhenDirectoryCannotBeCreated() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try FileManager.default.createDirectory(at: directory.root, withIntermediateDirectories: true)
        try Data("file".utf8).write(to: directory.dataDirectory)
        let store = DraftLibraryStore(directory: directory.dataDirectory)

        #expect(throws: DraftLibraryStoreError.writeFailed(fileName: DraftLibraryStore.draftsFileName)) {
            try store.saveDrafts([])
        }
        #expect(throws: DraftLibraryStoreError.writeFailed(fileName: DraftLibraryStore.historyFileName)) {
            try store.saveHistory([])
        }
    }
}
