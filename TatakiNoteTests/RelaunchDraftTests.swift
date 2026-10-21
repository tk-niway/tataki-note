import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct RelaunchDraftTests {
    private struct Fixture {
        let directory: URL
        let store: RelaunchDraftStore
        let library: DraftLibrary
        let panel: PanelModel
        let session: DraftSession

        init(directory: URL, library: DraftLibrary? = nil) {
            self.directory = directory
            self.store = RelaunchDraftStore(directory: directory)
            let library = library ?? DraftLibrary(store: .inMemory)
            let panel = PanelModel()
            self.library = library
            self.panel = panel
            self.session = DraftSession(panel: panel, library: library, ownProcessIdentifier: 777)
        }

        var storedFile: URL {
            directory.appendingPathComponent(RelaunchDraftStore.fileName)
        }

        var fileExists: Bool {
            FileManager.default.fileExists(atPath: storedFile.path)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RelaunchDraftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func blockedDirectory(in root: URL) throws -> URL {
        let blocker = root.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        return blocker.appendingPathComponent("sub", isDirectory: true)
    }

    // MARK: - AC-15

    @Test("AC-15: 開き直しでは書きかけを履歴へ移さずファイルへ残し、次の起動で本文とモードを戻してファイルを消す")
    func relaunchKeepsScratchAndRestoresIt() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = Fixture(directory: root)
        first.panel.text = "書きかけの文章"
        first.session.toggleMode()
        let modeBefore = first.session.mode

        let outcome = first.session.prepareForTermination(reason: .relaunch, store: first.store)

        #expect(outcome == .savedForRelaunch)
        #expect(first.fileExists)
        #expect(first.library.history.isEmpty)

        let second = Fixture(directory: root)
        let draft = try #require(second.store.take())
        second.session.restore(draft)

        #expect(second.panel.text == "書きかけの文章")
        #expect(second.session.document == .scratch)
        #expect(second.session.mode == modeBefore)
        #expect(!second.fileExists)
        #expect(second.store.take() == nil)
    }

    @Test("AC-15: 開き直しで残した下書きの表示は、同じ保存先から戻る")
    func relaunchKeepsSavedDraftDocument() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DraftLibrary(store: .inMemory)
        let draft = try #require(library.addDraft(text: "下書きの本文"))
        let first = Fixture(directory: root, library: library)
        first.session.request(.draft(draft.id))

        let outcome = first.session.prepareForTermination(reason: .relaunch, store: first.store)

        #expect(outcome == .savedForRelaunch)
        let stored = try #require(first.store.take())
        #expect(stored.document == .savedDraft(draft.id))
        #expect(stored.text == "下書きの本文")
        #expect(stored.version == RelaunchDraft.currentVersion)
    }

    @Test("AC-15: 開き直しで残す本文が空白だけなら、ファイルは作らない")
    func relaunchWithBlankTextWritesNothing() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = Fixture(directory: root)
        fixture.panel.text = "  \n "

        let outcome = fixture.session.prepareForTermination(reason: .relaunch, store: fixture.store)

        #expect(outcome == .archivedToHistory)
        #expect(!fixture.fileExists)
        #expect(fixture.library.history.isEmpty)
    }

    // MARK: - AC-16

    @Test("AC-16: ふだんの終了では書きかけを履歴へ移し、残すファイルを作らない")
    func normalTerminationArchivesToHistory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = Fixture(directory: root)
        fixture.panel.text = "ふだんの終了"

        let outcome = fixture.session.prepareForTermination(reason: .normal, store: fixture.store)

        #expect(outcome == .archivedToHistory)
        #expect(fixture.library.history.count == 1)
        #expect(fixture.library.history.first?.text == "ふだんの終了")
        #expect(fixture.library.history.first?.isInserted == false)
        #expect(!fixture.fileExists)
    }

    @Test("AC-16: 開き直しでファイルを書けないときは、ふだんの終了と同じく履歴へ移す")
    func relaunchFallsBackToHistoryWhenSaveFails() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = try blockedDirectory(in: root)
        let fixture = Fixture(directory: blocked)
        fixture.panel.text = "失いたくない文章"

        let outcome = fixture.session.prepareForTermination(reason: .relaunch, store: fixture.store)

        #expect(outcome == .archivedToHistory)
        #expect(fixture.library.history.count == 1)
        #expect(fixture.library.history.first?.text == "失いたくない文章")
        #expect(!fixture.fileExists)
    }

    // MARK: - AC-17

    @Test("AC-17: 下書きは、残っていればその下書きを開いた状態に戻す")
    func restoreSavedDraftThatStillExists() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DraftLibrary(store: .inMemory)
        let draft = try #require(library.addDraft(text: "ライブラリの本文"))
        let fixture = Fixture(directory: root, library: library)

        fixture.session.restore(RelaunchDraft(
            version: RelaunchDraft.currentVersion,
            text: "残した本文",
            document: .savedDraft(draft.id),
            mode: .note
        ))

        #expect(fixture.session.document == .savedDraft(draft.id))
        #expect(fixture.panel.text == "ライブラリの本文")
        #expect(fixture.session.mode == .note)
    }

    @Test("AC-17: 下書きが消えていれば、残した本文の書きかけに戻す")
    func restoreSavedDraftThatWasDeleted() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = Fixture(directory: root)

        fixture.session.restore(RelaunchDraft(
            version: RelaunchDraft.currentVersion,
            text: "残した本文",
            document: .savedDraft(UUID()),
            mode: .insert
        ))

        #expect(fixture.session.document == .scratch)
        #expect(fixture.panel.text == "残した本文")
    }

    @Test("AC-17: 履歴は、同じ本文の項目があればその履歴を見ている状態に戻す")
    func restoreHistoryEntryWithSameText() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DraftLibrary(store: .inMemory)
        library.recordUnsentText("履歴の本文")
        let entry = try #require(library.history.first)
        let fixture = Fixture(directory: root, library: library)

        fixture.session.restore(RelaunchDraft(
            version: RelaunchDraft.currentVersion,
            text: "履歴の本文",
            document: .fromHistory(entry.id),
            mode: .insert
        ))

        #expect(fixture.session.document == .fromHistory(entry.id))
        #expect(fixture.panel.text == "履歴の本文")
    }

    @Test("AC-17: 履歴の項目が無い・本文が違うときは、残した本文の書きかけに戻す")
    func restoreHistoryEntryThatDiffers() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DraftLibrary(store: .inMemory)
        library.recordUnsentText("履歴の本文")
        let entry = try #require(library.history.first)
        let fixture = Fixture(directory: root, library: library)

        fixture.session.restore(RelaunchDraft(
            version: RelaunchDraft.currentVersion,
            text: "履歴を編集した本文",
            document: .fromHistory(entry.id),
            mode: .insert
        ))

        #expect(fixture.session.document == .scratch)
        #expect(fixture.panel.text == "履歴を編集した本文")

        let missing = Fixture(directory: root)
        missing.session.restore(RelaunchDraft(
            version: RelaunchDraft.currentVersion,
            text: "履歴が無い本文",
            document: .fromHistory(UUID()),
            mode: .insert
        ))

        #expect(missing.session.document == .scratch)
        #expect(missing.panel.text == "履歴が無い本文")
    }

    @Test("AC-17: 戻した書きかけは、そのまま終了すると履歴へ移る")
    func restoredScratchIsArchivedOnNormalTermination() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = Fixture(directory: root)
        fixture.session.restore(RelaunchDraft(
            version: RelaunchDraft.currentVersion,
            text: "戻した本文",
            document: .scratch,
            mode: .insert
        ))

        fixture.session.prepareForTermination(reason: .normal, store: fixture.store)

        #expect(fixture.library.history.map(\.text) == ["戻した本文"])
    }

    @Test("AC-17: 空白だけの書きかけは、戻しても何も変わらない")
    func restoreBlankTextDoesNothing() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = Fixture(directory: root)

        fixture.session.restore(RelaunchDraft(
            version: RelaunchDraft.currentVersion,
            text: " \n\t",
            document: .scratch,
            mode: .note
        ))

        #expect(fixture.panel.text.isEmpty)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.session.mode == .insert)
    }

    @Test("AC-17: 読めないファイルは無視して消す")
    func takeIgnoresAndRemovesBrokenFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = Fixture(directory: root)
        try Data("これは JSON ではない".utf8).write(to: fixture.storedFile)

        #expect(fixture.store.take() == nil)
        #expect(!fixture.fileExists)
    }

    @Test("AC-17: 形の版が違うファイルは無視して消す")
    func takeIgnoresAndRemovesOtherVersion() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = Fixture(directory: root)
        let other = RelaunchDraft(
            version: RelaunchDraft.currentVersion + 1,
            text: "未来の形",
            document: .scratch,
            mode: .insert
        )
        try fixture.store.save(other)
        #expect(fixture.fileExists)

        #expect(fixture.store.take() == nil)
        #expect(!fixture.fileExists)
    }

    @Test("AC-17: 保存先が無い(nil)ときは何も残さず何も返さない")
    func storeWithoutDirectoryTouchesNothing() throws {
        let store = RelaunchDraftStore(directory: nil)

        try store.save(RelaunchDraft(
            version: RelaunchDraft.currentVersion,
            text: "メモリだけ",
            document: .scratch,
            mode: .insert
        ))

        #expect(store.take() == nil)
    }
}
