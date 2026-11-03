import CoreGraphics
import Foundation
import Observation

/// 検索バーの欄。
enum FindField: Equatable {
    case find
    case replace
}

/// 検索欄・置換欄へフォーカスを移す要求。count が増えるたびに1回だけ当てる。
struct FindFieldFocusRequest: Equatable {
    var field: FindField
    var count: Int
}

/// 検索バーの状態と、入力欄への検索・置換の指示。
@Observable
final class FindModel {
    private(set) var isBarVisible = false
    private(set) var isReplaceShown = false
    var replacement = ""
    private(set) var options = FindOptions()
    private(set) var matches: [NSRange] = []
    private(set) var isTruncated = false
    private(set) var isPatternInvalid = false
    private(set) var currentIndex: Int?
    private(set) var focusRequest = FindFieldFocusRequest(field: .find, count: 0)
    private(set) var appliedFocusCount = 0

    /// 検索・置換をする入力欄。
    @ObservationIgnored var editor: () -> (any FindTextEditing)? = { nil }

    /// 検索語。変わったら数え直し、選択の位置から最も近い一致を選ぶ。
    var query: String {
        get { storedQuery }
        set {
            guard newValue != storedQuery else { return }
            storedQuery = newValue
            research(movesSelection: true)
        }
    }

    /// 検索バーの高さ。
    var barHeight: CGFloat {
        FindBarMetrics.height(isVisible: isBarVisible, isReplaceShown: isReplaceShown)
    }

    /// 件数の表示。
    var countText: String {
        FindNavigation.countText(for: searchResult, currentIndex: currentIndex)
    }

    /// 正規表現が正しくないときの知らせ。
    var errorMessage: String? {
        isPatternInvalid ? FindNavigation.invalidPatternMessage : nil
    }

    private var storedQuery = ""
    private var searchResult: TextSearchResult = .noQuery

    /// その欄へのフォーカスの要求が、まだ当てられていないか。
    func hasPendingFocus(for field: FindField) -> Bool {
        isBarVisible && focusRequest.field == field && focusRequest.count > appliedFocusCount
    }

    /// 欄がフォーカスの要求を当て終えたことを知らせる。
    func didApplyFocus() {
        appliedFocusCount = focusRequest.count
    }

    // MARK: - 開閉

    /// 検索バーを出す。種があれば検索語に入れ、数え直して選択の位置から最も近い一致を選ぶ。
    func open(revealsReplace: Bool, movesFocus: Bool, seed: String?) {
        isBarVisible = true
        if revealsReplace {
            isReplaceShown = true
        }
        if let seed {
            storedQuery = seed
        }
        if movesFocus {
            requestFocus(revealsReplace && seed != nil ? .replace : .find)
        }
        research(movesSelection: true)
    }

    /// 検索バーを閉じてハイライトを消す。検索語・置換語・オプションは残す。
    func close() {
        guard isBarVisible else { return }
        isBarVisible = false
        appliedFocusCount = focusRequest.count
        matches = []
        currentIndex = nil
        isTruncated = false
        isPatternInvalid = false
        searchResult = .noQuery
        editor()?.showFindHighlights([], current: nil)
    }

    /// 置換の行の出し入れ。
    func toggleReplace() {
        isReplaceShown.toggle()
    }

    /// 検索のオプションを切り替えて数え直す。
    func toggle(_ option: FindOption) {
        options.toggle(option)
        if option != .preserveCase {
            research(movesSelection: true)
        }
    }

    /// 指定の欄へのフォーカスを要求する。
    func requestFocus(_ field: FindField) {
        focusRequest = FindFieldFocusRequest(field: field, count: focusRequest.count + 1)
    }

    // MARK: - 一致の行き来

    /// 選択の後ろの一致へ進む。
    func moveToNext() {
        guard isBarVisible, let editor = editor(),
              let index = FindNavigation.nextIndex(in: matches, after: editor.findSelection)
        else { return }
        editor.revealFindMatch(matches[index])
        selectionDidChange()
    }

    /// 選択の前の一致へ戻る。
    func moveToPrevious() {
        guard isBarVisible, let editor = editor(),
              let index = FindNavigation.previousIndex(in: matches, before: editor.findSelection)
        else { return }
        editor.revealFindMatch(matches[index])
        selectionDidChange()
    }

    // MARK: - 置換

    /// 選択が一致なら置き換えて次の一致へ進む。一致でなければ置き換えずに次の一致へ移る。
    func replaceOne() {
        guard isBarVisible, let editor = editor(),
              case let .found(all, _) = fullSearch(in: editor.findText),
              !all.isEmpty
        else { return }
        let text = editor.findText as NSString
        let selection = editor.findSelection
        guard let match = all.first(where: { $0.range == selection }) else {
            moveToNext()
            return
        }
        let replaced = ReplacePattern.replacement(for: match, in: text, template: replacement, options: options)
        let end = match.range.location + (replaced as NSString).length
        editor.replaceForFind(
            [FindEdit(range: match.range, replacement: replaced)],
            selectionAfter: NSRange(location: end, length: 0)
        )
        research(movesSelection: false)
        moveToNext()
    }

    /// すべての一致を1回の編集で置き換える。
    func replaceAll() {
        guard isBarVisible, let editor = editor(),
              case let .found(all, _) = fullSearch(in: editor.findText),
              !all.isEmpty
        else { return }
        let text = editor.findText as NSString
        var edits: [FindEdit] = []
        var shift = 0
        var selectionEnd = 0
        for match in all {
            let replaced = ReplacePattern.replacement(for: match, in: text, template: replacement, options: options)
            let replacedLength = (replaced as NSString).length
            edits.append(FindEdit(range: match.range, replacement: replaced))
            selectionEnd = match.range.location + shift + replacedLength
            shift += replacedLength - match.range.length
        }
        editor.replaceForFind(edits, selectionAfter: NSRange(location: selectionEnd, length: 0))
        research(movesSelection: false)
    }

    // MARK: - 入力欄の変化

    /// 入力欄の文章が変わったときに呼ぶ。選択は動かさずに数え直す。
    func textDidChange() {
        research(movesSelection: false)
    }

    /// 入力欄の選択が変わったときに呼ぶ。今の一致の番号だけ合わせ直す。
    func selectionDidChange() {
        guard isBarVisible, let editor = editor() else { return }
        guard FindNavigation.currentIndex(in: matches, selection: editor.findSelection) != currentIndex else { return }
        refreshCurrent(in: editor)
    }

    // MARK: - 内部

    private func fullSearch(in text: String) -> TextSearchResult {
        TextSearch.search(query, options: options, in: text, limit: nil)
    }

    private func research(movesSelection: Bool) {
        guard isBarVisible, let editor = editor() else { return }
        let result = TextSearch.search(query, options: options, in: editor.findText)
        searchResult = result
        switch result {
        case .noQuery:
            matches = []
            isTruncated = false
            isPatternInvalid = false
        case .invalidPattern:
            matches = []
            isTruncated = false
            isPatternInvalid = true
        case let .found(found, truncated):
            matches = found.map(\.range)
            isTruncated = truncated
            isPatternInvalid = false
        }
        if movesSelection,
           let index = FindNavigation.nearestIndex(in: matches, from: editor.findSelection.location) {
            editor.revealFindMatch(matches[index])
        }
        refreshCurrent(in: editor)
    }

    private func refreshCurrent(in editor: any FindTextEditing) {
        currentIndex = FindNavigation.currentIndex(in: matches, selection: editor.findSelection)
        editor.showFindHighlights(matches, current: currentIndex.map { matches[$0] })
    }
}
