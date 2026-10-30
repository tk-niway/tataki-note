import Foundation
@testable import TatakiNote

@MainActor
final class RecordingUpdater: UpdaterDriving {
    var onEvent: ((UpdaterEvent) -> Void)?
    var onCanCheckChange: ((Bool) -> Void)?
    var canCheckForUpdates = true
    var isSessionInProgress = false
    private(set) var startCount = 0
    private(set) var backgroundCheckCount = 0
    private(set) var userCheckCount = 0

    func start() {
        startCount += 1
    }

    func checkInBackground() {
        backgroundCheckCount += 1
    }

    func checkByUser() {
        userCheckCount += 1
    }

    func send(_ event: UpdaterEvent) {
        onEvent?(event)
    }
}
