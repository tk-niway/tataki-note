import AppKit
import Foundation
import SwiftUI
import Testing
@testable import TatakiNote

enum SidebarOpeningWay: CaseIterable, Sendable {
    case listDown
    case searchFieldDown
    case rowClick
    case searchFieldReturn
}

@MainActor
struct SidebarModelKeyNavigationTests {
    private static let dateText = "10月6日 14:32"

    @MainActor
    private final class Fixture {
        let defaults: TemporaryDefaults
        let settings: AppSettings
        let panel = PanelModel()
        let library: DraftLibrary
        let session: DraftSession
        let model: SidebarModel

        init() throws {
            defaults = try TemporaryDefaults()
            settings = defaults.makeSettings()
            library = DraftLibrary(store: .inMemory)
            session = DraftSession(panel: panel, library: library, ownProcessIdentifier: 777)
            model = SidebarModel(
                settings: settings,
                library: library,
                session: session,
                dateFormatter: { _ in SidebarModelKeyNavigationTests.dateText }
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

        func press(
            _ key: SidebarKey,
            _ modifiers: NSEvent.ModifierFlags = [],
            source: SidebarKeySource
        ) -> Bool {
            model.handleKey(key, source: source, modifiers: modifiers, hasMarkedText: false)
        }

        func cleanUp() {
            defaults.remove()
        }
    }

    // MARK: - 書きかけを開く操作で履歴へ移す

    @Test("AC-5: 書きかけがある状態で行を開くと、その時点で書きかけが挿入していない履歴の先頭に入り、書きかけを表す行は出ない", arguments: SidebarOpeningWay.allCases, SidebarTab.allCases)
    func openingRowArchivesScratch(way: SidebarOpeningWay, tab: SidebarTab) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("draft one")
        fixture.addHistory("history one")
        fixture.model.tab = tab
        fixture.model.query = way == .searchFieldReturn ? "one" : ""
        fixture.panel.text = "abc"
        let countBefore = fixture.session.archivedScratchCount
        for side in SidebarTab.allCases {
            fixture.model.tab = side
            #expect(!fixture.model.rows.contains { $0.title == "abc" })
        }
        fixture.model.tab = tab
        let firstRow = try #require(fixture.model.rows.first)

        switch way {
        case .listDown: #expect(fixture.press(.down, source: .list))
        case .searchFieldDown: #expect(fixture.press(.down, source: .searchField))
        case .rowClick: fixture.model.show(firstRow.id)
        case .searchFieldReturn: #expect(fixture.press(.returnKey, source: .searchField))
        }

        let archived = try #require(fixture.library.history.first)
        #expect(archived.text == "abc")
        #expect(!archived.isInserted)
        #expect(fixture.session.archivedScratchCount == countBefore + 1)
        #expect(fixture.panel.text == (tab == .drafts ? "draft one" : "history one"))
        fixture.model.query = ""
        fixture.model.tab = .drafts
        #expect(fixture.model.rows.map(\.title) == ["draft one"])
        fixture.model.tab = .history
        #expect(fixture.model.rows.filter { $0.title == "abc" }.count == 1)
    }

    // MARK: - 履歴の行の表示

    @Test("AC-17: 挿入していない履歴の行は「日時」だけ。挿入した履歴の行は「日時 · アプリ名」(名前が無ければ「不明なアプリ」)")
    func historyRowDetailDependsOnInsertion() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.addHistory("named", appName: "Safari")
        fixture.addHistory("unnamed", appName: nil)
        fixture.library.recordUnsentText("unsent")
        fixture.model.tab = .history

        func detail(of title: String) -> String? {
            fixture.model.rows.first { $0.title == title }?.detail
        }

        #expect(detail(of: "unsent") == Self.dateText)
        #expect(detail(of: "named") == "\(Self.dateText) · Safari")
        #expect(detail(of: "unnamed") == "\(Self.dateText) · 不明なアプリ")
    }

    // MARK: - 変換中・修飾キー

    @Test("AC-25: 変換中の文字がある間の ↑ ↓ ← → ↩ esc Tab ⌫ は、修飾キーや場所に関係なく渡し、何も操作しない", arguments: [SidebarKeySource.list, SidebarKeySource.searchField])
    func markedTextPassesEveryKeyThrough(source: SidebarKeySource) {
        let keys: [SidebarKey] = [.up, .down, .left, .right, .returnKey, .tab, .escape, .deleteBackward]
        let modifiersList: [NSEvent.ModifierFlags] = [[], [.shift], [.command], [.option], [.control], [.command, .shift]]
        for key in keys {
            for modifiers in modifiersList {
                let action = SidebarKeyResolver.action(for: key, source: source, modifiers: modifiers, hasMarkedText: true)
                #expect(action == .passThrough, "\(key) \(modifiers) \(source)")
            }
        }
    }

