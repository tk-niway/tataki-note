import AppKit
import Observation

/// サイドバーで表示する側。
enum SidebarTab: String, CaseIterable {
    case drafts
    case history

    /// 切り替えのアイコンのヘルプとアクセシビリティのラベル。
    var title: String {
        switch self {
        case .drafts: "下書き"
        case .history: "履歴"
        }
    }

    /// 切り替えのアイコンの SF Symbols の名前。
    var systemImageName: String {
        switch self {
        case .drafts: "doc.text"
        case .history: "clock.arrow.circlepath"
        }
    }
}

/// 一覧の1行。
struct SidebarRow: Equatable, Identifiable {
    enum Kind: Equatable {
        case draft
        case history
    }

    let id: UUID
    let kind: Kind
    let title: String
    let detail: String?
    let isShownInPanel: Bool
    var isUntitled = false
    var preview: String?

    /// 読み上げに使う文字。1段目・日時・本文の続きをつなぐ。
    var accessibilityText: String {
        [title, detail, preview].compactMap { $0 }.joined(separator: " ")
    }
}

/// サイドバーの開閉・表示中の側・検索・選択の状態。
@Observable final class SidebarModel {
    static let untitledDraftTitle = "(空の下書き)"
    static let unknownAppName = "不明なアプリ"

    /// 検索欄の文字。
    var query: String = ""

    private(set) var searchFocusRequest = 0
    private(set) var listFocusRequest = 0
    /// サイドバーが滑って開閉している間、本文の部分に保つ幅。動いていなければ nil。
    var slidingBodyWidth: CGFloat?
    private(set) var bodyFocusRequest = 0

    /// 窓のファーストレスポンダーに未確定の文字があるか。
    @ObservationIgnored var markedTextProbe: () -> Bool = { false }

    /// クリックで文章を変える操作の前に呼ぶ処理。
    @ObservationIgnored var beforeUserAction: () -> Void = {}

    /// 一覧の esc で呼ぶ、パネルを閉じる処理。
    @ObservationIgnored var closePanel: () -> Void = {}

    /// 行の文章を書き出す処理。
    @ObservationIgnored var exportText: (String) -> Void = { _ in }

    /// 行の文章を共有する処理。
    @ObservationIgnored var shareText: (String) -> Void = { _ in }

    @ObservationIgnored private var handledSearchFocusRequest = 0
    @ObservationIgnored private var handledListFocusRequest = 0

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let library: DraftLibrary
    @ObservationIgnored private let session: DraftSession
    @ObservationIgnored private let dateFormatter: (Date) -> String

    init(
        settings: AppSettings,
        library: DraftLibrary,
        session: DraftSession,
        dateFormatter: @escaping (Date) -> String = SidebarModel.defaultDateText
    ) {
        self.settings = settings
        self.library = library
        self.session = session
        self.dateFormatter = dateFormatter
    }

    /// 今年なら月日・時分、それ以外は年も付けた文字。
    nonisolated static func defaultDateText(_ date: Date) -> String {
        SidebarDateText.text(for: date, now: Date(), calendar: SidebarDateText.gregorian)
    }

    // MARK: - 開閉と表示中の側

    var isOpen: Bool { settings.isSidebarOpen }

    /// サイドバーを開閉する。
    func setOpen(_ isOpen: Bool) {
        settings.isSidebarOpen = isOpen
    }

    /// 表示中の側。
    var tab: SidebarTab {
        get { settings.sidebarTab }
        set {
            guard newValue != settings.sidebarTab else { return }
            settings.sidebarTab = newValue
        }
    }

    // MARK: - 一覧

    /// 切り替えに出す件数。検索の絞り込みに関係なく、その側の全件の数。
    func count(of tab: SidebarTab) -> Int {
        switch tab {
        case .drafts: library.drafts.count
        case .history: library.history.count
        }
    }

