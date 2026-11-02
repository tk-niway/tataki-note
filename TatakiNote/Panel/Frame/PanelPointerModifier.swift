import AppKit

/// 移動・サイズ変更に使う修飾キー。
enum PanelPointerModifier: String, CaseIterable {
    case shift, function, control, option, command

    /// 設定画面に出す記号。
    var symbol: String {
        switch self {
        case .shift: "⇧"
        case .function: "fn"
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        }
    }

    /// 読み上げの名前。
    var accessibilityName: String {
        switch self {
        case .shift: "shift"
        case .function: "fn"
        case .control: "control"
        case .option: "option"
        case .command: "command"
        }
    }

    /// 対応する NSEvent.ModifierFlags の1つ。
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .function: .function
        case .control: .control
        case .option: .option
        case .command: .command
        }
    }

    /// イベントの修飾キーのフラグを、この5つの集合にする。caps lock・テンキー・help など5つ以外は無視する。
    static func set(from flags: NSEvent.ModifierFlags) -> Set<PanelPointerModifier> {
        let deviceIndependent = flags.intersection(.deviceIndependentFlagsMask)
        return Set(allCases.filter { deviceIndependent.contains($0.flag) })
    }
}

/// 修飾キーで行う操作。
enum PanelPointerAction: String, CaseIterable {
    case move, resize

    /// もう一方の操作。
    var other: PanelPointerAction {
        switch self {
        case .move: .resize
        case .resize: .move
        }
    }
}
