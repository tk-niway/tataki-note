/// 以前の版で保存した確定+挿入キー・確定+送信キーの値を `PanelShortcut?` に読み替える。
enum PanelActionKey: String, CaseIterable, Sendable {
    case shiftEnter
    case commandEnter
    case commandShiftEnter
    case none

    var shortcut: PanelShortcut? {
        switch self {
        case .shiftEnter: .shiftReturn
        case .commandEnter: .commandReturn
        case .commandShiftEnter: .commandShiftReturn
        case .none: nil
        }
    }
}
