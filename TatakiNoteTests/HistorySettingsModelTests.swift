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

    @Test("AC-13: 履歴の件数が今の履歴の件数になり、履歴が増えると件数も増える")
    func historyCountFollowsLibrary() {
        let library = makeLibrary(historyCount: 2)
        let model = HistorySettingsModel(library: library)

        #expect(model.historyCount == 2)

        library.recordInsertion(text: "another", appName: "Notes", bundleIdentifier: nil)

        #expect(model.historyCount == 3)
    }

    @Test("AC-17: 履歴が 0 件のあいだは消せず、要求しても確認は出ない")
    func clearIsUnavailableWithoutHistory() {
        let model = HistorySettingsModel(library: makeLibrary(historyCount: 0))

        #expect(model.isClearAvailable == false)
        model.requestClear()
        #expect(model.isConfirming == false)
        #expect(model.phase == .idle)
    }

    @Test("AC-14: 消す操作をすると確認中になり、まだ履歴は消えない")
    func requestShowsConfirmationWithoutDeleting() {
        let library = makeLibrary(historyCount: 2)
        let model = HistorySettingsModel(library: library)

        #expect(model.phase == .idle)
        #expect(model.isClearAvailable)
        model.requestClear()

        #expect(model.phase == .confirming)
        #expect(model.isConfirming)
        #expect(library.history.count == 2)
    }

    @Test("AC-14: 確認中に「キャンセル」を選ぶと履歴は残り、待ちに戻る")
    func cancelKeepsHistory() {
        let library = makeLibrary(historyCount: 3)
        let model = HistorySettingsModel(library: library)

        model.requestClear()
        model.cancelClear()

        #expect(library.history.count == 3)
        #expect(model.phase == .idle)
        #expect(model.isConfirming == false)
        #expect(model.isClearAvailable)
    }

    @Test("AC-15: 確認中に「削除する」を選ぶと履歴が空になり、削除の後になって、消せなくなる")
    func confirmClearsHistory() {
        let library = makeLibrary(historyCount: 3)
        let model = HistorySettingsModel(library: library)

        model.requestClear()
        model.confirmClear()

        #expect(library.history.isEmpty)
        #expect(model.phase == .cleared)
        #expect(model.isConfirming == false)
        #expect(model.isClearAvailable == false)
        #expect(model.historyCount == 0)
        #expect(model.clearedCount == 3)
        #expect(model.clearedSequence == 1)
    }

    @Test("AC-15: 削除した後は、保存先から読み直しても履歴が空で、下書きは残る")
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

    @Test("AC-15: 確認中でないときの「削除する」では、履歴は消えず、削除の後にもならない")
    func confirmWithoutRequestDoesNothing() {
        let library = makeLibrary(historyCount: 1)
        let model = HistorySettingsModel(library: library)

        model.confirmClear()

        #expect(library.history.count == 1)
        #expect(model.phase == .idle)
        #expect(model.clearedSequence == 0)
    }

    @Test("AC-15: 削除の後にもう一度「削除する」が呼ばれても、何も起きない")
    func confirmTwiceDoesNothingSecondTime() {
        let library = makeLibrary(historyCount: 2)
        let model = HistorySettingsModel(library: library)

        model.requestClear()
        model.confirmClear()
        model.confirmClear()

        #expect(model.phase == .cleared)
        #expect(model.clearedCount == 2)
        #expect(model.clearedSequence == 1)
    }

    @Test("AC-16: 件数の減り方は n から n − max(1, ⌈n÷6⌉) を 0 まで繰り返した列で、最初の件数は含まない")
    func countdownStepsExamples() {
        #expect(HistorySettingsModel.countdownSteps(from: 0) == [])
        #expect(HistorySettingsModel.countdownSteps(from: 1) == [0])
        #expect(HistorySettingsModel.countdownSteps(from: 6) == [5, 4, 3, 2, 1, 0])
        #expect(HistorySettingsModel.countdownSteps(from: 50) == [41, 34, 28, 23, 19, 15, 12, 10, 8, 6, 5, 4, 3, 2, 1, 0])
    }

    @Test("AC-16: 件数の減り方は、どの件数でも前より小さくなり続けて 0 で終わる")
    func countdownStepsAlwaysDecreaseToZero() {
        for count in 1...DraftLibrary.historyLimit {
            let steps = HistorySettingsModel.countdownSteps(from: count)

            #expect(steps.last == 0, "\(count)")
            var previous = count
            for step in steps {
                #expect(step < previous, "\(count)")
                previous = step
            }
        }
    }

    @Test("AC-18: 確認中に待ちへ戻すと、確認は閉じて履歴は残る")
    func resetPhaseClosesConfirmationKeepingHistory() {
        let library = makeLibrary(historyCount: 2)
        let model = HistorySettingsModel(library: library)

        model.requestClear()
        model.resetPhase()

        #expect(model.phase == .idle)
        #expect(model.isConfirming == false)
        #expect(library.history.count == 2)
        #expect(model.isClearAvailable)
    }

    @Test("AC-18: 削除の後に待ちへ戻すと、押せない待ちになる(履歴は空のまま)")
    func resetPhaseAfterClearReturnsToIdle() {
        let library = makeLibrary(historyCount: 2)
        let model = HistorySettingsModel(library: library)

        model.requestClear()
        model.confirmClear()
        model.resetPhase()

        #expect(model.phase == .idle)
        #expect(model.historyCount == 0)
        #expect(model.isClearAvailable == false)
    }

    @Test("AC-18: 削除の後に新しく履歴が入ると、待ちに戻って押せる")
    func newHistoryAfterClearReturnsToIdle() {
        let library = makeLibrary(historyCount: 2)
        let model = HistorySettingsModel(library: library)

        model.requestClear()
        model.confirmClear()
        #expect(model.phase == .cleared)

        library.recordInsertion(text: "new", appName: "Notes", bundleIdentifier: nil)

        #expect(model.phase == .idle)
        #expect(model.historyCount == 1)
        #expect(model.isClearAvailable)
    }
}
