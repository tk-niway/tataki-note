import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SidebarModelRowsCacheTests {
    private static let dateText = "10月6日 14:32"

    private final class Counter {
        var value = 0
    }

    @MainActor
    private final class Fixture {
        let defaults: TemporaryDefaults
        let library: DraftLibrary
        let session: DraftSession
        let model: SidebarModel
        let listingCount = Counter()
        let dateCount = Counter()

        init() throws {
            defaults = try TemporaryDefaults()
            library = DraftLibrary(store: .inMemory)
            session = DraftSession(panel: PanelModel(), library: library, ownProcessIdentifier: 777)
            let listingCount = self.listingCount
            let dateCount = self.dateCount
            model = SidebarModel(
                settings: defaults.makeSettings(),
                library: library,
                session: session,
                dateFormatter: { _ in
                    dateCount.value += 1
                    return SidebarModelRowsCacheTests.dateText
                },
                listingCache: SidebarListingCache(makeListing: { text in
                    listingCount.value += 1
                    return SidebarListingCache.defaultListing(text)
                })
            )
        }

        @discardableResult
        func addDraft(_ text: String) throws -> UUID {
            try #require(library.addDraft(text: text)).id
        }

        @discardableResult
        func addHistory(_ text: String, appName: String? = "Safari") -> UUID {
            library.recordInsertion(text: text, appName: appName, bundleIdentifier: nil)
            return library.history[0].id
        }

        func readAllForOneRender() {
            _ = model.rows
            _ = model.selection
            _ = model.emptyMessage
            _ = model.isEmptyBySearch
        }

        func cleanUp() {
            defaults.remove()
        }
    }

    private func expectedRows(_ fixture: Fixture, tab: SidebarTab, query: String = "") -> [SidebarRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ text: String) -> Bool {
            needle.isEmpty || text.range(of: needle, options: [.caseInsensitive, .widthInsensitive]) != nil
        }
        switch tab {
        case .drafts:
            return fixture.library.drafts.filter { matches($0.text) }.map { draft in
                let firstLine = DraftListing.firstLine(of: draft.text)
                return SidebarRow(
                    id: draft.id,
                    kind: .draft,
                    title: firstLine ?? SidebarModel.untitledDraftTitle,
                    detail: Self.dateText,
                    isShownInPanel: fixture.session.document == .savedDraft(draft.id),
                    isUntitled: firstLine == nil,
                    preview: DraftListing.preview(of: draft.text)
                )
            }
        case .history:
            return fixture.library.history.filter { matches($0.text) }.map { entry in
                SidebarRow(
                    id: entry.id,
                    kind: .history,
                    title: DraftListing.firstLine(of: entry.text) ?? "",
                    detail: entry.isInserted
                        ? "\(Self.dateText) · \(entry.appName ?? SidebarModel.unknownAppName)"
                        : Self.dateText,
                    isShownInPanel: fixture.session.document == .fromHistory(entry.id),
                    preview: DraftListing.preview(of: entry.text)
                )
            }
        }
    }

    // MARK: - 一覧の中身は変わらない

    @Test("AC-13: 追加・編集・削除・検索語の変更・行の移動の後も、下書きの一覧は今の作り方と同じ")
    func draftRowsStayEqualToTheDirectBuild() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let first = try fixture.addDraft("最初\n続き1\n続き2")
        try fixture.addDraft("   ")
        try fixture.addDraft("二つ目 Apple\n詳細")
        #expect(fixture.model.rows == expectedRows(fixture, tab: .drafts))

        fixture.library.updateDraft(id: first, text: "最初を書き換えた\n別の続き")
        #expect(fixture.model.rows == expectedRows(fixture, tab: .drafts))

        fixture.model.query = "apple"
        #expect(fixture.model.rows == expectedRows(fixture, tab: .drafts, query: "apple"))
        #expect(fixture.model.rows.count == 1)

        fixture.model.query = "  該当なし  "
        #expect(fixture.model.rows == expectedRows(fixture, tab: .drafts, query: "該当なし"))
        #expect(fixture.model.rows.isEmpty)

        fixture.model.query = ""
        fixture.model.moveSelection(by: 1)
        #expect(fixture.model.rows == expectedRows(fixture, tab: .drafts))
        #expect(fixture.model.rows.filter(\.isShownInPanel).count == 1)

        fixture.library.deleteDraft(id: first)
        #expect(fixture.model.rows == expectedRows(fixture, tab: .drafts))
    }

    @Test("AC-13: 履歴の一覧も、追加・削除・検索語の変更・行の移動の後に今の作り方と同じ")
    func historyRowsStayEqualToTheDirectBuild() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.model.tab = .history
        let older = fixture.addHistory("古い\n続き", appName: "メモ")
        fixture.library.recordUnsentText("送っていない\n続き")
        fixture.addHistory("新しい Banana", appName: nil)
        #expect(fixture.model.rows == expectedRows(fixture, tab: .history))

        fixture.model.query = "banana"
        #expect(fixture.model.rows == expectedRows(fixture, tab: .history, query: "banana"))
        #expect(fixture.model.rows.count == 1)

        fixture.model.query = ""
        fixture.model.moveSelection(by: 1)
        #expect(fixture.model.rows == expectedRows(fixture, tab: .history))
        #expect(fixture.model.rows.filter(\.isShownInPanel).count == 1)

        fixture.library.deleteHistoryEntry(id: older)
        #expect(fixture.model.rows == expectedRows(fixture, tab: .history))
    }

    // MARK: - 作り直す回数

    @Test("AC-14: 同じ描画で rows・selection・emptyMessage・isEmptyBySearch を読んでも、行を作るのは1回")
    func oneRenderBuildsRowsOnce() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("一つ目\n続き")
        try fixture.addDraft("二つ目\n続き")
        try fixture.addDraft("三つ目\n続き")

        fixture.readAllForOneRender()

        #expect(fixture.dateCount.value == 3)
        #expect(fixture.listingCount.value == 3)

        fixture.readAllForOneRender()

        #expect(fixture.dateCount.value == 3)
        #expect(fixture.listingCount.value == 3)
    }

    @Test("AC-14: 検索語を1文字変えると行を作り直すが、見出し・続きは覚えから。前後の空白だけなら作り直さない")
    func queryChangeRebuildsRowsButNotListings() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("りんご\n続き")
        try fixture.addDraft("りんごジュース\n続き")
        try fixture.addDraft("みかん\n続き")
        fixture.model.query = "りん"
        #expect(fixture.model.rows.count == 2)
        let dateBefore = fixture.dateCount.value
        let listingBefore = fixture.listingCount.value

        fixture.model.query = "りんご"
        #expect(fixture.model.rows.count == 2)

        #expect(fixture.dateCount.value == dateBefore + 2)
        #expect(fixture.listingCount.value == listingBefore)

        fixture.model.query = "  りんご \n"
        #expect(fixture.model.rows.count == 2)

        #expect(fixture.dateCount.value == dateBefore + 2)
        #expect(fixture.listingCount.value == listingBefore)
    }

    @Test("AC-14: 保存した下書きを1文字編集すると、見出し・続きを作り直すのはその1件だけ")
    func editingOneDraftRemakesOnlyItsListing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let edited = try fixture.addDraft("編集する\n続き")
        try fixture.addDraft("そのまま1\n続き")
        try fixture.addDraft("そのまま2\n続き")
        _ = fixture.model.rows
        #expect(fixture.listingCount.value == 3)
        let dateBefore = fixture.dateCount.value

        fixture.library.updateDraft(id: edited, text: "編集する!\n続き")
        let rows = fixture.model.rows

        #expect(fixture.listingCount.value == 4)
        #expect(fixture.dateCount.value == dateBefore + 3)
        #expect(rows.first?.title == "編集する!")
    }

    @Test("AC-14: 下書きの側を出している間に履歴が増えても、作り直さない")
    func historyGrowthDoesNotRebuildDraftRows() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("下書き\n続き")
        _ = fixture.model.rows
        let dateBefore = fixture.dateCount.value
        let listingBefore = fixture.listingCount.value

        fixture.addHistory("履歴が増えた")
        _ = fixture.model.rows

        #expect(fixture.dateCount.value == dateBefore)
        #expect(fixture.listingCount.value == listingBefore)
    }

    @Test("AC-14: 側を切り替えたとき・行を移ったとき・履歴を消したときは作り直し、見出し・続きは覚えから")
    func tabSwitchMoveAndDeleteRebuildRows() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("下書き1\n続き")
        try fixture.addDraft("下書き2\n続き")
        let removable = fixture.addHistory("履歴1\n続き")
        fixture.addHistory("履歴2\n続き")
        _ = fixture.model.rows
        let draftListings = fixture.listingCount.value
        #expect(draftListings == 2)

        fixture.model.tab = .history
        _ = fixture.model.rows
        #expect(fixture.dateCount.value == 4)
        #expect(fixture.listingCount.value == draftListings + 2)

        fixture.model.moveSelection(by: 1)
        _ = fixture.model.rows
        #expect(fixture.dateCount.value == 6)
        #expect(fixture.listingCount.value == draftListings + 2)

        fixture.library.deleteHistoryEntry(id: removable)
        let rows = fixture.model.rows
        #expect(rows.count == 1)
        #expect(fixture.dateCount.value == 7)
        #expect(fixture.listingCount.value == draftListings + 2)
    }
}
