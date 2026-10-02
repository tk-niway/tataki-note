import XCTest

final class TutorialUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-21
    @MainActor
    func testAC21_launchWithPermissionShowsTutorial() throws {
        let app = launchApp(permission: AccessibilityOverride.trusted, showsTutorial: true)

        XCTAssertTrue(tutorialWindow(in: app).waitForExistence(timeout: timeout), "チュートリアルの窓が開かない")
        XCTAssertTrue(element(in: app, identifier: "tutorial.practiceField").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(in: app, identifier: "tutorial.step.openPanel").exists)
        XCTAssertTrue(app.buttons["tutorial.skip"].exists)
        XCTAssertFalse(element(in: app, identifier: "permissionGuide.status").exists)
    }

    // AC-18
    @MainActor
    func testAC18_skipShowsNoticeAndCloseClosesWindow() throws {
        let app = launchApp(permission: AccessibilityOverride.trusted, showsTutorial: true)
        let window = tutorialWindow(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: timeout), "チュートリアルの窓が開かない")

        let skip = app.buttons["tutorial.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: timeout))
        skip.click()

        XCTAssertTrue(element(in: app, identifier: "tutorial.skipNotice").waitForExistence(timeout: timeout))
        XCTAssertFalse(skip.exists)
        let close = app.buttons["tutorial.skipNotice.close"]
        XCTAssertTrue(close.exists)
        close.click()

        XCTAssertTrue(window.waitForNonExistence(timeout: timeout), "「閉じる」で窓が閉じない")
    }

    // AC-5
    @MainActor
    func testAC5_untrustedGuideShowsNoteAndClosingDoesNotOpenTutorial() throws {
        let app = launchApp(permission: AccessibilityOverride.untrusted, showsTutorial: true)

        XCTAssertTrue(
            element(in: app, identifier: "permissionGuide.tutorialNote").waitForExistence(timeout: timeout),
            "初回起動の許可の案内に注記が出ない"
        )
        XCTAssertTrue(app.buttons["permissionGuide.openSystemSettings"].exists)
        let close = app.buttons["permissionGuide.close"]
        XCTAssertTrue(close.exists)
        close.click()

        XCTAssertTrue(close.waitForNonExistence(timeout: timeout), "許可の案内が閉じない")
        XCTAssertFalse(tutorialWindow(in: app).waitForExistence(timeout: 2), "閉じただけでチュートリアルが開いた")
    }

    // AC-20
    @MainActor
    func testAC20_openTutorialFromAppInfoSettings() throws {
        let app = launchApp(permission: AccessibilityOverride.trusted, showsTutorial: false)
        XCTAssertFalse(tutorialWindow(in: app).waitForExistence(timeout: 1), "抑止した起動でチュートリアルが開いた")

        openSettingsFromMenu(in: app)
        let appInfo = element(in: app, identifier: "settings.sidebar.appInfo")
        XCTAssertTrue(appInfo.waitForExistence(timeout: timeout))
        appInfo.click()

        let openTutorial = element(in: app, identifier: "settings.appInfo.openTutorial")
        app.revealInSettings(openTutorial)
        openTutorial.click()

        XCTAssertTrue(tutorialWindow(in: app).waitForExistence(timeout: timeout), "チュートリアルの窓が開かない")
        XCTAssertTrue(element(in: app, identifier: "tutorial.practiceField").waitForExistence(timeout: timeout))
    }

    // MARK: - 起動

    @MainActor
    private func launchApp(permission: String, showsTutorial: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = permission
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        if showsTutorial {
            app.launchEnvironment["TATAKINOTE_FIRST_LAUNCH_TUTORIAL"] = "enabled"
        }
        app.launch()
        return app
    }

    // MARK: - 要素の探し方

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func tutorialWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows["tutorial"]
    }

    // MARK: - メニューバー

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
    private func openSettingsFromMenu(in app: XCUIApplication) {
        openMenu(in: app)
        let item = menuItem(in: app, identifier: "menu.settings", title: "設定")
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        clickShownMenuItem(item)
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
}
