import Foundation

/// 更新の仕組みから届く出来事。
enum UpdaterEvent: Equatable {
    case foundInBackground(version: String)
    case checkCompleted
    case checkFailed
    case userAttended
    case sessionFinished
    case willRelaunch
}

/// 更新の確認と入れ替えをする仕組み。
protocol UpdaterDriving: AnyObject {
    var onEvent: ((UpdaterEvent) -> Void)? { get set }
    var onCanCheckChange: ((Bool) -> Void)? { get set }
    var canCheckForUpdates: Bool { get }
    var isSessionInProgress: Bool { get }
    func start()
    func checkInBackground()
    func checkByUser()
}

/// 何もしない更新の仕組み。
final class InertUpdater: UpdaterDriving {
    var onEvent: ((UpdaterEvent) -> Void)?
    var onCanCheckChange: ((Bool) -> Void)?
    let canCheckForUpdates = false
    let isSessionInProgress = false

    func start() {}

    func checkInBackground() {}

    func checkByUser() {}
}

#if DEBUG
/// 起動するとすぐ新しい版 9.9.9 を見つけたことにする、確認用の更新の仕組み。
final class PreviewUpdater: UpdaterDriving {
    var onEvent: ((UpdaterEvent) -> Void)?
    var onCanCheckChange: ((Bool) -> Void)?
    let canCheckForUpdates = true
    let isSessionInProgress = false

    func start() {
        onEvent?(.foundInBackground(version: "9.9.9"))
    }

    func checkInBackground() {}

    func checkByUser() {
        onEvent?(.userAttended)
        onEvent?(.sessionFinished)
    }
}
#endif
