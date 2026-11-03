import Testing
@testable import TatakiNote

@MainActor
struct PanelModelFinishTargetLookupTests {
    private let editor = MonitorFixture.editor
    private let browser = MonitorFixture.browser

    private struct Snapshot: Equatable {
        let isPresented: Bool
        let target: InsertionTarget?
        let isTargetPending: Bool
        let pendingLookupApp: InsertionTarget?

        @MainActor
        init(_ model: PanelModel) {
            isPresented = model.isPresented
            target = model.target
            isTargetPending = model.isTargetPending
            pendingLookupApp = model.pendingLookupApp
        }
    }

    private func closedModel() -> PanelModel {
        PanelModel()
    }

    private func pendingModel() -> PanelModel {
        let model = PanelModel()
        model.present(target: nil, pendingLookupApp: editor)
        return model
    }

    private func presentedModel(target: InsertionTarget?) -> PanelModel {
        let model = PanelModel()
        model.present(target: target)
        return model
    }

    @Test("AC-7: finishTargetLookup と updateTarget は、閉じている・待ち・同じ挿入先・別の挿入先・nil のどれから呼んでも同じ状態になる")
    func finishTargetLookupMatchesUpdateTarget() {
        let cases: [(name: String, make: () -> PanelModel, argument: InsertionTarget?)] = [
            ("閉じている・挿入先あり", closedModel, editor),
            ("閉じている・nil", closedModel, nil),
            ("待ち・挿入先あり", pendingModel, editor),
            ("待ち・別の挿入先", pendingModel, browser),
            ("待ち・nil", pendingModel, nil),
            ("同じ挿入先", { presentedModel(target: editor) }, editor),
            ("別の挿入先", { presentedModel(target: editor) }, browser),
            ("挿入先から nil", { presentedModel(target: editor) }, nil),
            ("nil から挿入先", { presentedModel(target: nil) }, editor),
        ]
        for item in cases {
            let finished = item.make()
            let updated = item.make()
            finished.finishTargetLookup(item.argument)
            updated.updateTarget(item.argument)
            #expect(Snapshot(finished) == Snapshot(updated), Comment(rawValue: item.name))
        }
    }

    @Test("AC-7: 待ちから呼ぶと、挿入先が決まり、待ちの印と調べているアプリが消える。閉じているときは何も変わらない")
    func finishTargetLookupResolvesPendingAndIgnoresClosed() {
        let pending = pendingModel()
        pending.finishTargetLookup(browser)
        #expect(pending.target == browser)
        #expect(!pending.isTargetPending)
        #expect(pending.pendingLookupApp == nil)

        let closed = closedModel()
        let before = Snapshot(closed)
        closed.finishTargetLookup(editor)
        #expect(Snapshot(closed) == before)
        #expect(closed.target == nil)
    }
}
