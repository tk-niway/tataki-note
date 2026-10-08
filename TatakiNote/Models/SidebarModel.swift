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

/// 検索欄・一覧で受けるキー。
enum SidebarKey: Equatable {
    case up
    case down
    case returnKey
    case escape
    case deleteBackward
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

    /// 右クリックのメニューの削除の項目の題。
    var deleteMenuTitle: String {
        switch kind {
        case .draft: "削除…"
        case .history: "削除"
        }
    }
}

/// サイドバーの開閉・表示中の側・検索・選択・削除の確認の状態。
@Observable final class SidebarModel {
    static let untitledDraftTitle = "(空の下書き)"
    static let unknownAppName = "不明なアプリ"

    /// 検索欄の文字。変えると選択を先頭の行に置き直し、下書きの削除の確認を取り消す。
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            selectedID = nil
            pendingDeletion = nil
        }
    }

    private(set) var pendingDeletion: UUID?
    private(set) var searchFocusRequest = 0
    /// サイドバーが滑って開閉している間、本文の部分に保つ幅。動いていなければ nil。
    var slidingBodyWidth: CGFloat?
    private(set) var bodyFocusRequest = 0

    /// 窓のファーストレスポンダーに未確定の文字があるか。
    @ObservationIgnored var markedTextProbe: () -> Bool = { false }

    /// クリックで文章を変える操作の前に呼ぶ処理。
    @ObservationIgnored var beforeUserAction: () -> Void = {}

    private var selectedID: UUID?
    @ObservationIgnored private var handledSearchFocusRequest = 0

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

    /// 月日・時分の文字。
    nonisolated static func defaultDateText(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute())
    }

    // MARK: - 開閉と表示中の側

    var isOpen: Bool { settings.isSidebarOpen }

    /// サイドバーを開閉する。閉じると下書きの削除の確認を取り消す。
    func setOpen(_ isOpen: Bool) {
        settings.isSidebarOpen = isOpen
        if !isOpen {
            pendingDeletion = nil
        }
    }

    /// 表示中の側。変えると選択を先頭の行に置き直し、下書きの削除の確認を取り消す。
    var tab: SidebarTab {
        get { settings.sidebarTab }
        set {
            guard newValue != settings.sidebarTab else { return }
            settings.sidebarTab = newValue
            selectedID = nil
            pendingDeletion = nil
        }
    }

    // MARK: - 一覧

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
                        detail: nil,
                        isShownInPanel: session.document == .savedDraft(draft.id),
                        isUntitled: firstLine == nil
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
                        detail: "\(dateFormatter(entry.insertedAt)) · \(entry.appName ?? Self.unknownAppName)",
                        isShownInPanel: false
                    )
                }
        }
    }

    /// 選んでいる行。一覧に無ければ先頭の行。
    var selection: UUID? {
        let current = rows
        if let selectedID, current.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return current.first?.id
    }

    /// 一覧が空のときの説明。
    var emptyMessage: String? {
        guard rows.isEmpty else { return nil }
        if isEmptyBySearch {
            return "「\(trimmedQuery)」に一致するものはありません"
        }
        switch tab {
        case .drafts: return "⌘S で今の文章を取っておけます"
        case .history: return "挿入した文章がここに残ります(最新 \(DraftLibrary.historyLimit) 件)"
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

    /// 選択を上下に動かす。端で止まる。
    func moveSelection(by offset: Int) {
        let current = rows
        guard !current.isEmpty else { return }
        let currentIndex = current.firstIndex { $0.id == selection } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), current.count - 1)
        selectedID = current[nextIndex].id
    }

    /// 行を選ぶ。一覧に無い行は無視する。
    func select(_ id: UUID) {
        guard rows.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// 本文へフォーカスを戻すよう求める。
    func returnToBody() {
        bodyFocusRequest += 1
    }

    // MARK: - 呼び出し

    /// 選んでいる行を呼び出す。
    func activateSelection() {
        beforeUserAction()
        guard let id = selection else { return }
        performActivation(of: id)
    }

    /// 行を選んで呼び出す。
    func activate(_ id: UUID) {
        beforeUserAction()
        performActivation(of: id)
    }

    private func performActivation(of id: UUID) {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        selectedID = id
        pendingDeletion = nil
        switch row.kind {
        case .draft: session.request(.draft(id))
        case .history: session.request(.history(id))
        }
        returnToBody()
    }

    // MARK: - 削除

    /// 右クリックのメニューの削除の項目を押せるか。
    var isDeleteAvailable: Bool {
        session.pendingSwitch == nil
    }

    /// 行の削除を求める。下書きは確認を出し、履歴はすぐ消す。
    func requestDelete(_ id: UUID) {
        beforeUserAction()
        guard isDeleteAvailable, let row = rows.first(where: { $0.id == id }) else { return }
        switch row.kind {
        case .draft: pendingDeletion = id
        case .history: session.deleteHistoryEntry(id: id)
        }
    }

    /// 選んでいる行の削除を求める。
    func deleteSelection() {
        guard let id = selection else { return }
        requestDelete(id)
    }

    /// 下書きの削除の確認に「削除」と答える。
    func confirmDeletion() {
        guard let id = pendingDeletion else { return }
        pendingDeletion = nil
        session.deleteDraft(id: id)
    }

    /// 下書きの削除の確認に「キャンセル」と答える。
    func cancelDeletion() {
        pendingDeletion = nil
    }

    // MARK: - キー

    /// 検索欄・一覧で押したキーを処理する。処理した(または飲み込んだ)なら `true`。
    func handleKey(_ key: SidebarKey, modifiers: NSEvent.ModifierFlags, hasMarkedText: Bool) -> Bool {
        if hasMarkedText { return false }
        let relevant = modifiers.intersection(PanelShortcut.relevantModifiers)
        if pendingDeletion != nil {
            switch key {
            case .returnKey where relevant.isEmpty: confirmDeletion()
            case .escape: cancelDeletion()
            default: break
            }
            return true
        }
        switch key {
        case .up:
            guard relevant.isEmpty else { return false }
            moveSelection(by: -1)
            return true
        case .down:
            guard relevant.isEmpty else { return false }
            moveSelection(by: 1)
            return true
        case .returnKey:
            if relevant.isEmpty {
                activateSelection()
            }
            return true
        case .escape:
            guard relevant.isEmpty else { return false }
            returnToBody()
            return true
        case .deleteBackward:
            guard relevant == [.command] else { return false }
            deleteSelection()
            return true
        }
    }

    // MARK: - 内部

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ text: String, _ needle: String) -> Bool {
        needle.isEmpty || text.range(of: needle, options: [.caseInsensitive, .widthInsensitive]) != nil
    }
}
