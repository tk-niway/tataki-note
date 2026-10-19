import XCTest

/// 下書き・履歴・タイトルバーの UI テストが共通で使う、起動とパネルの開き方。
class PanelDraftsUITestCase: XCTestCase {
    let timeout: TimeInterval = 5
    let tolerance: CGFloat = 3

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"
    private var dataDirectory: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TatakiNoteUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dataDirectory = directory
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
        if let dataDirectory {
            try? FileManager.default.removeItem(at: dataDirectory)
        }
    }

    // MARK: - 起動

    /// 履歴を書いた保存先と専用の設定で起動する。
    @MainActor
    func launchApp(history: [String] = [], showsTutorial: Bool = false, seed: [String: Any] = [:]) throws -> XCUIApplication {
        if !history.isEmpty {
            try writeHistory(history)
        }
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        if !seed.isEmpty {
            let data = try JSONSerialization.data(withJSONObject: seed, options: [.sortedKeys])
            app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = String(decoding: data, as: UTF8.self)
        }
        app.launchEnvironment["TATAKINOTE_DATA_DIRECTORY"] = dataDirectory?.path
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        if showsTutorial {
            app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
            app.launchEnvironment["TATAKINOTE_FIRST_LAUNCH_TUTORIAL"] = "enabled"
        }
        app.launch()
        return app
    }

    private func writeHistory(_ texts: [String]) throws {
        guard let dataDirectory else { return }
        let entries = texts.map { text -> [String: Any] in
            [
                "id": UUID().uuidString,
                "text": text,
                "insertedAt": "2026-10-06T05:32:00Z",
                "appName": "Notes",
            ]
        }
        let object: [String: Any] = ["version": 1, "history": entries]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: dataDirectory.appendingPathComponent("history.json"))
    }

    // MARK: - パネル

    /// メニューバーからパネルを開き、パネルの窓を返す。
    @MainActor
    func openPanel(in app: XCUIApplication) -> XCUIElement {
        openPanelFromMenu(in: app)
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForExistence(timeout: timeout))
        let panel = app.dialogs["promptPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: timeout), "パネルの窓が見つからない")
        return panel
    }

    @MainActor
    func textView(in app: XCUIApplication) -> XCUIElement {
        app.textViews["promptPanel.textView"]
    }

    @MainActor
    func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// サイドバーの一覧の行のうち、表示の文字に `text` を含むもの。
    @MainActor
    func row(in app: XCUIApplication, containing text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.descendants(matching: .any).matching(identifier: "sidebar.row").matching(predicate).firstMatch
    }

    @MainActor
    func openSidebar(in app: XCUIApplication) {
        let toggle = app.buttons["promptPanel.sidebarToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout))
        toggle.click()
        XCTAssertTrue(element(in: app, identifier: "sidebar.tab.drafts").waitForExistence(timeout: timeout), "サイドバーが開かない")
    }

    @MainActor
    func pressCommand(_ key: String, in app: XCUIApplication) {
        app.typeKey(key, modifierFlags: .command)
    }

    @MainActor
    func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    // MARK: - メニューバー

    @MainActor
    func openPanelFromMenu(in app: XCUIApplication) {
        var statusItem = app.statusItems.firstMatch
        if !statusItem.waitForExistence(timeout: timeout) {
            statusItem = app.menuBars.statusItems.firstMatch
        }
        XCTAssertTrue(statusItem.waitForExistence(timeout: timeout))
        statusItem.click()

        let byIdentifier = app.menuItems["menu.openPanel"]
        let item = byIdentifier.exists ? byIdentifier : app.menuItems["パネルを開く"]
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        let deadline = Date().addingTimeInterval(timeout)
        while item.frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(item.frame.isEmpty, "メニューが表示されていない(項目の枠が空)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }
}
