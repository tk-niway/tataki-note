import AppKit
import Observation

/// @note p0-189
protocol RunningApplicationsProviding {
    /// @note p0-190
    func runningApplications() -> [AutoShowApp]
}

/// @note p0-191
struct WorkspaceRunningApplications: RunningApplicationsProviding {
    func runningApplications() -> [AutoShowApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let bundleIdentifier = app.bundleIdentifier else { return nil }
            return AutoShowApp(bundleIdentifier: bundleIdentifier, name: app.localizedName ?? bundleIdentifier)
        }
    }
}

/// @note p0-192
struct AutoShowAppRow: Equatable, Identifiable {
    var bundleIdentifier: String
    /// @note p0-193
    var name: String
    /// @note p0-194
    var applicationURL: URL?

    var id: String { bundleIdentifier }
}

/// @note p0-195
@Observable
final class AutoShowAppsEditor {
    /// @note p0-196
    var selection: String?

    /// @note p0-197
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

        // @note p0-198
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

    /// @note p0-199
    var isEditable: Bool {
        settings.autoShowMode == .selectedApps
    }

    /// @note p0-200
    var candidates: [AutoShowApp] {
        Self.candidates(running: runningApps, selected: settings.autoShowApps, ownBundleIdentifier: ownBundleIdentifier)
    }

    /// @note p0-201
    var canRemove: Bool {
        isEditable && AutoShowApp.contains(settings.autoShowApps, bundleIdentifier: selection)
    }

    /// @note p0-202
    func rows() -> [AutoShowAppRow] {
        settings.autoShowApps.map { app in
            AutoShowAppRow(
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                applicationURL: applicationURL(app.bundleIdentifier)
            )
        }
    }

    /// @note p0-203
    func refreshRunningApps() {
        runningApps = runningApplications.runningApplications()
    }

    /// @note p0-204
    func add(_ app: AutoShowApp) {
        guard !AutoShowApp.contains(settings.autoShowApps, bundleIdentifier: app.bundleIdentifier) else { return }
        settings.autoShowApps = AutoShowApp.normalized(settings.autoShowApps + [app])
    }

    /// @note p0-205
    func removeSelected() {
        guard canRemove, let selection else { return }
        settings.autoShowApps.removeAll { $0.bundleIdentifier == selection }
        self.selection = nil
    }

    /// @note p0-206
    @discardableResult
    func addApplication(at url: URL) -> Bool {
        guard let bundle = Bundle(url: url),
              let app = Self.app(
                  bundleIdentifier: bundle.bundleIdentifier,
                  // @note p0-207
                  displayName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                  bundleName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                  fileName: url.deletingPathExtension().lastPathComponent
              )
        else { return false }
        add(app)
        return true
    }

    // MARK: - 純粋関数(テストはここを見る)

    /// @note p0-208
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

    /// @note p0-209
    static func app(bundleIdentifier: String?, displayName: String?, bundleName: String?, fileName: String) -> AutoShowApp? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        let name = [displayName, bundleName].compactMap { $0 }.first { !$0.isEmpty } ?? fileName
        return AutoShowApp(bundleIdentifier: bundleIdentifier, name: name)
    }
}
