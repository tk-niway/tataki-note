import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SidebarModelTests {
    @MainActor
    private final class Fixture {
        let defaults: TemporaryDefaults
        let settings: AppSettings
        let panel = PanelModel()
        let library: DraftLibrary
        let session: DraftSession
        let model: SidebarModel

        convenience init() throws {
            try self.init(store: .inMemory)
        }

        init(store: DraftLibraryStore) throws {
            defaults = try TemporaryDefaults()
            settings = defaults.makeSettings()
            library = DraftLibrary(store: store)
            session = DraftSession(panel: panel, library: library, ownProcessIdentifier: 777)
            model = SidebarModel(settings: settings, library: library, session: session, dateFormatter: { _ in "10月6日 14:32" })
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

        func press(_ key: SidebarKey, _ modifiers: NSEvent.ModifierFlags = [], hasMarkedText: Bool = false) -> Bool {
            model.handleKey(key, modifiers: modifiers, hasMarkedText: hasMarkedText)
        }

        func cleanUp() {
            defaults.remove()
        }
    }

    // MARK: - 開閉と表示中の側の保存

    @Test("AC-22: 初めてはサイドバーが閉じていて「下書き」を表示する。読んだだけでは保存しない")
    func sidebarDefaultsToClosedDrafts() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        #expect(!fixture.model.isOpen)
        #expect(fixture.model.tab == .drafts)
        #expect(fixture.defaults.defaults.object(forKey: "sidebarIsOpen") == nil)
        #expect(fixture.defaults.defaults.object(forKey: "sidebarTab") == nil)
    }

    @Test("AC-22: サイドバーの開閉と表示中の側は保存され、設定を作り直しても同じになる")
    func openStateAndTabSurviveRecreation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.model.setOpen(true)
        fixture.model.tab = .history

        #expect(fixture.defaults.defaults.bool(forKey: "sidebarIsOpen"))
        #expect(fixture.defaults.defaults.string(forKey: "sidebarTab") == "history")
        let reloaded = SidebarModel(
            settings: fixture.defaults.makeSettings(),
            library: fixture.library,
            session: fixture.session
        )
        #expect(reloaded.isOpen)
        #expect(reloaded.tab == .history)

        reloaded.setOpen(false)
        reloaded.tab = .drafts
        let again = SidebarModel(settings: fixture.defaults.makeSettings(), library: fixture.library, session: fixture.session)
        #expect(!again.isOpen)
        #expect(again.tab == .drafts)
    }

    @Test("AC-22: 読めない値が保存されていたら、閉じていて「下書き」に戻る")
    func invalidStoredValuesFallBackToDefaults() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.defaults.defaults.set("unknown", forKey: "sidebarTab")
        fixture.defaults.defaults.set("yes", forKey: "sidebarIsOpen")

        let settings = fixture.defaults.makeSettings()

        #expect(!settings.isSidebarOpen)
        #expect(settings.sidebarTab == .drafts)
    }

    @Test("AC-22: ⌘K 相当の openForSearch はサイドバーを開き(保存される)、検索欄へのフォーカスを求める")
    func openForSearchOpensAndRequestsFocus() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let before = fixture.model.searchFocusRequest

        fixture.model.openForSearch()

        #expect(fixture.model.isOpen)
        #expect(fixture.model.searchFocusRequest == before + 1)
        #expect(fixture.defaults.makeSettings().isSidebarOpen)

        fixture.model.openForSearch()
        #expect(fixture.model.searchFocusRequest == before + 2)
    }

    @Test("AC-22: 検索欄へのフォーカスの要求は、当てたと記録するまで保留され、もう一度 openForSearch すると保留に戻る")
    func pendingSearchFocusIsTrackedUntilHandled() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(!fixture.model.hasPendingSearchFocus)

        fixture.model.openForSearch()
        #expect(fixture.model.hasPendingSearchFocus)

        fixture.model.markSearchFocusHandled()
        #expect(!fixture.model.hasPendingSearchFocus)

        fixture.model.openForSearch()
        #expect(fixture.model.hasPendingSearchFocus)
    }

    // MARK: - 絞り込み

    @Test("AC-23: 検索欄の文字は表示中の側を本文全体から絞り込む。2行目以降の語でも当たり、大文字・小文字と全角・半角を区別しない")
    func queryFiltersWholeText() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let multiline = try fixture.addDraft("first line\nsecond keyword")
        let apple = try fixture.addDraft("Apple")
        let fullWidth = try fixture.addDraft("ＡＢＣ")
        let halfKana = try fixture.addDraft("ｶﾀｶﾅ")

        fixture.model.query = "keyword"
        #expect(fixture.model.rows.map(\.id) == [multiline])

        fixture.model.query = "APPLE"
        #expect(fixture.model.rows.map(\.id) == [apple])

        fixture.model.query = "abc"
        #expect(fixture.model.rows.map(\.id) == [fullWidth])

        fixture.model.query = "カタカナ"
        #expect(fixture.model.rows.map(\.id) == [halfKana])

        fixture.model.query = "  Apple  "
        #expect(fixture.model.rows.map(\.id) == [apple])

        fixture.model.query = "   "
        #expect(fixture.model.rows.count == 4)
    }

    @Test("AC-23: 濁点の有無は区別する(「は」で「ば」は当たらない)")
    func queryDistinguishesDakuten() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let voiced = try fixture.addDraft("ばなな")
        let plain = try fixture.addDraft("はなび")

        fixture.model.query = "は"
        #expect(fixture.model.rows.map(\.id) == [plain])

        fixture.model.query = "ば"
        #expect(fixture.model.rows.map(\.id) == [voiced])
    }

    @Test("AC-23: 絞り込みは表示中の側だけにかかり、履歴の側は履歴の本文を絞る")
    func queryAppliesToVisibleSideOnly() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("shared draft")
        let entry = fixture.addHistory("shared history\nsecond line")
        fixture.addHistory("other")

        fixture.model.tab = .history
        fixture.model.query = "second"

        #expect(fixture.model.rows.map(\.id) == [entry])
        fixture.model.tab = .drafts
        #expect(fixture.model.rows.count == 0)
    }

    // MARK: - 選択とキー

    @Test("AC-23: ↑ ↓ で選択が動いて端で止まる。先頭の行が最初の選択")
    func arrowKeysMoveSelectionAndStopAtEnds() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let first = try fixture.addDraft("one")
        let second = try fixture.addDraft("two")
        let third = try fixture.addDraft("three")
        #expect(fixture.model.rows.map(\.id) == [third, second, first])
        #expect(fixture.model.selection == third)

        #expect(fixture.press(.up))
        #expect(fixture.model.selection == third)
        #expect(fixture.press(.down))
        #expect(fixture.model.selection == second)
        #expect(fixture.press(.down))
        #expect(fixture.model.selection == first)
        #expect(fixture.press(.down))
        #expect(fixture.model.selection == first)
        #expect(fixture.press(.up))
        #expect(fixture.model.selection == second)
    }

    @Test("AC-23: ↩ で選んだものを呼び出して本文へフォーカスを戻す。履歴の側では履歴を読み込む")
    func returnActivatesSelection() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let draft = try fixture.addDraft("saved text")
        let focusBefore = fixture.model.bodyFocusRequest

        #expect(fixture.press(.returnKey))

        #expect(fixture.panel.text == "saved text")
        #expect(fixture.session.document == .savedDraft(draft))
        #expect(fixture.model.bodyFocusRequest == focusBefore + 1)

        let entry = fixture.addHistory("from history")
        fixture.model.tab = .history
        fixture.session.request(.newScratch)
        #expect(fixture.press(.returnKey))

        #expect(fixture.panel.text == "from history")
        #expect(fixture.session.document == .fromHistory(entry))
    }

    @Test("AC-23: 修飾キー付きの ↩(確定キー ⇧⌘↩・確定+送信キー ⌘↩ など)では呼び出さず、飲み込む")
    func modifiedReturnDoesNotActivate() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("saved text")
        let focusBefore = fixture.model.bodyFocusRequest

        for modifiers: NSEvent.ModifierFlags in [[.command, .shift], [.command], [.shift], [.option], [.control]] {
            #expect(fixture.press(.returnKey, modifiers))
        }

        #expect(fixture.panel.text.isEmpty)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.model.bodyFocusRequest == focusBefore)
        #expect(fixture.model.query.isEmpty)
    }

    @Test("AC-23: 文字を変えると選択は先頭の行に戻る")
    func queryChangeResetsSelectionToFirstRow() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("aa")
        let middle = try fixture.addDraft("ab")
        let top = try fixture.addDraft("ac")
        fixture.model.moveSelection(by: 1)
        #expect(fixture.model.selection == middle)

        fixture.model.query = "a"

        #expect(fixture.model.rows.contains { $0.id == middle })
        #expect(fixture.model.selection == top)
    }

    @Test("AC-23: 表示中の側を変えても選択は新しい側の先頭に置き直される")
    func tabChangeResetsSelection() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("draft")
        let entry = fixture.addHistory("older")
        let newest = fixture.addHistory("newer")
        fixture.model.tab = .history
        fixture.model.moveSelection(by: 1)
        #expect(fixture.model.selection == entry)

        fixture.model.tab = .drafts
        fixture.model.tab = .history

        #expect(fixture.model.selection == newest)
    }

    @Test("AC-23: esc は本文へ戻る。修飾キー付きの ↑ ↓ esc は検索欄に渡す")
    func escapeReturnsToBodyAndModifiedKeysPassThrough() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("a")
        let focusBefore = fixture.model.bodyFocusRequest

        #expect(fixture.press(.escape))
        #expect(fixture.model.bodyFocusRequest == focusBefore + 1)
        #expect(!fixture.press(.up, [.command]))
        #expect(!fixture.press(.down, [.option]))
        #expect(!fixture.press(.escape, [.shift]))
        #expect(fixture.model.bodyFocusRequest == focusBefore + 1)
    }

    @Test("AC-23: Caps Lock・fn などの印は修飾キーに数えない")
    func irrelevantModifierFlagsAreIgnored() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("saved text")

        #expect(fixture.press(.returnKey, [.capsLock]))

        #expect(fixture.panel.text == "saved text")
    }

    @Test("AC-23: 検索欄に未確定の文字があるときの ↑ ↓ ↩ esc ⌘⌫ は入力メソッドに渡り、選択・呼び出し・本文へ戻る、のどれも起こさない")
    func markedTextPassesEveryKeyThrough() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("one")
        let top = try fixture.addDraft("two")
        let focusBefore = fixture.model.bodyFocusRequest

        #expect(!fixture.press(.up, hasMarkedText: true))
        #expect(!fixture.press(.down, hasMarkedText: true))
        #expect(!fixture.press(.returnKey, hasMarkedText: true))
        #expect(!fixture.press(.escape, hasMarkedText: true))
        #expect(!fixture.press(.deleteBackward, [.command], hasMarkedText: true))

        #expect(fixture.model.selection == top)
        #expect(fixture.panel.text.isEmpty)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.model.bodyFocusRequest == focusBefore)
        #expect(fixture.library.drafts.count == 2)
    }

    // MARK: - 行の表示

    @Test("AC-24: 下書きの行は1行目だけ(先頭の空行は飛ばす)。本文が空・空白だけなら「(空の下書き)」")
    func draftRowsShowFirstLine() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("\n\n  タイトル  \n二行目")
        try fixture.addDraft(" \n\t")
        let rows = fixture.model.rows

        #expect(rows.count == 2)
        #expect(rows[0].title == "(空の下書き)")
        #expect(rows[1].title == "タイトル")
        #expect(rows.allSatisfy { $0.kind == .draft && $0.detail == nil })
    }

    @Test("AC-24: 履歴の行は「挿入日時 · 挿入先のアプリ名」と1行目を出す。アプリ名が無ければ「不明なアプリ」")
    func historyRowsShowDateAppAndFirstLine() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.addHistory("\n本文の一行目\n二行目", appName: "チャットノート")
        fixture.addHistory("no app", appName: nil)
        fixture.model.tab = .history
        let rows = fixture.model.rows

        #expect(rows.count == 2)
        #expect(rows[0].title == "no app")
        #expect(rows[0].detail == "10月6日 14:32 · 不明なアプリ")
        #expect(rows[1].title == "本文の一行目")
        #expect(rows[1].detail == "10月6日 14:32 · チャットノート")
        #expect(rows.allSatisfy { $0.kind == .history && !$0.isShownInPanel })
    }

    @Test("AC-24: パネルに出している下書きの行は分かる。切り替えると印も移る")
    func rowMarksDraftShownInPanel() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let first = try fixture.addDraft("first")
        let second = try fixture.addDraft("second")
        #expect(fixture.model.rows.allSatisfy { !$0.isShownInPanel })

        fixture.session.request(.draft(first))
        #expect(fixture.model.rows.filter(\.isShownInPanel).map(\.id) == [first])

        fixture.session.request(.draft(second))
        #expect(fixture.model.rows.filter(\.isShownInPanel).map(\.id) == [second])
    }

    @Test("AC-24: 既定の日時の文字は月日と時分を含む")
    func defaultDateTextContainsMonthDayAndTime() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let text = SidebarModel.defaultDateText(date)

        #expect(!text.isEmpty)
        #expect(text.contains(":") || text.contains("時"))
    }

    // MARK: - 空の説明

    @Test("AC-25: 下書きが 0 件なら「⌘S で今の文章を取っておけます」、履歴が 0 件なら「挿入した文章がここに残ります(最新 50 件)」")
    func emptyMessagesPerSide() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        #expect(fixture.model.emptyMessage == "⌘S で今の文章を取っておけます")
        fixture.model.tab = .history
        #expect(fixture.model.emptyMessage == "挿入した文章がここに残ります(最新 50 件)")

        fixture.addHistory("x")
        #expect(fixture.model.emptyMessage == nil)
    }

    @Test("AC-25: 検索で何も当たらないときは、そのことを出す")
    func emptyMessageForNoSearchResults() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("hello")

        fixture.model.query = " nothing "

        #expect(fixture.model.rows.isEmpty)
        #expect(fixture.model.emptyMessage == "「nothing」に一致するものはありません")

        fixture.model.query = "hello"
        #expect(fixture.model.emptyMessage == nil)
    }

    // MARK: - 削除

    @Test("AC-1: 下書きの削除は確認なしですぐ消え、右クリックした行に働き、選択は動かさない。保存先から読み直しても無い。選んでいた行を消すと選択は先頭の行になる")
    func draftDeletionIsImmediate() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let fixture = try Fixture(store: DraftLibraryStore(directory: directory.dataDirectory))
        defer { fixture.cleanUp() }
        let bottom = try fixture.addDraft("bottom")
        let middle = try fixture.addDraft("middle")
        let top = try fixture.addDraft("top")
        #expect(fixture.model.selection == top)

        fixture.model.requestDelete(bottom)

        #expect(fixture.library.drafts.map(\.id) == [top, middle])
        #expect(fixture.model.selection == top)
        let reloaded = DraftLibrary(store: DraftLibraryStore(directory: directory.dataDirectory))
        #expect(reloaded.drafts.map(\.id) == [top, middle])

        fixture.model.select(middle)
        fixture.model.requestDelete(middle)

        #expect(fixture.library.drafts.map(\.id) == [top])
        #expect(fixture.model.selection == top)
    }

    @Test("AC-1: 一覧での ⌘⌫ は選んでいる行をすぐ消し、保存先から読み直しても無い")
    func commandDeleteDeletesSelection() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let fixture = try Fixture(store: DraftLibraryStore(directory: directory.dataDirectory))
        defer { fixture.cleanUp() }
        let bottom = try fixture.addDraft("bottom")
        let top = try fixture.addDraft("top")
        #expect(fixture.model.selection == top)

        #expect(fixture.press(.deleteBackward, [.command]))

        #expect(fixture.library.drafts.map(\.id) == [bottom])
        #expect(fixture.model.selection == bottom)
        let reloaded = DraftLibrary(store: DraftLibraryStore(directory: directory.dataDirectory))
        #expect(reloaded.drafts.map(\.id) == [bottom])
    }

    @Test("AC-26: 修飾キー無しの ⌫ は検索欄の文字の削除のままで、下書きは消えない")
    func plainDeleteBackwardPassesThrough() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addDraft("draft")

        #expect(!fixture.press(.deleteBackward))
        #expect(!fixture.press(.deleteBackward, [.option]))

        #expect(fixture.library.drafts.count == 1)
    }

    @Test("AC-26: 履歴の削除は確認なしですぐ消える")
    func historyDeletionIsImmediate() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let older = fixture.addHistory("older")
        let newer = fixture.addHistory("newer")
        fixture.model.tab = .history

        fixture.model.requestDelete(older)

        #expect(fixture.library.history.map(\.id) == [newer])
        #expect(fixture.model.selection == newer)
    }

    @Test("AC-5: 保存していない文章の切り替えの確認中は、削除の項目は押せず、requestDelete も ⌘⌫ も受けない(下書きも履歴も消えない)")
    func deletionIsUnavailableWhileSwitchConfirmationIsShown() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let draft = try fixture.addDraft("saved")
        let entry = fixture.addHistory("history")
        fixture.panel.text = "unsaved"
        #expect(fixture.model.isDeleteAvailable)

        fixture.session.request(.draft(draft))
        #expect(fixture.session.pendingSwitch == .draft(draft))
        #expect(!fixture.model.isDeleteAvailable)

        fixture.model.requestDelete(draft)
        #expect(fixture.library.drafts.map(\.id) == [draft])
        #expect(fixture.press(.deleteBackward, [.command]))
        #expect(fixture.library.drafts.map(\.id) == [draft])

        fixture.model.tab = .history
        fixture.model.requestDelete(entry)
        #expect(fixture.library.history.map(\.id) == [entry])

        fixture.session.resolvePendingSwitch(.cancel)
        #expect(fixture.model.isDeleteAvailable)
    }

    @Test("AC-26: activate・activateSelection・requestDelete は、文章を変える前に beforeUserAction を呼ぶ")
    func userActionsCallBeforeUserActionFirst() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let draft = try fixture.addDraft("draft")
        var calls: [String] = []
        fixture.model.beforeUserAction = {
            calls.append("before:\(fixture.panel.text.isEmpty ? "empty" : "text")")
        }

        fixture.model.activate(draft)
        fixture.model.activateSelection()
        fixture.model.requestDelete(draft)

        #expect(calls == ["before:empty", "before:text", "before:text"])
    }

    @Test("AC-2: 下書きの削除でパネルに出している下書きを消すと、本文は残って保存していない書きかけになる")
    func deletingShownDraftKeepsText() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let draft = try fixture.addDraft("shown")
        fixture.model.activate(draft)

        fixture.model.requestDelete(draft)

        #expect(fixture.panel.text == "shown")
        #expect(fixture.session.document == .scratch)
        #expect(fixture.model.rows.isEmpty)
    }

    // MARK: - 切り替えのアイコン

    @Test("AC-29: 「下書き」「履歴」の切り替えは、それぞれヘルプとラベル用の題を持ち、アイコンは互いに違う")
    func tabsHaveTitlesAndDistinctIcons() {
        #expect(SidebarTab.allCases == [.drafts, .history])
        #expect(SidebarTab.drafts.title == "下書き")
        #expect(SidebarTab.history.title == "履歴")
        #expect(SidebarTab.drafts.systemImageName != SidebarTab.history.systemImageName)
        #expect(SidebarTab.allCases.allSatisfy { !$0.systemImageName.isEmpty })
    }

    // MARK: - 失敗の説明

    @Test("AC-42: 何も問題が無ければ失敗の説明は出ない")
    func noProblemMeansNoMessage() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        #expect(fixture.model.problemMessage == nil)
        fixture.model.tab = .history
        #expect(fixture.model.problemMessage == nil)
    }

    @Test("AC-42: 下書き・履歴のファイルが読めなかったときの説明は、どちらの側を表示していても出て、空の説明も出る")
    func unreadableFilesAreReportedOnBothSides() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try directory.write("broken", named: DraftLibraryStore.draftsFileName)
        let fixture = try Fixture(store: DraftLibraryStore(directory: directory.dataDirectory))
        defer { fixture.cleanUp() }

        let draftsMessage = "保存してあった下書きを読み込めませんでした。元のファイルは別名で残してあります。"
        #expect(fixture.model.problemMessage == draftsMessage)
        #expect(fixture.model.emptyMessage == "⌘S で今の文章を取っておけます")
        fixture.model.tab = .history
        #expect(fixture.model.problemMessage == draftsMessage)

        try directory.write("{\"version\": 2, \"history\": []}", named: DraftLibraryStore.historyFileName)
        let both = try Fixture(store: DraftLibraryStore(directory: directory.dataDirectory))
        defer { both.cleanUp() }
        #expect(both.model.problemMessage == "挿入の履歴を読み込めませんでした。元のファイルは別名で残してあります。")
    }

    @Test("AC-42: 両方のファイルが読めなかったときは、下書き・履歴の順に改行でつなぐ")
    func bothUnreadableMessagesAreJoinedInOrder() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try directory.write("broken", named: DraftLibraryStore.draftsFileName)
        try directory.write("broken", named: DraftLibraryStore.historyFileName)
        let fixture = try Fixture(store: DraftLibraryStore(directory: directory.dataDirectory))
        defer { fixture.cleanUp() }

        #expect(fixture.model.problemMessage == """
        保存してあった下書きを読み込めませんでした。元のファイルは別名で残してあります。
        挿入の履歴を読み込めませんでした。元のファイルは別名で残してあります。
        """)
    }

    @Test("AC-42: 書き出しに失敗したときは保存の失敗の説明が出て、書き出せると消える。読み込みの失敗の説明は残る")
    func saveFailureMessageAppearsAndClears() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try directory.write("broken", named: DraftLibraryStore.draftsFileName)
        let fixture = try Fixture(store: DraftLibraryStore(directory: directory.dataDirectory))
        defer { fixture.cleanUp() }
        let unreadable = "保存してあった下書きを読み込めませんでした。元のファイルは別名で残してあります。"
        let saveFailed = "保存できませんでした。ディスクの空きを確かめてください。"

        try FileManager.default.removeItem(at: directory.dataDirectory)
        try Data("file".utf8).write(to: directory.dataDirectory)
        try fixture.addDraft("kept in memory")

        #expect(fixture.model.problemMessage == "\(saveFailed)\n\(unreadable)")
        #expect(fixture.model.rows.map(\.title) == ["kept in memory"])

        try FileManager.default.removeItem(at: directory.dataDirectory)
        fixture.library.flush()

        #expect(fixture.model.problemMessage == unreadable)
    }

    @Test("AC-42: 書き出しの失敗だけのときは、保存の失敗の説明だけが出る")
    func saveFailureAloneShowsOnlySaveFailure() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        try FileManager.default.createDirectory(at: directory.root, withIntermediateDirectories: true)
        try Data("file".utf8).write(to: directory.dataDirectory)
        let fixture = try Fixture(store: DraftLibraryStore(directory: directory.dataDirectory))
        defer { fixture.cleanUp() }

        fixture.addHistory("history")

        #expect(fixture.model.problemMessage == "保存できませんでした。ディスクの空きを確かめてください。")
        fixture.model.tab = .history
        #expect(fixture.model.problemMessage == "保存できませんでした。ディスクの空きを確かめてください。")

        try FileManager.default.removeItem(at: directory.dataDirectory)
        fixture.addHistory("again")

        #expect(fixture.model.problemMessage == nil)
    }
}