    /// 表示中の側を `query` で絞った行。
    var rows: [SidebarRow] {
        let needle = trimmedQuery
        switch tab {
        case .drafts:
            return library.drafts
                .filter { matches($0.text, needle) }
                .map { draft in
                    let firstLine = DraftListing.firstLine(of: draft.text)
                    return SidebarRow(
                        id: draft.id,
                        kind: .draft,
                        title: firstLine ?? Self.untitledDraftTitle,
                        detail: dateFormatter(draft.updatedAt),
                        isShownInPanel: session.document == .savedDraft(draft.id),
                        isUntitled: firstLine == nil,
                        preview: DraftListing.preview(of: draft.text)
                    )
                }
        case .history:
            return library.history
                .filter { matches($0.text, needle) }
                .map { entry in
                    SidebarRow(
                        id: entry.id,
                        kind: .history,
                        title: DraftListing.firstLine(of: entry.text) ?? "",
                        detail: historyDetail(of: entry),
                        isShownInPanel: session.document == .fromHistory(entry.id),
                        preview: DraftListing.preview(of: entry.text)
                    )
                }
        }
    }

    /// ハイライトしている行。パネルに出ている行。無ければ、検索語があるときだけ先頭の行。
    var selection: UUID? {
        let current = rows
        if let shown = current.first(where: \.isShownInPanel) {
            return shown.id
        }
        return trimmedQuery.isEmpty ? nil : current.first?.id
    }

    /// 一覧が空のときの説明。
    var emptyMessage: String? {
        guard rows.isEmpty else { return nil }
        if isEmptyBySearch {
            return "「\(trimmedQuery)」に一致するものはありません"
        }
        switch tab {
        case .drafts: return "⌘S で今の文章を取っておけます"
        case .history: return "挿入した文章がここに残ります(最新 \(library.historyLimit) 件)"
        }
    }

    /// 一覧が空なのが、検索で絞った結果か。
    var isEmptyBySearch: Bool {
        guard rows.isEmpty, !trimmedQuery.isEmpty else { return false }
        switch tab {
        case .drafts: return !library.drafts.isEmpty
        case .history: return !library.history.isEmpty
        }
    }

