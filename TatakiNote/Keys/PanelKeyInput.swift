import AppKit

/// 入力欄に届いたキーの値。
struct PanelKeyInput: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    var hasMarkedText: Bool
    var characters: String = ""
}

extension PanelKeyInput {
    /// キーのイベントから作る。修飾キーは機器によらない印に絞り、文字は修飾キーを除いた文字の小文字にする。
    init(event: NSEvent, hasMarkedText: Bool) {
        self.init(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
            hasMarkedText: hasMarkedText,
            characters: event.charactersIgnoringModifiers?.lowercased() ?? ""
        )
    }
}
