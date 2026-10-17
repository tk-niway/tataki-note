import XCTest

final class DockAndQuitUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    private let sidebarGeneralID = "settings.sidebar.general"
    private let quitSettingsID = "settings.quit"
    private let hideMenuBarIconToggleID = "settings.hideMenuBarIconToggle"
    private let showDockIconToggleID = "settings.showDockIconToggle"
    private let confirmQuitToggleID = "settings.confirmQuitToggle"
    private let clearHistoryID = "settings.clearHistory"
    private let confirmationID = "quitConfirmation"
    private let confirmationQuitID = "quitConfirmation.quit"
    private let confirmationCancelID = "quitConfirmation.cancel"
    private let confirmationSuppressID = "quitConfirmation.suppress"

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

    // AC-17
    @MainActor
    func testAC17_quitKeyShowsConfirmation() throws {
        let app = makeApp()
        app.launch()

        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        app.typeText("abc")
        XCTAssertEqual(textView.promptPanelText, "abc")

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(waitForConfirmation(in: app), "⌘Q で確かめの窓が出ない")
        XCTAssertTrue(element(in: app, identifier: confirmationQuitID).exists)
        XCTAssertTrue(element(in: app, identifier: confirmationCancelID).exists)
        let suppress = element(in: app, identifier: confirmationSuppressID)
        XCTAssertTrue(suppress.exists)
        XCTAssertFalse(isChecked(suppress), "「今後は確かめない」が最初からチェックされている")

        app.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(waitUntil { self.isChecked(suppress) }, "⌘D でチェックされない")
        app.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(waitUntil { !self.isChecked(suppress) }, "もう一度 ⌘D でチェックが外れない")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element(in: app, identifier: confirmationQuitID).waitForNonExistence(timeout: timeout), "esc で確かめの窓が閉じない")
        XCTAssertNotEqual(app.state, .notRunning, "キャンセルで終了した")
        XCTAssertTrue(textView.exists)

        app.typeText("d")
        XCTAssertEqual(textView.promptPanelText, "abcd")

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(waitForConfirmation(in: app), "もう一度 ⌘Q で確かめの窓が出ない")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.wait(for: .notRunning, timeout: timeout), "確かめの窓で ↩ を押しても終了しない")
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

    // AC-21
    @MainActor
    func testAC21_dockAndQuitToggles() throws {
        let app = makeApp(seed: ["showsDockIcon": false])
        app.launch()

        openSettingsFromMenu(in: app)
        let hideToggle = element(in: app, identifier: hideMenuBarIconToggleID)
        let dockToggle = element(in: app, identifier: showDockIconToggleID)
        let confirmToggle = element(in: app, identifier: confirmQuitToggleID)
        let clearHistory = element(in: app, identifier: clearHistoryID)
        app.revealInSettings(clearHistory)
        app.revealInSettings(dockToggle)
        app.revealInSettings(confirmToggle)

        XCTAssertTrue(hideToggle.exists)
        XCTAssertGreaterThan(dockToggle.frame.minY, hideToggle.frame.minY, "「Dock にアイコンを出す」が「メニューバーのアイコンを隠す」より下に無い")
        XCTAssertGreaterThan(confirmToggle.frame.minY, dockToggle.frame.minY, "「⌘Q で終了する前に確かめる」が「Dock にアイコンを出す」より下に無い")
        XCTAssertLessThan(confirmToggle.frame.minY, clearHistory.frame.minY, "2つのスイッチが「履歴」より上に無い")
        XCTAssertFalse(isChecked(dockToggle), "種でオフにした「Dock にアイコンを出す」がオンに見える")
        XCTAssertTrue(isChecked(confirmToggle), "「⌘Q で終了する前に確かめる」がオンに見えない")

        dockToggle.click()
        XCTAssertTrue(waitUntil { self.isChecked(dockToggle) }, "「Dock にアイコンを出す」がオンにならない")
        XCTAssertFalse(waitUntil(timeout: 1) { !self.isSettingsWindowUsable(in: app) }, "Dock のアイコンを出すと設定ウィンドウが押せなくなった")

        dockToggle.click()
        XCTAssertTrue(waitUntil { !self.isChecked(dockToggle) }, "「Dock にアイコンを出す」がオフにならない")
        XCTAssertFalse(waitUntil(timeout: 1) { !self.isSettingsWindowUsable(in: app) }, "Dock のアイコンを消すと設定ウィンドウが押せなくなった")

        confirmToggle.click()
        XCTAssertTrue(waitUntil { !self.isChecked(confirmToggle) }, "「⌘Q で終了する前に確かめる」がオフにならない")

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
    private func waitForConfirmation(in app: XCUIApplication) -> Bool {
        if app.windows[confirmationID].waitForExistence(timeout: timeout) {
            return true
        }
        return element(in: app, identifier: confirmationID).waitForExistence(timeout: 1)
    }

    @MainActor
    private func isSettingsWindowUsable(in app: XCUIApplication) -> Bool {
        let general = element(in: app, identifier: sidebarGeneralID)
        return general.exists && general.isHittable
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