    /// 読み込み・書き出しの失敗の説明。無ければ `nil`。
    var problemMessage: String? {
        var lines: [String] = []
        if library.problems.contains(.saveFailed) {
            lines.append("保存できませんでした。ディスクの空きを確かめてください。")
        }
        if library.problems.contains(.draftsUnreadable) {
            lines.append("保存してあった下書きを読み込めませんでした。元のファイルは別名で残してあります。")
        }
        if library.problems.contains(.historyUnreadable) {
            lines.append("挿入の履歴を読み込めませんでした。元のファイルは別名で残してあります。")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // MARK: - 検索と選択

    /// サイドバーを開いて検索欄にフォーカスを移す。
    func openForSearch() {
        setOpen(true)
        searchFocusRequest += 1
    }

    /// 検索欄へのフォーカスの要求がまだ当たっていないか。
    var hasPendingSearchFocus: Bool {
        searchFocusRequest != handledSearchFocusRequest
    }

    /// 検索欄へのフォーカスの要求を当てたと記録する。
    func markSearchFocusHandled() {
        handledSearchFocusRequest = searchFocusRequest
    }

    /// 一覧へのフォーカスの要求がまだ当たっていないか。
    var hasPendingListFocus: Bool {
        listFocusRequest != handledListFocusRequest
    }

    /// 一覧へフォーカスを移すよう求める。
    func focusList() {
        listFocusRequest += 1
    }

    /// 一覧へのフォーカスの要求を当てたと記録する。
    func markListFocusHandled() {
        handledListFocusRequest = listFocusRequest
    }

    /// 当たっていない一覧・検索欄へのフォーカスの要求を、当てたことにする。
    func discardPendingFocusRequests() {
        handledSearchFocusRequest = searchFocusRequest
        handledListFocusRequest = listFocusRequest
    }

    /// 本文へフォーカスを戻すよう求める。
    func returnToBody() {
        bodyFocusRequest += 1
    }

    // MARK: - 選択と呼び出し

    /// ハイライトを上下に動かし、動いた先の行の中身をパネルに出す。端で止まる。
    func moveSelection(by offset: Int) {
        let current = rows
        guard !current.isEmpty else { return }
        let targetIndex: Int
        if let selection, let index = current.firstIndex(where: { $0.id == selection }) {
            targetIndex = min(max(index + offset, 0), current.count - 1)
        } else {
            targetIndex = 0
        }
        load(current[targetIndex])
    }

    /// 行をクリックしたときの操作。中身をパネルに出して、一覧にフォーカスを置く。
    func show(_ id: UUID) {
        beforeUserAction()
        guard let row = rows.first(where: { $0.id == id }) else { return }
        load(row)
        focusList()
    }

    /// ハイライトしている行がパネルに出ていなければ出して、本文へフォーカスを移す。
    func confirmSelection() {
        beforeUserAction()
        if let id = selection, let row = rows.first(where: { $0.id == id }), !row.isShownInPanel {
            load(row)
        }
        returnToBody()
    }

    /// 表示する側を反対にする。
    func switchTab() {
        tab = tab == .drafts ? .history : .drafts
    }

    private func load(_ row: SidebarRow) {
        switch row.kind {
        case .draft: session.request(.draft(row.id))
        case .history: session.request(.history(row.id))
        }
    }

    // MARK: - 削除

    /// 行をすぐ消す。
    func requestDelete(_ id: UUID) {
        beforeUserAction()
        guard let row = rows.first(where: { $0.id == id }) else { return }
        switch row.kind {
        case .draft: session.deleteDraft(id: id)
        case .history: session.deleteHistoryEntry(id: id)
        }
    }

    /// ハイライトしている行をすぐ消す。ハイライトが無ければ何もしない。
    func deleteSelection() {
        guard let id = selection else { return }
        requestDelete(id)
    }

    // MARK: - 書き出しと共有

    /// 行の文章。行が無ければ `nil`。
    func text(of id: UUID) -> String? {
        if let draft = library.draft(id: id) {
            return draft.text
        }
        return library.history.first { $0.id == id }?.text
    }

    /// 行の文章を書き出し・共有できるか。文章が空・空白だけなら `false`。
    func canExport(_ id: UUID) -> Bool {
        guard let text = text(of: id) else { return false }
        return !ExportableText.isEmpty(text)
    }

    /// 行の文章を書き出す。書き出せない行では何もしない。
    func requestExport(_ id: UUID) {
        guard canExport(id), let text = text(of: id) else { return }
        exportText(text)
    }

    /// 行の文章を共有する。共有できない行では何もしない。
    func requestShare(_ id: UUID) {
        guard canExport(id), let text = text(of: id) else { return }
        shareText(text)
    }

    // MARK: - キー

    /// 検索欄・一覧で押したキーを処理する。処理した(または飲み込んだ)なら `true`。
    func handleKey(
        _ key: SidebarKey,
        source: SidebarKeySource,
        modifiers: NSEvent.ModifierFlags,
        hasMarkedText: Bool
    ) -> Bool {
        let action = SidebarKeyResolver.action(
            for: key,
            source: source,
            modifiers: modifiers,
            hasMarkedText: hasMarkedText
        )
        switch action {
        case .moveSelection(let offset): moveSelection(by: offset)
        case .confirmSelection: confirmSelection()
        case .returnToBody: returnToBody()
        case .closePanel: closePanel()
        case .switchTab: switchTab()
        case .deleteSelection: deleteSelection()
        case .swallow: break
        case .passThrough: return false
        }
        return true
    }

    // MARK: - 内部

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func historyDetail(of entry: HistoryEntry) -> String {
        let date = dateFormatter(entry.insertedAt)
        guard entry.isInserted else { return date }
        return "\(date) · \(entry.appName ?? Self.unknownAppName)"
    }

    private func matches(_ text: String, _ needle: String) -> Bool {
        needle.isEmpty || text.range(of: needle, options: [.caseInsensitive, .widthInsensitive]) != nil
    }
}
