import Foundation

/// 検索・置換をする入力欄。
protocol FindTextEditing: AnyObject {
    var findText: String { get }
    var findSelection: NSRange { get }
    func showFindHighlights(_ ranges: [NSRange], current: NSRange?)
    func revealFindMatch(_ range: NSRange)
    func popFindMatch(_ range: NSRange)
    func replaceForFind(_ edits: [FindEdit], selectionAfter: NSRange)
    func focusForFind()
}

/// 1か所の置き換え。
struct FindEdit: Equatable {
    let range: NSRange
    let replacement: String
}

/// パネルの入力欄を弱い参照で覚える入れ物。
final class FindEditorRegistry {
    weak var editor: (any FindTextEditing)?
}
