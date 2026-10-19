import XCTest

final class DockAndQuitUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    private let sidebarGeneralID = "settings.sidebar.general"
    private let quitSettingsID = "settings.quit"
    private let launchAtLoginToggleID = "settings.launchAtLoginToggle"
    private let showMenuBarIconToggleID = "settings.showMenuBarIconToggle"
    private let showDockIconToggleID = "settings.showDockIconToggle"
    private let confirmQuitToggleID = "settings.confirmQuitToggle"
    private let clearHistoryID = "settings.clearHistory"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-12
    @MainActor
    func testAC12_opensPanelAfterLaunchOnlyWhenEnabled() throws {
        let app = makeApp()
        app.launchEnvironment["TATAKINOTE_OPEN_PANEL_ON_LAUNCH"] = "enabled"
        app.launch()

        let panel = app.dialogs["promptPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: timeout), "起動の後にパネルが開かない")
        let noTarget = element(in: app, identifier: "promptPanel.noInsertionTarget")
        XCTAssertTrue(noTarget.waitForExistence(timeout: timeout), "「挿入先なし」が出ない")
        XCTAssertEqual(noTarget.label, "挿入先なし")
        app.terminate()

        app.launchEnvironment["TATAKINOTE_OPEN_PANEL_ON_LAUNCH"] = nil
        app.launch()
        XCTAssertTrue(waitForStatusItem(in: app), "メニューバーのアイコンが出ない")
        XCTAssertFalse(app.dialogs["promptPanel"].waitForExistence(timeout: 2), "指定が無いのに起動の後にパネルが開いた")
        app.terminate()
    }

    // AC-18
    @MainActor
    func testAC18_quitKeyQuitsImmediatelyWhenOff() throws {
        let app = makeApp(seed: ["confirmsQuit": false])
        app.launch()

        openPanelFromMenu(in: app)
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForExistence(timeout: timeout))

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: timeout), "確かめの設定がオフなのに、⌘Q で終了しない")
    }

    // AC-19
    @MainActor
    func testAC19_menuAndButtonQuitWithoutConfirmation() throws {
        let app = makeApp()
        app.launch()

        openMenu(in: app)
        let quitItem = menuItem(in: app, identifier: "menu.quit", title: "終了")
        XCTAssertTrue(quitItem.waitForExistence(timeout: timeout))
        clickShownMenuItem(quitItem)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: timeout), "メニューの「終了」で終了しない")

        app.launch()
        openSettingsFromMenu(in: app)
        let quitButton = element(in: app, identifier: quitSettingsID)
        XCTAssertTrue(quitButton.waitForExistence(timeout: timeout))
        quitButton.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: timeout), "設定の「TatakiNote を終了」で終了しない")
    }

    // AC-27
    @MainActor
    func testAC27_startupToggles() throws {
        let app = makeApp(seed: ["showsDockIcon": false])
        app.launch()

        XCTAssertTrue(waitForStatusItem(in: app), "メニューバーのアイコンが出ない")
        openSettingsFromMenu(in: app)
        let launchToggle = element(in: app, identifier: launchAtLoginToggleID)
        let menuBarToggle = element(in: app, identifier: showMenuBarIconToggleID)
        let dockToggle = element(in: app, identifier: showDockIconToggleID)
        let confirmToggle = element(in: app, identifier: confirmQuitToggleID)
        let clearHistory = element(in: app, identifier: clearHistoryID)
        app.revealInSettings(clearHistory)
        app.revealInSettings(confirmToggle)
        app.revealInSettings(dockToggle)
        app.revealInSettings(menuBarToggle)
        app.revealInSettings(launchToggle)

        XCTAssertTrue(launchToggle.exists)
        XCTAssertGreaterThan(menuBarToggle.frame.minY, launchToggle.frame.minY, "「メニューバーにアイコンを表示」が「ログイン時に起動」より下に無い")
        XCTAssertGreaterThan(dockToggle.frame.minY, menuBarToggle.frame.minY, "「Dock にアイコンを表示」が「メニューバーにアイコンを表示」より下に無い")
        XCTAssertGreaterThan(confirmToggle.frame.minY, dockToggle.frame.minY, "「⌘Q で終了前に確認」が「Dock にアイコンを表示」より下に無い")
        XCTAssertLessThan(confirmToggle.frame.minY, clearHistory.frame.minY, "3つのスイッチが「履歴」より上に無い")
        XCTAssertTrue(isChecked(menuBarToggle), "アイコンが出ているのに「メニューバーにアイコンを表示」がオンに見えない")
        XCTAssertFalse(isChecked(dockToggle), "種でオフにした「Dock にアイコンを表示」がオンに見える")
        XCTAssertTrue(isChecked(confirmToggle), "「⌘Q で終了前に確認」がオンに見えない")

        app.revealInSettings(menuBarToggle)
        menuBarToggle.click()
        XCTAssertTrue(waitUntil { !self.isChecked(menuBarToggle) }, "「メニューバーにアイコンを表示」がオフにならない")
        XCTAssertTrue(waitUntil { !self.isMenuBarIconShown(in: app) }, "アイコンが消えない")
        XCTAssertNotEqual(app.state, .notRunning, "アイコンを表示しないとアプリが終了した")
        XCTAssertTrue(isSettingsWindowUsable(in: app), "アイコンを表示しないと設定ウィンドウが押せなくなった")

        menuBarToggle.click()
        XCTAssertTrue(waitUntil { self.isChecked(menuBarToggle) }, "「メニューバーにアイコンを表示」がオンに戻らない")
        XCTAssertTrue(waitUntil { self.isMenuBarIconShown(in: app) }, "アイコンが戻らない")

        app.revealInSettings(dockToggle)
        dockToggle.click()
        XCTAssertTrue(waitUntil { self.isChecked(dockToggle) }, "「Dock にアイコンを表示」がオンにならない")
        XCTAssertFalse(waitUntil(timeout: 1) { !self.isSettingsWindowUsable(in: app) }, "Dock のアイコンを表示すると設定ウィンドウが押せなくなった")

        dockToggle.click()
        XCTAssertTrue(waitUntil { !self.isChecked(dockToggle) }, "「Dock にアイコンを表示」がオフにならない")
        XCTAssertFalse(waitUntil(timeout: 1) { !self.isSettingsWindowUsable(in: app) }, "Dock のアイコンを消すと設定ウィンドウが押せなくなった")

        app.revealInSettings(confirmToggle)
        confirmToggle.click()
        XCTAssertTrue(waitUntil { !self.isChecked(confirmToggle) }, "「⌘Q で終了前に確認」がオフにならない")

        closeSettings(in: app)
    }

    // MARK: - 起動と要素の探し方

    @MainActor
    private func makeApp(seed: [String: Any]? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        if let seed, let data = try? JSONSerialization.data(withJSONObject: seed, options: [.sortedKeys]) {
            app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = String(decoding: data, as: UTF8.self)
        }
        return app
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func isChecked(_ element: XCUIElement) -> Bool {
        if let value = element.value as? NSNumber {
            return value.boolValue
        }
        return element.isSelected
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval? = nil, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout ?? self.timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    @MainActor
    private func isSettingsWindowUsable(in app: XCUIApplication) -> Bool {
        let general = element(in: app, identifier: sidebarGeneralID)
        return general.exists && general.isHittable
    }

    @MainActor
    private func isMenuBarIconShown(in app: XCUIApplication) -> Bool {
        app.statusItems.firstMatch.exists || app.menuBars.statusItems.firstMatch.exists
    }

    @MainActor
    private func waitForStatusItem(in app: XCUIApplication) -> Bool {
        if app.statusItems.firstMatch.waitForExistence(timeout: timeout) {
            return true
        }
        return app.menuBars.statusItems.firstMatch.waitForExistence(timeout: timeout)
    }

    @MainActor
    private func openMenu(in app: XCUIApplication) {
        var statusItem = app.statusItems.firstMatch
        if !statusItem.waitForExistence(timeout: timeout) {
            statusItem = app.menuBars.statusItems.firstMatch
        }
        XCTAssertTrue(statusItem.waitForExistence(timeout: timeout))
        statusItem.click()
    }

    @MainActor
    private func openPanelFromMenu(in app: XCUIApplication) {
        openMenu(in: app)
        let item = menuItem(in: app, identifier: "menu.openPanel", title: "パネルを開く")
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        clickShownMenuItem(item)
    }

    @MainActor
    private func openSettingsFromMenu(in app: XCUIApplication) {
        openMenu(in: app)
        let item = menuItem(in: app, identifier: "menu.settings", title: "設定")
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        clickShownMenuItem(item)
        XCTAssertTrue(element(in: app, identifier: sidebarGeneralID).waitForExistence(timeout: timeout))
    }

    @MainActor
    private func clickShownMenuItem(_ item: XCUIElement) {
        let deadline = Date().addingTimeInterval(timeout)
        while item.frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(item.frame.isEmpty, "メニューが表示されていない(項目の枠が空)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    @MainActor
    private func menuItem(in app: XCUIApplication, identifier: String, title: String) -> XCUIElement {
        let byIdentifier = app.menuItems[identifier]
        if byIdentifier.exists {
            return byIdentifier
        }
        return app.menuItems[title]
    }

    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        let window = app.windows.containing(.any, identifier: sidebarGeneralID).firstMatch
        XCTAssertTrue(window.exists)
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(element(in: app, identifier: sidebarGeneralID).waitForNonExistence(timeout: timeout))
    }
}
