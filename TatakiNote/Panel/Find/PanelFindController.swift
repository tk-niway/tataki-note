import AppKit

/// 検索欄・置換欄の部品が、どちらの欄かを名乗る。
protocol FindFieldIdentifying: AnyObject {
    var findField: FindField { get }
}

/// 検索バーのボタンの操作。
enum FindBarAction: Equatable {
    case toggleReplace
    case previous
    case next
    case close
    case replaceOne
    case replaceAll
    case toggle(FindOption)
}

/// パネルの検索バーのキーとボタンの操作を、検索の状態と入力欄へ振り分ける。
final class PanelFindController {
    private let model: FindModel
    private let registry: FindEditorRegistry
    private let panel: NSWindow

    init(model: FindModel, registry: FindEditorRegistry, panel: NSWindow) {
        self.model = model
        self.registry = registry
        self.panel = panel
    }

    /// ファーストレスポンダーからフォーカスの場所を決める。
    static func focus(of responder: NSResponder?) -> FindFocus {
        if responder is PromptTextView {
            return .editor
        }
        if let textView = responder as? NSTextView, let identifying = textView.delegate as? FindFieldIdentifying {
            return fieldFocus(identifying.findField)
        }
        if let identifying = responder as? FindFieldIdentifying {
            return fieldFocus(identifying.findField)
        }
        return .other
    }

    /// キーを判定して検索の操作を行う。行った(または飲み込んだ)なら true。
    func handleKey(_ input: PanelKeyInput) -> Bool {
        guard let action = FindKeyResolver.action(
            for: input,
            focus: Self.focus(of: panel.firstResponder),
            isBarVisible: model.isBarVisible,
            isReplaceShown: model.isReplaceShown
        ) else { return false }
        perform(action)
        return true
    }

    /// キーの操作を行う。
    func perform(_ action: FindKeyAction) {
        let focus = Self.focus(of: panel.firstResponder)
        switch action {
        case .open(let revealsReplace):
            let seed = focus == .editor ? currentSeed() : nil
            model.open(revealsReplace: revealsReplace, movesFocus: true, seed: seed)
        case .next, .previous:
            if !model.isBarVisible {
                model.open(revealsReplace: false, movesFocus: false, seed: model.query.isEmpty ? currentSeed() : nil)
            }
            if action == .next {
                model.moveToNext()
            } else {
                model.moveToPrevious()
            }
        case .toggle(let option):
            model.toggle(option)
        case .replaceOne:
            model.replaceOne()
        case .replaceAll:
            model.replaceAll()
        case .close:
            model.close()
            if focus == .editor || focus == .findField || focus == .replaceField {
                registry.editor?.focusForFind()
            }
        case .focusFindField:
            model.requestFocus(.find)
        case .focusReplaceField:
            if model.isReplaceShown {
                model.requestFocus(.replace)
            }
        case .focusEditor:
            registry.editor?.focusForFind()
        case .insertNewlineInField:
            (panel.firstResponder as? NSTextView)?.insertNewlineIgnoringFieldEditor(nil)
        case .swallow:
            break
        }
    }

    /// タイトルバーの虫眼鏡の操作。検索バーが出ていれば閉じ、出ていなければ ⌘F と同じく出す。
    func toggleBar() {
        if model.isBarVisible {
            perform(FindKeyAction.close)
        } else {
            perform(FindKeyAction.open(revealsReplace: false))
        }
    }

    /// 検索バーのボタンの操作を行う。
    func perform(_ action: FindBarAction) {
        switch action {
        case .toggleReplace:
            model.toggleReplace()
        case .previous: perform(FindKeyAction.previous)
        case .next: perform(FindKeyAction.next)
        case .close: perform(FindKeyAction.close)
        case .replaceOne: perform(FindKeyAction.replaceOne)
        case .replaceAll: perform(FindKeyAction.replaceAll)
        case .toggle(let option): perform(FindKeyAction.toggle(option))
        }
    }

    private static func fieldFocus(_ field: FindField) -> FindFocus {
        field == .find ? .findField : .replaceField
    }

    private func currentSeed() -> String? {
        guard let editor = registry.editor else { return nil }
        return FindNavigation.seed(
            selection: editor.findSelection,
            in: editor.findText as NSString,
            isRegex: model.options.isRegex
        )
    }
}
