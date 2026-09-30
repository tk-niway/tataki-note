import AppKit
import Foundation
import Testing
@testable import TatakiNote

/// @note p0-763
@MainActor
final class StubRunningApplications: RunningApplicationsProviding {
    var apps: [AutoShowApp]

    init(apps: [AutoShowApp] = []) {
        self.apps = apps
    }

    func runningApplications() -> [AutoShowApp] {
        apps
    }
}

@MainActor
struct AutoShowAppsEditorTests {
    private let ownBundleIdentifier = "com.example.tatakinote"
    private let own = AutoShowApp(bundleIdentifier: "com.example.tatakinote", name: "TatakiNote")
    private let chatmate = AutoShowApp(bundleIdentifier: "com.example.chatmate", name: "Chatmate")
    private let notes = AutoShowApp(bundleIdentifier: "com.example.notes", name: "Notes")
    private let browser = AutoShowApp(bundleIdentifier: "com.example.browser", name: "Browser")

    /// @note p0-764
    private func makeSuite() throws -> (UserDefaults, String) {
        let name = UUID().uuidString
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    private func removeSuite(_ defaults: UserDefaults, name: String) {
        defaults.removePersistentDomain(forName: name)
    }

    /// @note p0-765
    private func makeEditor(
        settings: AppSettings,
        running: StubRunningApplications,
        notificationCenter: NotificationCenter
    ) -> AutoShowAppsEditor {
        AutoShowAppsEditor(
            settings: settings,
            runningApplications: running,
            applicationURL: { _ in nil },
            ownBundleIdentifier: ownBundleIdentifier,
            notificationCenter: notificationCenter
        )
    }

    /// @note p0-766
    private func savedApps(in defaults: UserDefaults) -> [AutoShowApp] {
        AppSettings(store: SettingsStore(defaults: defaults)).autoShowApps
    }

    // MARK: - AC-3

    @Test("AC-3: 「＋」の候補から1件足すと、一覧に入って保存され、候補からは消える")
    func addingCandidateAddsAndSaves() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowMode = .selectedApps
        let editor = makeEditor(
            settings: settings,
            running: StubRunningApplications(apps: [notes, chatmate]),
            notificationCenter: NotificationCenter()
        )

        let candidate = try #require(editor.candidates.first)
        #expect(candidate == chatmate)
        editor.add(candidate)

        #expect(settings.autoShowApps == [chatmate])
        #expect(savedApps(in: defaults) == [chatmate])
        #expect(editor.candidates == [notes])

        // @note p0-767
        editor.add(notes)
        #expect(settings.autoShowApps == [chatmate, notes])
        #expect(savedApps(in: defaults) == [chatmate, notes])
        #expect(editor.candidates.isEmpty)
    }

    // MARK: - AC-4

    @Test("AC-4: 候補に TatakiNote 自身は出ない(自分の bundle identifier が nil なら除かない)")
    func candidatesExcludeOwnApp() {
        let running = [own, chatmate]
        #expect(AutoShowAppsEditor.candidates(running: running, selected: [], ownBundleIdentifier: ownBundleIdentifier) == [chatmate])
        #expect(AutoShowAppsEditor.candidates(running: running, selected: [], ownBundleIdentifier: nil) == [chatmate, own])
    }

    @Test("AC-4: 候補にすでに選んだアプリは出ない")
    func candidatesExcludeSelectedApps() {
        let candidates = AutoShowAppsEditor.candidates(
            running: [chatmate, notes, browser],
            selected: [notes],
            ownBundleIdentifier: ownBundleIdentifier
        )
        #expect(candidates == [browser, chatmate])
    }

    @Test("AC-4: 同じ bundle identifier のアプリは候補に1件だけ出る(空の bundle identifier は出ない)")
    func candidatesAreDeduplicated() {
        let candidates = AutoShowAppsEditor.candidates(
            running: [
                chatmate,
                AutoShowApp(bundleIdentifier: "com.example.chatmate", name: "Chatmate 2"),
                AutoShowApp(bundleIdentifier: "", name: "Nameless"),
            ],
            selected: [],
            ownBundleIdentifier: ownBundleIdentifier
        )
        #expect(candidates == [chatmate])
    }

