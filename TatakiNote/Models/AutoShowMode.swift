/// 入力欄が選ばれたときにパネルを自動で出すかどうか。
enum AutoShowMode: String, CaseIterable, Sendable {
    case off
    case allApps
    case selectedApps

    static let defaultValue: AutoShowMode = .off
}
