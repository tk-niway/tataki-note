import Foundation

/// 挿入できなかったことを利用者に伝える内容。
struct InsertionFailureNotice: Equatable {
    enum Reason: Equatable {
        case noTarget
        case targetNotActivated(appName: String?)
        case noTextInput(appName: String?)
    }

    var reason: Reason
    var isDraftKept: Bool
}

protocol InsertionFailureNotifying {
    func notify(_ notice: InsertionFailureNotice) async
}