    @Test("AC-4: 候補は名前順(localizedStandardCompare)に並び、名前が同じなら bundle identifier の順")
    func candidatesAreSortedByName() {
        // @note p0-768
        let running = [
            AutoShowApp(bundleIdentifier: "com.example.b", name: "b"),
            AutoShowApp(bundleIdentifier: "com.example.app10", name: "App 10"),
            AutoShowApp(bundleIdentifier: "com.example.a", name: "A"),
            AutoShowApp(bundleIdentifier: "com.example.app2", name: "App 2"),
        ]
        let candidates = AutoShowAppsEditor.candidates(running: running, selected: [], ownBundleIdentifier: ownBundleIdentifier)
        #expect(candidates.map(\.name) == ["A", "App 2", "App 10", "b"])

        let sameName = [
            AutoShowApp(bundleIdentifier: "com.example.z", name: "Same"),
            AutoShowApp(bundleIdentifier: "com.example.m", name: "Same"),
        ]
        let sameNameCandidates = AutoShowAppsEditor.candidates(running: sameName, selected: [], ownBundleIdentifier: nil)
        #expect(sameNameCandidates.map(\.bundleIdentifier) == ["com.example.m", "com.example.z"])
    }

    @Test("AC-4: 起動中のアプリがすべて選択済み・起動中のアプリが無いときは、候補が空")
    func candidatesAreEmptyWhenNothingLeft() {
        #expect(AutoShowAppsEditor.candidates(running: [chatmate, notes], selected: [notes, chatmate], ownBundleIdentifier: ownBundleIdentifier).isEmpty)
        #expect(AutoShowAppsEditor.candidates(running: [own], selected: [], ownBundleIdentifier: ownBundleIdentifier).isEmpty)
        #expect(AutoShowAppsEditor.candidates(running: [], selected: [chatmate], ownBundleIdentifier: ownBundleIdentifier).isEmpty)
    }

    @Test("AC-4: モデルの候補は、起動中のアプリから自分と一覧のアプリを除いて名前順に並べたもの")
    func editorCandidatesUseRunningAppsAndSettings() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowApps = [browser]
        let editor = makeEditor(
            settings: settings,
            running: StubRunningApplications(apps: [own, notes, browser, chatmate]),
            notificationCenter: NotificationCenter()
        )