    @Test("AC-25: 修飾キー付きの ↑ ↓ ← → esc は一覧の操作をしない")
    func modifiedArrowsAndEscapePassThrough() {
        let keys: [SidebarKey] = [.up, .down, .left, .right, .escape]
        let modifiersList: [NSEvent.ModifierFlags] = [[.shift], [.command], [.option], [.control], [.command, .shift]]
        for source in [SidebarKeySource.list, .searchField] {
            for key in keys {
                for modifiers in modifiersList {
                    let action = SidebarKeyResolver.action(for: key, source: source, modifiers: modifiers, hasMarkedText: false)
                    #expect(action == .passThrough, "\(key) \(modifiers) \(source)")
                }
            }
        }
    }

    @Test("AC-25: 一覧の Tab は修飾キー無しと ⇧ だけ側を切り替える。⌘・⌥・⌃ 付きは操作しない")
    func tabWithCommandOptionControlPassesThrough() {
        func action(_ modifiers: NSEvent.ModifierFlags) -> SidebarKeyAction {
            SidebarKeyResolver.action(for: .tab, source: .list, modifiers: modifiers, hasMarkedText: false)
        }

        #expect(action([]) == .switchTab)
        #expect(action([.shift]) == .switchTab)
        #expect(action([.command]) == .passThrough)
        #expect(action([.option]) == .passThrough)
        #expect(action([.control]) == .passThrough)
        #expect(action([.command, .shift]) == .passThrough)
        #expect(action([.capsLock]) == .switchTab)
    }

    @Test("AC-25: 検索欄の ← → Tab ⌫ は文字の操作のまま渡す")
    func searchFieldTextKeysPassThrough() {
        for key in [SidebarKey.left, .right, .tab, .deleteBackward] {
            for modifiers: NSEvent.ModifierFlags in [[], [.shift], [.command]] {
                let action = SidebarKeyResolver.action(for: key, source: .searchField, modifiers: modifiers, hasMarkedText: false)
                #expect(action == .passThrough, "\(key) \(modifiers)")
            }
        }
    }

    // MARK: - 検索語と読み込み

    @Test("AC-27: 検索欄の文字を変えてもパネルの文章は変わらず、当たった先頭の行がハイライトされる")
    func queryChangeDoesNotLoadAndHighlightsFirstMatch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let banana = try fixture.addDraft("banana")
        try fixture.addDraft("apple")
        let bandana = try fixture.addDraft("bandana")
        fixture.panel.text = "typed"

        fixture.model.query = "ban"

