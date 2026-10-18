import XCTest

final class SettingsWindowUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-1
    // AC-2
    // AC-3
    @MainActor
    func testAC1_AC2_AC3_generalSection() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let general = element(in: app, identifier: sidebarGeneralID)
        XCTAssertTrue(general.waitForExistence(timeout: timeout))
        // AC-1
        XCTAssertTrue(waitUntil { general.isHittable }, "設定画面が手前に開いていない(サイドバーの「一般」が押せない)")
        // AC-2
        XCTAssertTrue(isSidebarItemSelected(sidebarGeneralID, in: app))

        XCTAssertTrue(element(in: app, identifier: quitID).exists)

        // AC-1
        let showIcon = element(in: app, identifier: showMenuBarIconToggleID)
        app.revealInSettings(showIcon)
        XCTAssertTrue(showIcon.isHittable)

        // AC-2
        openSettingsFromMenu(in: app)
        XCTAssertTrue(general.waitForExistence(timeout: timeout))
        XCTAssertEqual(app.windows.containing(.any, identifier: themePickerID).count, 1)
        closeSettings(in: app)
    }

    // AC-11
    @MainActor
    func testAC11_themeScenario() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let themePicker = element(in: app, identifier: themePickerID)
        app.revealInSettings(themePicker)

        let system = segment("システム", in: themePicker)
        let light = segment("ライト", in: themePicker)
        let dark = segment("ダーク", in: themePicker)
        XCTAssertTrue(system.waitForExistence(timeout: timeout))
        XCTAssertTrue(light.exists)
        XCTAssertTrue(dark.exists)
        XCTAssertTrue(isChecked(system))
        XCTAssertFalse(isChecked(light))
        XCTAssertFalse(isChecked(dark))

        dark.click()
        XCTAssertTrue(isChecked(dark))
        XCTAssertFalse(isChecked(system))
        XCTAssertFalse(isChecked(light))

        closeSettings(in: app)
    }

    // AC-12
    @MainActor
    func testAC12_menuBarIconToggleScenario() throws {
        let app = XCUIApplication()
        launch(app)

        XCTAssertTrue(waitUntil { self.isMenuBarIconShown(in: app) })
        openSettingsFromMenu(in: app)
        let toggle = element(in: app, identifier: showMenuBarIconToggleID)
        app.revealInSettings(toggle)
        XCTAssertTrue(isChecked(toggle))

        toggle.click()
        XCTAssertTrue(waitUntil { !self.isChecked(toggle) })
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertNotEqual(app.state, .notRunning, "アイコンを表示しないとアプリが終了した")
        XCTAssertTrue(settingsWindow(in: app).exists, "アイコンを表示しないと設定画面が閉じた")

        XCTAssertTrue(waitUntil { !self.isMenuBarIconShown(in: app) }, "アイコンが消えない")

        toggle.click()
        XCTAssertTrue(waitUntil { self.isChecked(toggle) })
        XCTAssertTrue(waitUntil { self.isMenuBarIconShown(in: app) }, "アイコンが戻らない")

        toggle.click()
        XCTAssertTrue(waitUntil { !self.isChecked(toggle) })
        XCTAssertTrue(waitUntil { !self.isMenuBarIconShown(in: app) })
        element(in: app, identifier: quitID).click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: timeout))

        launch(app, dismissingPermissionGuide: false)
        XCTAssertTrue(element(in: app, identifier: "permissionGuide.status").waitForExistence(timeout: timeout))
        app.dismissPermissionGuideIfPresent()

        XCTAssertFalse(waitUntil(timeout: 2) { self.isMenuBarIconShown(in: app) }, "表示しない設定のまま起動し直したのにアイコンが出た")
        app.terminate()
    }

    // AC-14
    @MainActor
    func testAC14_sidebarCannotCollapse() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let general = element(in: app, identifier: sidebarGeneralID)
        let quit = element(in: app, identifier: quitID)
        XCTAssertTrue(general.waitForExistence(timeout: timeout))

        let window = settingsWindow(in: app)
        let splitter = window.splitters.firstMatch
        if splitter.exists {
            let from = splitter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            from.press(forDuration: 0.3, thenDragTo: to)
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(general.isHittable, "サイドバーが畳まれた(「一般」が押せない)")
        XCTAssertTrue(quit.isHittable, "サイドバーが畳まれた(「TatakiNote を終了」が押せない)")

        closeSettings(in: app)
        openSettingsFromMenu(in: app)
        XCTAssertTrue(general.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { general.isHittable }, "開き直すとサイドバーが畳まれていた(「一般」が押せない)")
        XCTAssertTrue(quit.isHittable, "開き直すとサイドバーが畳まれていた(「TatakiNote を終了」が押せない)")
        closeSettings(in: app)
    }

    // AC-15
    @MainActor
    func testAC15_menuItems() throws {
        let app = XCUIApplication()
        launch(app)

        let statusItem = openMenu(in: app)
        let openPanelItem = menuItem(in: app, identifier: "menu.openPanel", title: "パネルを開く")
        XCTAssertTrue(openPanelItem.waitForExistence(timeout: timeout))
        let settingsItem = menuItem(in: app, identifier: "menu.settings", title: "設定")
        XCTAssertTrue(settingsItem.exists)
        XCTAssertTrue(menuItem(in: app, identifier: "menu.quit", title: "終了").exists)

        let expectedTitles = ["パネルを開く", "設定", "終了"]
        let shownTitles = statusItem.descendants(matching: .menuItem).allElementsBoundByIndex
            .map(\.title)
            .filter { expectedTitles.contains($0) }
        if shownTitles.count == expectedTitles.count {
            XCTAssertEqual(shownTitles, expectedTitles)
        }

        XCTAssertFalse(app.menuItems["権限の状態…"].exists)
        XCTAssertFalse(app.menuItems["menu.permission"].exists)
        XCTAssertFalse(app.menuItems["設定…"].exists)

        clickShownMenuItem(settingsItem)
        XCTAssertTrue(element(in: app, identifier: sidebarGeneralID).waitForExistence(timeout: timeout))
        closeSettings(in: app)
    }

    // MARK: - 起動

    @MainActor
    private func launch(_ app: XCUIApplication, dismissingPermissionGuide: Bool = true) {
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.untrusted
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        app.launch()
        if dismissingPermissionGuide {
            app.dismissPermissionGuideIfPresent()
        }
    }

    // MARK: - 設定画面の部品

    private let sidebarGeneralID = "settings.sidebar.general"
    private let quitID = "settings.quit"
    private let themePickerID = "settings.themePicker"
    private let showMenuBarIconToggleID = "settings.showMenuBarIconToggle"

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func segment(_ name: String, in picker: XCUIElement) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ OR title == %@", name, name)
        return picker.descendants(matching: .any).matching(predicate).firstMatch
    }

    @MainActor
    private func isChecked(_ element: XCUIElement) -> Bool {
        if let value = element.value as? NSNumber {
            return value.boolValue
        }
        return element.isSelected
    }

    @MainActor
    private func isSidebarItemSelected(_ identifier: String, in app: XCUIApplication) -> Bool {
        element(in: app, identifier: identifier).isSelected
    }

    @MainActor
    private func settingsWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.containing(.any, identifier: sidebarGeneralID).firstMatch
    }

    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        let window = settingsWindow(in: app)
        XCTAssertTrue(window.exists)
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(element(in: app, identifier: sidebarGeneralID).waitForNonExistence(timeout: timeout))
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval? = nil, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout ?? self.timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    // MARK: - メニューバー

    @MainActor
    private func isMenuBarIconShown(in app: XCUIApplication) -> Bool {
        app.statusItems.firstMatch.exists || app.menuBars.statusItems.firstMatch.exists
    }

    @MainActor
    @discardableResult
    private func openMenu(in app: XCUIApplication) -> XCUIElement {
        var statusItem = app.statusItems.firstMatch
        if !statusItem.waitForExistence(timeout: timeout) {
            statusItem = app.menuBars.statusItems.firstMatch
        }
        XCTAssertTrue(statusItem.waitForExistence(timeout: timeout))
        statusItem.click()
        return statusItem
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
