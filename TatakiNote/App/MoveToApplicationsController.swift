import AppKit

/// 「アプリケーション」フォルダの外から起動されたときに、移動を確認して移す。
final class MoveToApplicationsController {
    private let settings: AppSettings
    private let terminateForRelaunch: () -> Void
    private let mover: ApplicationMover
    private let terminator: OtherInstanceTerminator

    init(
        settings: AppSettings,
        terminateForRelaunch: @escaping () -> Void,
        mover: ApplicationMover = .system,
        terminator: OtherInstanceTerminator = .system
    ) {
        self.settings = settings
        self.terminateForRelaunch = terminateForRelaunch
        self.mover = mover
        self.terminator = terminator
    }

    /// 必要なら確認を出し、選ばれたとおりにする。開き直すために終了へ向かうなら true。
    func offerIfNeeded() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        let source = ApplicationLocation.moveSource(
            bundlePath: bundleURL.path,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            isOnReadOnlyVolume: Self.isOnReadOnlyVolume(bundleURL)
        )
        guard ApplicationLocation.shouldAsk(source: source, isSuppressed: settings.suppressesMoveToApplicationsPrompt),
              let source
        else { return false }

        let others = Self.otherInstanceIdentifiers()
        let choice = ask(otherInstanceIsRunning: !others.isEmpty)
        switch MoveToApplicationsPrompt.step(choice: choice, otherInstanceIsRunning: !others.isEmpty) {
        case .stay(let suppresses):
            if suppresses { settings.suppressesMoveToApplicationsPrompt = true }
            return false
        case .terminateOthersThenMove:
            guard terminator.terminateAll(others) else {
                showFailure(
                    message: String(localized: "動いている TatakiNote を終了できませんでした。"),
                    informative: String(localized: "メニューバーの TatakiNote から「終了」を選んでから、もう一度開いてください。")
                )
                return false
            }
            return move(from: bundleURL, as: source)
        case .move:
            return move(from: bundleURL, as: source)
        }
    }

    private func move(from bundleURL: URL, as source: ApplicationMoveSource) -> Bool {
        let destination: URL
        do {
            destination = try mover.move(from: bundleURL, as: source)
        } catch {
            showFailure(
                message: String(localized: "「アプリケーション」フォルダへ移動できませんでした。"),
                informative: String(localized: "Finder で TatakiNote を「アプリケーション」フォルダへドラッグしてください。")
            )
            return false
        }
        do {
            try AppRelauncher.relaunch(at: destination)
        } catch {
            return false
        }
        terminateForRelaunch()
        return true
    }

    private func ask(otherInstanceIsRunning: Bool) -> MoveChoice {
        let alert = NSAlert()
        alert.messageText = String(localized: "TatakiNote を「アプリケーション」フォルダへ移動しますか?")
        alert.informativeText = MoveToApplicationsPrompt.informativeText(otherInstanceIsRunning: otherInstanceIsRunning)
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "移動する"))
        let stayButton = alert.addButton(withTitle: String(localized: "移動しない"))
        stayButton.keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "今後は聞かない")
        NSApp.activate()
        let response = alert.runModal()
        return MoveToApplicationsPrompt.choice(
            isMoveButton: response == .alertFirstButtonReturn,
            isSuppressionChecked: alert.suppressionButton?.state == .on
        )
    }

    private func showFailure(message: String, informative: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }

    private static func isOnReadOnlyVolume(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
    }

    private static func otherInstanceIdentifiers() -> [Int32] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return [] }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(\.processIdentifier)
        return MoveToApplicationsPrompt.otherInstanceIdentifiers(
            running: running,
            own: ProcessInfo.processInfo.processIdentifier
        )
    }
}
