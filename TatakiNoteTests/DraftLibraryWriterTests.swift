import Foundation
import Testing
@testable import TatakiNote

private nonisolated final class WriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var runs: [String] = []
    private var mainThreadRuns = 0

    func record(_ label: String) {
        lock.lock()
        defer { lock.unlock() }
        runs.append(label)
        if Thread.isMainThread { mainThreadRuns += 1 }
    }

    var recorded: [String] {
        lock.lock()
        defer { lock.unlock() }
        return runs
    }

    var ranOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadRuns > 0
    }
}

@MainActor
struct DraftLibraryWriterTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func block(_ writer: BackgroundDraftLibraryWriter, until gate: DispatchSemaphore) {
        writer.write(fileName: "blocker", { gate.wait() }, completion: { _ in })
    }

    @Test("AC-15: 背景の書き手は書き出しをメインスレッドの外で行い、同じファイルの待っている書き出しは最後の1つだけ行う")
    func backgroundWriterRunsOffMainAndCoalesces() async {
        let writer = BackgroundDraftLibraryWriter()
        let recorder = WriteRecorder()
        let gate = DispatchSemaphore(value: 0)
        block(writer, until: gate)

        var results: [DraftLibraryWriteResult] = []
        for label in ["first", "second", "third"] {
            writer.write(fileName: "a.json", { recorder.record(label) }, completion: { results.append($0) })
        }
        writer.write(fileName: "b.json", { recorder.record("other") }, completion: { results.append($0) })
        gate.signal()
        writer.waitUntilIdle()

        #expect(recorder.recorded == ["third", "other"])
        #expect(!recorder.ranOnMainThread)
        await waitUntil { results.count == 2 }
        #expect(results == [
            DraftLibraryWriteResult(fileName: "a.json", succeeded: true),
            DraftLibraryWriteResult(fileName: "b.json", succeeded: true),
        ])
    }

    @Test("AC-15: 背景の書き手で頼んだ下書きは、waitUntilIdle の後にファイルを読み直すと最後の中身がある")
    func backgroundWriterWritesLastContents() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)
        let writer = BackgroundDraftLibraryWriter()
        let library = DraftLibrary(store: store, writer: writer, now: { date })

        library.addDraft(text: "one")
        library.addDraft(text: "two")
        library.addDraft(text: "three")
        writer.waitUntilIdle()

        let reloaded = DraftLibrary(store: store)
        #expect(reloaded.drafts.map(\.text) == ["three", "two", "one"])
    }

    @Test("AC-16: 背景の書き手でも、書き出しに失敗すると保存の失敗が出て下書きは書き出し待ちに戻り、次に成功すると保存の失敗が消える")
    func backgroundFailureSurfacesAndRecovers() async throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try FileManager.default.createDirectory(at: directory.root, withIntermediateDirectories: true)
        try Data().write(to: directory.dataDirectory)
        let writer = BackgroundDraftLibraryWriter()
        let library = DraftLibrary(
            store: DraftLibraryStore(directory: directory.dataDirectory),
            writer: writer,
            now: { date }
        )

        library.addDraft(text: "kept")
        writer.waitUntilIdle()
        await waitUntil { library.problems.contains(.saveFailed) }

        #expect(library.problems.contains(.saveFailed))
        #expect(library.hasPendingWrite)

        try FileManager.default.removeItem(at: directory.dataDirectory)
        library.flush()
        writer.waitUntilIdle()
        await waitUntil { !library.problems.contains(.saveFailed) }

        #expect(!library.problems.contains(.saveFailed))
        #expect(!library.hasPendingWrite)
        #expect(try DraftLibraryStore(directory: directory.dataDirectory).loadDrafts().map(\.text) == ["kept"])
    }

    @Test("AC-17: finishPendingWrites の後は、遅らせた下書きの書き換えと頼んだ履歴の書き出しが全部ファイルにあり、flush は書き出しの終わりを待たない")
    func finishPendingWritesWritesEverythingAndFlushDoesNotWait() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)
        let writer = BackgroundDraftLibraryWriter()
        let library = DraftLibrary(store: store, writer: writer, now: { date })
        let draft = library.addDraft(text: "before")
        writer.waitUntilIdle()

        let gate = DispatchSemaphore(value: 0)
        block(writer, until: gate)
        library.updateDraft(id: draft?.id ?? UUID(), text: "after")
        library.recordInsertion(text: "inserted", appName: "Notes", bundleIdentifier: "com.apple.Notes")
        library.flush()

        #expect(library.hasPendingWrite == false)
        #expect((try? store.loadDrafts().map(\.text)) == ["before"])
        #expect(((try? store.loadHistory()) ?? []).isEmpty)

        gate.signal()
        library.finishPendingWrites()

        let reloaded = DraftLibrary(store: store)
        #expect(reloaded.drafts.map(\.text) == ["after"])
        #expect(reloaded.history.map(\.text) == ["inserted"])
    }

    @Test("AC-17: finishPendingWrites は、遅らせた下書きがあれば書き出して待つ")
    func finishPendingWritesFlushesDeferredDraft() {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)
        let library = DraftLibrary(store: store, writer: BackgroundDraftLibraryWriter(), now: { date })
        let draft = library.addDraft(text: "before")
        library.finishPendingWrites()

        library.updateDraft(id: draft?.id ?? UUID(), text: "edited")
        #expect(library.hasPendingWrite)
        library.finishPendingWrites()

        #expect(!library.hasPendingWrite)
        #expect(DraftLibrary(store: store).drafts.map(\.text) == ["edited"])
    }

    @Test("AC-18: 書き手を渡さない DraftLibrary は、その場で書き出し、書いた直後に読み直すと書いた中身がある")
    func defaultWriterWritesImmediately() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)
        let library = DraftLibrary(store: store, now: { date })

        library.addDraft(text: "now")
        library.recordUnsentText("unsent")

        #expect(try store.loadDrafts().map(\.text) == ["now"])
        #expect(try store.loadHistory().map(\.text) == ["unsent"])
    }

    @Test("AC-18: その場の書き手は、その場で job を実行し、その場で結果を返す")
    func immediateWriterRunsInPlace() {
        let writer = ImmediateDraftLibraryWriter()
        let recorder = WriteRecorder()
        var results: [DraftLibraryWriteResult] = []

        writer.write(fileName: "x.json", { recorder.record("x") }, completion: { results.append($0) })

        #expect(recorder.recorded == ["x"])
        #expect(results == [DraftLibraryWriteResult(fileName: "x.json", succeeded: true)])

        struct Failure: Error {}
        writer.write(fileName: "y.json", { throw Failure() }, completion: { results.append($0) })
        #expect(results.last == DraftLibraryWriteResult(fileName: "y.json", succeeded: false))
    }

    @Test("AC-19: 変更前の形式(version 1・整形あり・isInserted の無い古い行)のファイルは読め、書き出す形式も変わらない")
    func legacyFilesStillReadAndFormatIsUnchanged() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try directory.write("""
        {
          "drafts" : [
            {
              "id" : "11111111-1111-1111-1111-111111111111",
              "text" : "古い下書き",
              "updatedAt" : "2023-11-14T22:13:20Z"
            }
          ],
          "version" : 1
        }
        """, named: "drafts.json")
        try directory.write("""
        {
          "history" : [
            {
              "appName" : "Safari",
              "bundleIdentifier" : "com.apple.Safari",
              "id" : "22222222-2222-2222-2222-222222222222",
              "insertedAt" : "2023-11-14T22:13:20Z",
              "text" : "古い行"
            }
          ],
          "version" : 1
        }
        """, named: "history.json")
        let store = DraftLibraryStore(directory: directory.dataDirectory)

        let drafts = try store.loadDrafts()
        let history = try store.loadHistory()

        #expect(drafts.map(\.text) == ["古い下書き"])
        #expect(drafts.first?.updatedAt == date)
        #expect(history.map(\.text) == ["古い行"])
        #expect(history.first?.isInserted == true)

        let writer = BackgroundDraftLibraryWriter()
        let library = DraftLibrary(store: store, writer: writer, now: { date })
        library.recordUnsentText("新しい行")
        library.addDraft(text: "新しい下書き")
        writer.waitUntilIdle()

        let historyText = try #require(directory.read("history.json"))
        let draftsText = try #require(directory.read("drafts.json"))
        #expect(historyText.contains("\n  \"history\" : ["))
        #expect(draftsText.contains("\n  \"drafts\" : ["))
        let historyObject = try #require(JSONSerialization.jsonObject(with: Data(historyText.utf8)) as? [String: Any])
        let draftsObject = try #require(JSONSerialization.jsonObject(with: Data(draftsText.utf8)) as? [String: Any])
        #expect(Set(historyObject.keys) == ["version", "history"])
        #expect(Set(draftsObject.keys) == ["version", "drafts"])
        #expect(historyObject["version"] as? Int == 1)
        #expect(draftsObject["version"] as? Int == 1)
        let rows = try #require(historyObject["history"] as? [[String: Any]])
        #expect(Set(rows[0].keys) == ["id", "text", "insertedAt", "isInserted"])
        #expect(Set(rows[1].keys) == ["id", "text", "insertedAt", "appName", "bundleIdentifier", "isInserted"])
        #expect(rows[1]["isInserted"] as? Bool == true)
    }
}
