import XCTest

final class UpdateUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    @MainActor
    func testAC7_AC10_AC12_pendingUpdateFlow() throws {
        let app = XCUIApplication()
        launch(app)

        openMenu(in: app)
        let updateItem = menuItem(in: app, identifier: "menu.updateAvailable", title: "新しいバージョンがあります(9.9.9)")
        // AC-7
        XCTAssertTrue(updateItem.waitForExistence(timeout: timeout))
        let checkItem = menuItem(in: app, identifier: "menu.checkForUpdates", title: "アップデートを確認…")
        // AC-12
        XCTAssertTrue(checkItem.exists)

        let settingsItem = menuItem(in: app, identifier: "menu.settings", title: "設定")
        XCTAssertTrue(settingsItem.exists)
        clickShownMenuItem(settingsItem)
        XCTAssertTrue(element(in: app, identifier: "settings.sidebar.general").waitForExistence(timeout: timeout))

        let badge = element(in: app, identifier: "settings.sidebar.updateBadge")
        // AC-10
        XCTAssertTrue(badge.waitForExistence(timeout: timeout))

        let appInfo = element(in: app, identifier: "settings.sidebar.appInfo")
        XCTAssertTrue(appInfo.waitForExistence(timeout: timeout))
        appInfo.click()

        let status = element(in: app, identifier: "settings.appInfo.updateStatus")
        let toggle = element(in: app, identifier: "settings.appInfo.automaticUpdateToggle")
        let check = element(in: app, identifier: "settings.appInfo.checkForUpdates")
        app.revealInSettings(status)
        app.revealInSettings(toggle)
        // AC-12
        app.revealInSettings(check)
        XCTAssertTrue(check.isEnabled)

        let showUpdate = element(in: app, identifier: "settings.appInfo.showUpdate")
        app.revealInSettings(showUpdate)
        showUpdate.click()
        // AC-10
        XCTAssertTrue(status.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(badge.waitForNonExistence(timeout: timeout))

        closeSettings(in: app)

        openMenu(in: app)
        let reopenedCheckItem = menuItem(in: app, identifier: "menu.checkForUpdates", title: "アップデートを確認…")
        XCTAssertTrue(reopenedCheckItem.waitForExistence(timeout: timeout))
        // AC-7
        XCTAssertFalse(app.menuItems["menu.updateAvailable"].exists)
        XCTAssertFalse(app.menuItems["新しいバージョンがあります(9.9.9)"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - 起動

    @MainActor
    private func launch(_ app: XCUIApplication) {
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.untrusted
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        app.launchEnvironment["TATAKINOTE_UPDATE_OVERRIDE"] = "available"
        app.launch()
        app.dismissPermissionGuideIfPresent()
    }

    // MARK: - 要素の探し方

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
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
    private func clickShownMenuItem(_ item: XCUIElement) {
        let deadline = Date().addingTimeInterval(timeout)
        while item.frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(item.frame.isEmpty, "メニューが表示されていない(項目の枠が空)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        let window = app.windows.containing(.any, identifier: "settings.sidebar.general").firstMatch
        XCTAssertTrue(window.exists)
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(element(in: app, identifier: "settings.sidebar.general").waitForNonExistence(timeout: timeout))
    }

    @MainActor
    private func menuItem(in app: XCUIApplication, identifier: String, title: String) -> XCUIElement {
        let byIdentifier = app.menuItems[identifier]
        if byIdentifier.exists {
            return byIdentifier
        }
        return app.menuItems[title]
    }
}
