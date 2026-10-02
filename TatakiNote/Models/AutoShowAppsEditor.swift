import AppKit
import Observation

/// 起動中のアプリの一覧を返す(「＋」の候補に使う)。
protocol RunningApplicationsProviding {
    func runningApplications() -> [AutoShowApp]
}

/// `NSWorkspace` から起動中のアプリを取る。
struct WorkspaceRunningApplications: RunningApplicationsProviding {
    func runningApplications() -> [AutoShowApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let bundleIdentifier = app.bundleIdentifier else { return nil }
            return AutoShowApp(bundleIdentifier: bundleIdentifier, name: app.localizedName ?? bundleIdentifier)
        }
    }
}

/// 対象のアプリの一覧の1行に出すもの。
struct AutoShowAppRow: Equatable, Identifiable {
    var bundleIdentifier: String
    var name: String
    var applicationURL: URL?

    var id: String { bundleIdentifier }
}

/// 設定画面の「選んだアプリのみ」の一覧の状態と操作。
@Observable
final class AutoShowAppsEditor {
    var selection: String?

    private(set) var runningApps: [AutoShowApp] = []

    private let settings: AppSettings
    private let runningApplications: any RunningApplicationsProviding
    private let applicationURL: (String) -> URL?
    private let ownBundleIdentifier: String?
    private let notificationCenter: NotificationCenter
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(
        settings: AppSettings,
        runningApplications: any RunningApplicationsProviding = WorkspaceRunningApplications(),
        applicationURL: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.settings = settings
        self.runningApplications = runningApplications
        self.applicationURL = applicationURL
        self.ownBundleIdentifier = ownBundleIdentifier
        self.notificationCenter = notificationCenter

        refreshRunningApps()

        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        observers = names.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshRunningApps()
                }
            }
        }
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    var isEditable: Bool {
        settings.autoShowMode == .selectedApps
    }

    var candidates: [AutoShowApp] {
        Self.candidates(running: runningApps, selected: settings.autoShowApps, ownBundleIdentifier: ownBundleIdentifier)
    }

    var canRemove: Bool {
        isEditable && AutoShowApp.contains(settings.autoShowApps, bundleIdentifier: selection)
    }

    func rows() -> [AutoShowAppRow] {
        settings.autoShowApps.map { app in
            AutoShowAppRow(
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                applicationURL: applicationURL(app.bundleIdentifier)
            )
        }
    }

    func refreshRunningApps() {
        runningApps = runningApplications.runningApplications()
    }

    func add(_ app: AutoShowApp) {
        guard !AutoShowApp.contains(settings.autoShowApps, bundleIdentifier: app.bundleIdentifier) else { return }
        settings.autoShowApps = AutoShowApp.normalized(settings.autoShowApps + [app])
    }

    func removeSelected() {
        guard canRemove, let selection else { return }
        settings.autoShowApps.removeAll { $0.bundleIdentifier == selection }
        self.selection = nil
    }

    @discardableResult
    func addApplication(at url: URL) -> Bool {
        guard let bundle = Bundle(url: url),
              let app = Self.app(
                  bundleIdentifier: bundle.bundleIdentifier,
                  displayName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                  bundleName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                  fileName: url.deletingPathExtension().lastPathComponent
              )
        else { return false }
        add(app)
        return true
    }

    // MARK: - 純粋関数(テストはここを見る)

    static func candidates(running: [AutoShowApp], selected: [AutoShowApp], ownBundleIdentifier: String?) -> [AutoShowApp] {
        AutoShowApp.normalized(running)
            .filter { app in
                app.bundleIdentifier != ownBundleIdentifier
                    && !AutoShowApp.contains(selected, bundleIdentifier: app.bundleIdentifier)
            }
            .sorted { lhs, rhs in
                switch lhs.name.localizedStandardCompare(rhs.name) {
                case .orderedAscending:
                    true
                case .orderedDescending:
                    false
                case .orderedSame:
                    lhs.bundleIdentifier < rhs.bundleIdentifier
                }
            }
    }

    static func app(bundleIdentifier: String?, displayName: String?, bundleName: String?, fileName: String) -> AutoShowApp? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        let name = [displayName, bundleName].compactMap { $0 }.first { !$0.isEmpty } ?? fileName
        return AutoShowApp(bundleIdentifier: bundleIdentifier, name: name)
    }
}