        #expect(editor.candidates == [chatmate, notes])
    }

    // MARK: - AC-5・AC-10

    @Test("AC-5, AC-10: 何も選んでいないと「−」は押せず、一覧の行を選ぶと押せる。一覧に無いものを選んでいても押せない")
    func canRemoveFollowsSelection() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowMode = .selectedApps
        settings.autoShowApps = [chatmate, notes]
        let editor = makeEditor(settings: settings, running: StubRunningApplications(), notificationCenter: NotificationCenter())

        #expect(editor.selection == nil)
        #expect(!editor.canRemove)

        editor.selection = notes.bundleIdentifier
        #expect(editor.canRemove)

        editor.selection = "com.example.notinlist"
        #expect(!editor.canRemove)
    }

    @Test("AC-5, AC-10: 「−」で選んだ行を外すと保存された一覧からも消え、選択が外れて「−」は押せなくなる")
    func removeSelectedRemovesAndSaves() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowMode = .selectedApps
        settings.autoShowApps = [chatmate, notes, browser]
        let editor = makeEditor(settings: settings, running: StubRunningApplications(), notificationCenter: NotificationCenter())

        editor.selection = notes.bundleIdentifier
        editor.removeSelected()

        #expect(settings.autoShowApps == [chatmate, browser])
        #expect(savedApps(in: defaults) == [chatmate, browser])
        #expect(editor.selection == nil)
        #expect(!editor.canRemove)
    }

    @Test("AC-5, AC-10: 「−」を押せないときに removeSelected を呼んでも一覧は変わらない")
    func removeSelectedDoesNothingWhenNotRemovable() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowMode = .selectedApps
        settings.autoShowApps = [chatmate, notes]
        let editor = makeEditor(settings: settings, running: StubRunningApplications(), notificationCenter: NotificationCenter())

        // @note p0-769
        editor.removeSelected()
        #expect(settings.autoShowApps == [chatmate, notes])

        // @note p0-770
        editor.selection = "com.example.notinlist"
        editor.removeSelected()
        #expect(settings.autoShowApps == [chatmate, notes])
        #expect(savedApps(in: defaults) == [chatmate, notes])
    }

    // MARK: - AC-6

    @Test("AC-6: 同じアプリを2回足しても一覧は1件のままで、先に足したアプリの位置も変わらない")
    func addingSameAppTwiceKeepsOne() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowMode = .selectedApps
        let editor = makeEditor(settings: settings, running: StubRunningApplications(), notificationCenter: NotificationCenter())

        editor.add(chatmate)
        editor.add(notes)
        editor.add(chatmate)
        // @note p0-771
        editor.add(AutoShowApp(bundleIdentifier: "com.example.chatmate", name: "Chatmate 2"))

        #expect(settings.autoShowApps == [chatmate, notes])
        #expect(savedApps(in: defaults) == [chatmate, notes])
    }

    // MARK: - AC-7

    @Test("AC-7: .app の中身から作るとき、bundle identifier が nil か空ならアプリにならない")
    func appRequiresBundleIdentifier() {
        #expect(AutoShowAppsEditor.app(bundleIdentifier: nil, displayName: "Calc", bundleName: "Calc", fileName: "Calc") == nil)
        #expect(AutoShowAppsEditor.app(bundleIdentifier: "", displayName: "Calc", bundleName: "Calc", fileName: "Calc") == nil)
    }

    @Test("AC-7: 名前は CFBundleDisplayName → CFBundleName → ファイル名の順(空文字は無いものとみなす)")
    func appNameFallsBack() {
        let bundleIdentifier = "com.example.calc"
        #expect(
            AutoShowAppsEditor.app(bundleIdentifier: bundleIdentifier, displayName: "Display", bundleName: "Bundle", fileName: "File")
                == AutoShowApp(bundleIdentifier: bundleIdentifier, name: "Display")
        )
        #expect(
            AutoShowAppsEditor.app(bundleIdentifier: bundleIdentifier, displayName: nil, bundleName: "Bundle", fileName: "File")
                == AutoShowApp(bundleIdentifier: bundleIdentifier, name: "Bundle")
        )
        #expect(
            AutoShowAppsEditor.app(bundleIdentifier: bundleIdentifier, displayName: "", bundleName: "Bundle", fileName: "File")
                == AutoShowApp(bundleIdentifier: bundleIdentifier, name: "Bundle")
        )
        #expect(
            AutoShowAppsEditor.app(bundleIdentifier: bundleIdentifier, displayName: nil, bundleName: nil, fileName: "File")
                == AutoShowApp(bundleIdentifier: bundleIdentifier, name: "File")
        )
        #expect(
            AutoShowAppsEditor.app(bundleIdentifier: bundleIdentifier, displayName: "", bundleName: "", fileName: "File")
                == AutoShowApp(bundleIdentifier: bundleIdentifier, name: "File")
        )
    }

    @Test("AC-7: .app のファイルを足すと一覧に入り、同じものは1件のまま。アプリでないもの・bundle identifier の無いものは足さない")
    func addApplicationReadsBundle() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowMode = .selectedApps
        let editor = makeEditor(settings: settings, running: StubRunningApplications(), notificationCenter: NotificationCenter())

        let calc = try makeFakeApplication(
            named: "Calc",
            in: directory,
            info: ["CFBundleIdentifier": "com.example.calc", "CFBundleDisplayName": "Calc Display", "CFBundleName": "CalcBundle"]
        )
        #expect(editor.addApplication(at: calc))
        let expected = [AutoShowApp(bundleIdentifier: "com.example.calc", name: "Calc Display")]
        #expect(settings.autoShowApps == expected)
        #expect(savedApps(in: defaults) == expected)

        // @note p0-772
        #expect(editor.addApplication(at: calc))
        #expect(settings.autoShowApps == expected)

        // @note p0-773
        let plain = try makeFakeApplication(named: "Plain Tool", in: directory, info: ["CFBundleIdentifier": "com.example.plain"])
        #expect(editor.addApplication(at: plain))
        #expect(settings.autoShowApps.last == AutoShowApp(bundleIdentifier: "com.example.plain", name: "Plain Tool"))

        // @note p0-774
        let noIdentifier = try makeFakeApplication(named: "NoIdentifier", in: directory, info: ["CFBundleName": "NoIdentifier"])
        #expect(!editor.addApplication(at: noIdentifier))
        let emptyIdentifier = try makeFakeApplication(named: "EmptyIdentifier", in: directory, info: ["CFBundleIdentifier": ""])
        #expect(!editor.addApplication(at: emptyIdentifier))

        // @note p0-775
        #expect(!editor.addApplication(at: directory.appendingPathComponent("Missing.app", isDirectory: true)))

        #expect(settings.autoShowApps.map(\.bundleIdentifier) == ["com.example.calc", "com.example.plain"])
        #expect(savedApps(in: defaults).map(\.bundleIdentifier) == ["com.example.calc", "com.example.plain"])
    }

    /// @note p0-776
    private func makeFakeApplication(named name: String, in directory: URL, info: [String: String]) throws -> URL {
        let application = directory.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = application.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return application
    }

    // MARK: - AC-8

    @Test("AC-8: モードを「オフ」「全アプリ」にしても一覧は消えず操作できなくなり、「選んだアプリのみ」に戻すと元の一覧を操作できる")
    func changingModeKeepsList() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowMode = .selectedApps
        settings.autoShowApps = [chatmate, notes]
        let editor = makeEditor(settings: settings, running: StubRunningApplications(), notificationCenter: NotificationCenter())
        editor.selection = chatmate.bundleIdentifier
        #expect(editor.isEditable)
        #expect(editor.canRemove)

        settings.autoShowMode = .off
        #expect(settings.autoShowApps == [chatmate, notes])
        #expect(!editor.isEditable)
        #expect(!editor.canRemove)
        // @note p0-777
        editor.removeSelected()
        #expect(settings.autoShowApps == [chatmate, notes])

        settings.autoShowMode = .allApps
        #expect(settings.autoShowApps == [chatmate, notes])
        #expect(!editor.isEditable)
        #expect(!editor.canRemove)

        settings.autoShowMode = .selectedApps
        #expect(settings.autoShowApps == [chatmate, notes])
        #expect(savedApps(in: defaults) == [chatmate, notes])
        #expect(editor.isEditable)
        #expect(editor.canRemove)
    }

    // MARK: - AC-2

    @Test("AC-2: モードと一覧は、同じ suite で作り直した AppSettings・モデルでも残り、「全アプリ」なら一覧は編集できない")
    func modeAndListSurviveRecreation() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowMode = .allApps
        settings.autoShowApps = [chatmate]

        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        let editor = makeEditor(settings: reloaded, running: StubRunningApplications(), notificationCenter: NotificationCenter())
        #expect(reloaded.autoShowMode == .allApps)
        #expect(reloaded.autoShowApps == [chatmate])
        #expect(!editor.isEditable)
    }

    // MARK: - AC-9

    @Test("AC-9: アプリの場所が見つからなくても、行には保存された名前がそのまま出て、並びは一覧のまま")
    func rowsKeepSavedNamesWhenAppIsMissing() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        let missing = AutoShowApp(bundleIdentifier: "com.example.notinstalled", name: "消されたアプリ")
        settings.autoShowApps = [missing, chatmate]
        let editor = makeEditor(settings: settings, running: StubRunningApplications(), notificationCenter: NotificationCenter())

        let rows = editor.rows()
        #expect(rows == [
            AutoShowAppRow(bundleIdentifier: "com.example.notinstalled", name: "消されたアプリ", applicationURL: nil),
            AutoShowAppRow(bundleIdentifier: "com.example.chatmate", name: "Chatmate", applicationURL: nil),
        ])
        #expect(rows.map(\.id) == settings.autoShowApps.map(\.bundleIdentifier))
    }

    @Test("AC-9: アプリの場所が見つかっても、行の名前は保存された名前")
    func rowsUseSavedNamesWhenAppIsFound() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowApps = [chatmate]
        let location = URL(fileURLWithPath: "/Applications/Chatmate Renamed.app")
        let editor = AutoShowAppsEditor(
            settings: settings,
            runningApplications: StubRunningApplications(),
            applicationURL: { $0 == "com.example.chatmate" ? location : nil },
            ownBundleIdentifier: ownBundleIdentifier,
            notificationCenter: NotificationCenter()
        )

        #expect(editor.rows() == [AutoShowAppRow(bundleIdentifier: "com.example.chatmate", name: "Chatmate", applicationURL: location)])
    }

    // MARK: - AC-11

    @Test("AC-11: 起動中のアプリを取り直すと、あとから起動したアプリが候補に出て、終了したアプリは消える")
    func refreshUpdatesCandidates() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        let running = StubRunningApplications(apps: [notes])
        let editor = makeEditor(settings: settings, running: running, notificationCenter: NotificationCenter())
        #expect(editor.candidates == [notes])

        running.apps = [notes, chatmate]
        editor.refreshRunningApps()
        #expect(editor.candidates == [chatmate, notes])

        running.apps = [chatmate]
        editor.refreshRunningApps()
        #expect(editor.candidates == [chatmate])
    }

    @Test("AC-11: アプリの起動・終了の通知が届くと、起動中のアプリを取り直す")
    func workspaceNotificationsRefreshRunningApps() async throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        let running = StubRunningApplications(apps: [notes])
        let notificationCenter = NotificationCenter()
        let editor = makeEditor(settings: settings, running: running, notificationCenter: notificationCenter)
        #expect(editor.runningApps == [notes])

        running.apps = [notes, chatmate]
        notificationCenter.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        try await waitUntil { editor.runningApps == [notes, chatmate] }
        #expect(editor.runningApps == [notes, chatmate])
        #expect(editor.candidates == [chatmate, notes])

        running.apps = [chatmate]
        notificationCenter.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        try await waitUntil { editor.runningApps == [chatmate] }
        #expect(editor.runningApps == [chatmate])
        #expect(editor.candidates == [chatmate])
    }

    /// @note p0-778
    private func waitUntil(_ condition: () -> Bool) async throws {
        var attempts = 0
        while !condition() && attempts < 20 {
            try await Task.sleep(for: .milliseconds(50))
            attempts += 1
        }
    }
}
