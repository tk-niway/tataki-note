import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct HistorySettingsModelTests {
    private func makeLibrary(historyCount: Int, store: DraftLibraryStore? = nil) -> DraftLibrary {
        let library = DraftLibrary(store: store ?? .inMemory)
        for index in 0..<historyCount {
            library.recordInsertion(text: "entry \(index)", appName: "Notes", bundleIdentifier: nil)
        }
        return library
    }

    @Test("AC-41: 履歴が 0 件のあいだは消せず、要求しても確認は出ない")
    func clearIsUnavailableWithoutHistory() {
        let model = HistorySettingsModel(library: makeLibrary(historyCount: 0))

        #expect(model.isClearAvailable == false)
        model.requestClear()
        #expect(model.isConfirming == false)
    }

    @Test("AC-41: 消す操作をすると確認が出て、まだ履歴は消えない")
    func requestShowsConfirmationWithoutDeleting() {
        let library = makeLibrary(historyCount: 2)
        let model = HistorySettingsModel(library: library)

        #expect(model.isClearAvailable)
        model.requestClear()

        #expect(model.isConfirming)
        #expect(library.history.count == 2)
    }

    @Test("AC-41: 確認で「すべて削除」を選ぶと履歴が空になり、確認が閉じて、消せなくなる")
    func confirmClearsHistory() {
        let library = makeLibrary(historyCount: 3)
        let model = HistorySettingsModel(library: library)

        model.requestClear()
        model.confirmClear()

        #expect(library.history.isEmpty)
        #expect(model.isConfirming == false)
        #expect(model.isClearAvailable == false)
    }

    @Test("AC-41: 確認で「キャンセル」を選ぶと履歴は残り、確認が閉じる")
    func cancelKeepsHistory() {
        let library = makeLibrary(historyCount: 3)
        let model = HistorySettingsModel(library: library)

        model.requestClear()
        model.cancelClear()

        #expect(library.history.count == 3)
        #expect(model.isConfirming == false)
        #expect(model.isClearAvailable)
    }

    @Test("AC-41: 確認を出していないときの「すべて削除」では、履歴は消えない")
    func confirmWithoutRequestDoesNothing() {
        let library = makeLibrary(historyCount: 1)
        let model = HistorySettingsModel(library: library)

        model.confirmClear()

        #expect(library.history.count == 1)
    }

    @Test("AC-41: 削除した後は、保存先から読み直しても履歴が空で、下書きは残る")
    func clearingPersistsAndKeepsDrafts() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)
        let library = makeLibrary(historyCount: 2, store: store)
        let draft = try #require(library.addDraft(text: "keep me"))
        let model = HistorySettingsModel(library: library)

        model.requestClear()
        model.confirmClear()

        let reloaded = DraftLibrary(store: store)
        #expect(reloaded.history.isEmpty)
        #expect(reloaded.drafts.map(\.id) == [draft.id])
    }
}
