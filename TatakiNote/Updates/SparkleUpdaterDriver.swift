#if canImport(Sparkle)
import AppKit
import Sparkle

/// Sparkle で更新の確認と入れ替えをする。
final class SparkleUpdaterDriver: NSObject, UpdaterDriving, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    var onEvent: ((UpdaterEvent) -> Void)?
    var onCanCheckChange: ((Bool) -> Void)?

    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    var isSessionInProgress: Bool {
        controller?.updater.sessionInProgress ?? false
    }

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.controller = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            guard let canCheck = change.newValue else { return }
            Task { @MainActor in
                self?.onCanCheckChange?(canCheck)
            }
        }
        controller.startUpdater()
        onCanCheckChange?(controller.updater.canCheckForUpdates)
    }

    func checkInBackground() {
        controller?.updater.checkForUpdatesInBackground()
    }

    func checkByUser() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onEvent?(.checkCompleted)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        onEvent?(.checkCompleted)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        onEvent?(.checkFailed)
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        onEvent?(.willRelaunch)
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool {
        UpdatePresentation.supportsGentleReminders
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        UpdatePresentation.showsBackgroundUpdateImmediately
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        onEvent?(.foundInBackground(version: update.displayVersionString))
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onEvent?(.userAttended)
    }

    func standardUserDriverWillFinishUpdateSession() {
        onEvent?(.sessionFinished)
    }
}
#endif