        #expect(fixture.panel.text == "typed")
        #expect(fixture.session.document == .scratch)
        #expect(fixture.model.rows.map(\.id) == [bandana, banana])
        #expect(fixture.model.selection == bandana)
        #expect(fixture.library.history.isEmpty)
    }

    @Test("AC-27: パネルに出ている行が当たっていれば、先頭でなくてもその行がハイライトされる")
    func queryHighlightsShownRowWhenMatched() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let first = try fixture.addDraft("ban one")
        let second = try fixture.addDraft("ban two")
        fixture.model.show(first)
        #expect(fixture.model.rows.map(\.id) == [second, first])

        fixture.model.query = "ban"

        #expect(fixture.model.selection == first)
        #expect(fixture.panel.text == "ban one")

        fixture.model.query = "two"

        #expect(fixture.model.selection == second)
        #expect(fixture.panel.text == "ban one")
    }

    @Test("AC-27: 検索語が空白だけなら、パネルに出ている行が無い限りハイライトは無い")
    func blankQueryHasNoHighlight() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("one")

        fixture.model.query = "   "

        #expect(fixture.model.selection == nil)
    }

    // MARK: - ⌘⌫

    @Test("AC-28: ハイライトが無いときの一覧の ⌘⌫ は何も消さず、キーは飲み込む")
    func commandDeleteWithoutHighlightDeletesNothing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let top = try fixture.addDraft("top")
        fixture.addHistory("entry")
        #expect(fixture.model.selection == nil)

        #expect(fixture.press(.deleteBackward, [.command], source: .list))
        fixture.model.tab = .history
        #expect(fixture.press(.deleteBackward, [.command], source: .list))

        #expect(fixture.library.drafts.map(\.id) == [top])
        #expect(fixture.library.history.count == 1)
    }

    @Test("AC-28: ハイライトしている下書きがパネルに出ていれば、⌘⌫ で消した後も本文は書きかけとしてパネルに残り、履歴には入らない")
    func commandDeleteShownDraftKeepsTextAsScratch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let other = try fixture.addDraft("other")
        try fixture.addDraft("shown")
        #expect(fixture.press(.down, source: .list))
        #expect(fixture.panel.text == "shown")

        #expect(fixture.press(.deleteBackward, [.command], source: .list))

        #expect(fixture.library.drafts.map(\.id) == [other])
        #expect(fixture.panel.text == "shown")
        #expect(fixture.session.document == .scratch)
        #expect(fixture.model.selection == nil)
        #expect(fixture.library.history.isEmpty)
    }

    @Test("AC-28: ハイライトしている履歴がパネルに出ていれば、⌘⌫ で消した後も本文はパネルに残り、ハイライトは無くなる")
    func commandDeleteShownHistoryKeepsText() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let older = fixture.addHistory("older")
        fixture.addHistory("newer")
        fixture.model.tab = .history
        #expect(fixture.press(.down, source: .list))
        #expect(fixture.press(.down, source: .list))
        #expect(fixture.panel.text == "older")
        #expect(fixture.model.selection == older)

        #expect(fixture.press(.deleteBackward, [.command], source: .list))

        #expect(fixture.library.history.map(\.text) == ["newer"])
        #expect(fixture.panel.text == "older")
        #expect(fixture.model.selection == nil)
    }

    @Test("AC-28: 検索語があり、ハイライトが表示していない先頭の行なら、⌘⌫ でその行が消え、パネルの文章は変わらない")
    func commandDeleteHighlightedFirstMatchKeepsPanelText() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let apple = try fixture.addDraft("apple")
        let banana = try fixture.addDraft("banana")
        fixture.model.show(apple)
        fixture.model.query = "ban"
        #expect(fixture.model.selection == banana)

        #expect(fixture.press(.deleteBackward, [.command], source: .list))

        #expect(fixture.library.drafts.map(\.id) == [apple])
        #expect(fixture.panel.text == "apple")
        #expect(fixture.session.document == .savedDraft(apple))
    }

    @Test("AC-28: 検索欄の ⌘⌫ は文字の削除として渡し、行を消さない")
    func searchFieldCommandDeletePassesThrough() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("one")
        fixture.model.query = "one"

        #expect(!fixture.press(.deleteBackward, [.command], source: .searchField))

        #expect(fixture.library.drafts.count == 1)
    }

    // MARK: - ↑ ↓ ↩ → Tab ← esc と行のクリック

    @Test("AC-18: ↑ ↓ は行の中身をパネルに出すだけで、フォーカスの要求は出さない。ハイライトが無いときはどちらでも先頭の行")
    func arrowKeysLoadWithoutMovingFocus() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let older = try fixture.addDraft("older")
        let newer = try fixture.addDraft("newer")
        let bodyBefore = fixture.model.bodyFocusRequest
        let listBefore = fixture.model.listFocusRequest
        let searchBefore = fixture.model.searchFocusRequest

        #expect(fixture.press(.up, source: .list))
        #expect(fixture.session.document == .savedDraft(newer))
        #expect(fixture.press(.down, source: .searchField))
        #expect(fixture.session.document == .savedDraft(older))
        #expect(fixture.press(.down, source: .list))
        #expect(fixture.session.document == .savedDraft(older))

        #expect(fixture.model.bodyFocusRequest == bodyBefore)
        #expect(fixture.model.listFocusRequest == listBefore)
        #expect(fixture.model.searchFocusRequest == searchBefore)
    }

    @Test("AC-18: ハイライトが無いとき ↓ も先頭の行を出す。行が無ければ何も起きない")
    func downWithoutHighlightLoadsFirstRow() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.press(.down, source: .list))
        #expect(fixture.session.document == .scratch)

        try fixture.addDraft("oldest")
        let top = try fixture.addDraft("top")
        #expect(fixture.model.selection == nil)
        #expect(fixture.press(.down, source: .list))
        #expect(fixture.session.document == .savedDraft(top))
        #expect(fixture.panel.text == "top")

        fixture.session.request(.newScratch)
        #expect(fixture.model.selection == nil)
        #expect(fixture.press(.up, source: .list))
        #expect(fixture.session.document == .savedDraft(top))
    }

    @Test("AC-19: 一覧の → と ↩、検索欄の ↩ は、パネルに出ていない行を出してから本文へフォーカスを移す")
    func confirmLoadsHighlightedRowAndReturnsToBody() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let first = try fixture.addDraft("first")
        let second = try fixture.addDraft("second")
        fixture.model.query = "first"
        let bodyBefore = fixture.model.bodyFocusRequest

        #expect(fixture.press(.returnKey, source: .searchField))
        #expect(fixture.session.document == .savedDraft(first))
        #expect(fixture.model.bodyFocusRequest == bodyBefore + 1)

        fixture.model.query = ""
        fixture.model.show(second)
        fixture.model.query = "first"
        #expect(fixture.model.selection == first)

        #expect(fixture.press(.right, source: .list))
        #expect(fixture.session.document == .savedDraft(first))
        #expect(fixture.model.bodyFocusRequest == bodyBefore + 2)
    }

    @Test("AC-19: ハイライトが無いときの ↩ と → は、パネルの文章を変えずに本文へフォーカスを移す")
    func confirmWithoutHighlightKeepsPanelText() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("saved")
        fixture.panel.text = "typed"
        let bodyBefore = fixture.model.bodyFocusRequest

        #expect(fixture.press(.returnKey, source: .searchField))
        #expect(fixture.press(.returnKey, source: .list))
        #expect(fixture.press(.right, source: .list))

        #expect(fixture.panel.text == "typed")
        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.history.isEmpty)
        #expect(fixture.model.bodyFocusRequest == bodyBefore + 3)
    }

    @Test("AC-20: 一覧の Tab で下書きと履歴が切り替わり、パネルの文章は変わらない。← は飲み込んで何もしない")
    func tabSwitchesSideAndLeftDoesNothing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("draft")
        fixture.panel.text = "typed"
        let bodyBefore = fixture.model.bodyFocusRequest

        #expect(fixture.press(.tab, source: .list))
        #expect(fixture.model.tab == .history)
        #expect(fixture.press(.tab, [.shift], source: .list))
        #expect(fixture.model.tab == .drafts)
        #expect(fixture.press(.left, source: .list))

        #expect(fixture.model.tab == .drafts)
        #expect(fixture.panel.text == "typed")
        #expect(fixture.library.history.isEmpty)
        #expect(fixture.model.bodyFocusRequest == bodyBefore)
    }

    @Test("AC-20: ⇧Tab のバックタブの文字も Tab として扱い、矢印キーは左右のキーになる")
    func keyEquivalentConversion() {
        #expect(SidebarKeyResolver.key(for: .tab) == .tab)
        #expect(SidebarKeyResolver.key(for: KeyEquivalent("\u{19}")) == .tab)
        #expect(SidebarKeyResolver.key(for: .leftArrow) == .left)
        #expect(SidebarKeyResolver.key(for: .rightArrow) == .right)
        #expect(SidebarKeyResolver.key(for: .upArrow) == .up)
        #expect(SidebarKeyResolver.key(for: .downArrow) == .down)
        #expect(SidebarKeyResolver.key(for: .return) == .returnKey)
        #expect(SidebarKeyResolver.key(for: .escape) == .escape)
        #expect(SidebarKeyResolver.key(for: .delete) == .deleteBackward)
        #expect(SidebarKeyResolver.key(for: KeyEquivalent("a")) == nil)
    }

    @Test("AC-21: 一覧の esc はパネルを閉じる処理を呼び、検索欄の esc は本文へ戻る")
    func escapeClosesFromListAndReturnsToBodyFromSearchField() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var closeCount = 0
        fixture.model.closePanel = { closeCount += 1 }
        let bodyBefore = fixture.model.bodyFocusRequest

        #expect(fixture.press(.escape, source: .list))
        #expect(closeCount == 1)
        #expect(fixture.model.bodyFocusRequest == bodyBefore)

        #expect(fixture.press(.escape, source: .searchField))
        #expect(closeCount == 1)
        #expect(fixture.model.bodyFocusRequest == bodyBefore + 1)
    }

    @Test("AC-22: 一覧へのフォーカスの要求は、当てたと記録するまで保留され、開き直しで捨てられる")
    func listFocusRequestIsPendingUntilHandledOrDiscarded() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(!fixture.model.hasPendingListFocus)

        fixture.model.focusList()
        #expect(fixture.model.hasPendingListFocus)
        fixture.model.markListFocusHandled()
        #expect(!fixture.model.hasPendingListFocus)

        fixture.model.focusList()
        fixture.model.openForSearch()
        #expect(fixture.model.hasPendingListFocus)
        #expect(fixture.model.hasPendingSearchFocus)
        fixture.model.discardPendingFocusRequests()
        #expect(!fixture.model.hasPendingListFocus)
        #expect(!fixture.model.hasPendingSearchFocus)
    }

    @Test("AC-24: 行のクリックは中身をパネルに出して一覧にフォーカスを置き、文章を変える前に beforeUserAction を呼ぶ")
    func rowClickLoadsAndFocusesList() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let draft = try fixture.addDraft("draft")
        var textsAtCall: [String] = []
        fixture.model.beforeUserAction = { textsAtCall.append(fixture.panel.text) }
        let bodyBefore = fixture.model.bodyFocusRequest
        let listBefore = fixture.model.listFocusRequest

        fixture.model.show(draft)

        #expect(textsAtCall == [""])
        #expect(fixture.panel.text == "draft")
        #expect(fixture.session.document == .savedDraft(draft))
        #expect(fixture.model.listFocusRequest == listBefore + 1)
        #expect(fixture.model.bodyFocusRequest == bodyBefore)
    }
}
