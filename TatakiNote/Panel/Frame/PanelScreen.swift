/// パネルを新しく開くときに出す画面の選び方。
enum PanelScreen: String, CaseIterable, Sendable {
    case nearFocusedField
    case targetWindow
    case mouse
    case main

    static let defaultValue: PanelScreen = .nearFocusedField

    var usesTargetWindowFrame: Bool {
        self == .targetWindow || self == .nearFocusedField
    }
}
