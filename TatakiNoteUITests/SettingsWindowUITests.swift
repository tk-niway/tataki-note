import XCTest

// @note p0-1438
final class SettingsWindowUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    /// @note p0-1439
    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-1
    // @note p0-1440
    // AC-2
    // @note p0-1441
    // AC-3
    // @note p0-1442
    @MainActor
    func testAC1_AC2_AC3_generalSection() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let general = element(in: app, identifier: sidebarGeneralID)
        XCTAssertTrue(general.waitForExistence(timeout: timeout))
        // AC-1
        // @note p0-1443
        XCTAssertTrue(waitUntil { general.isHittable }, "設定画面が手前に開いていない(サイドバーの「一般」が押せない)")
        // AC-2
        // @note p0-1444
        XCTAssertTrue(isSidebarItemSelected(sidebarGeneralID, in: app))

        // @note p0-1445
        XCTAssertTrue(hotkeyRecorder(in: app).exists)
        for identifier in generalIdentifiers {
            XCTAssertTrue(element(in: app, identifier: identifier).exists, identifier)
        }
        XCTAssertTrue(app.descendants(matching: .any)["パネルを出す位置"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["パネルを出す画面"].firstMatch.exists)
        XCTAssertTrue(element(in: app, identifier: quitID).exists)

        // AC-1
        // @note p0-1446
        let hideIcon = element(in: app, identifier: hideMenuBarIconToggleID)
        app.revealInSettings(hideIcon)
        XCTAssertTrue(hideIcon.isHittable)

        // AC-2
        // @note p0-1447
        openSettingsFromMenu(in: app)
        XCTAssertTrue(general.waitForExistence(timeout: timeout))
        XCTAssertEqual(app.windows.containing(.any, identifier: themePickerID).count, 1)

        // AC-2
        // @note p0-1448
        closeSettings(in: app)
        openSettingsFromMenu(in: app)
        XCTAssertTrue(general.waitForExistence(timeout: timeout))
        XCTAssertTrue(isSidebarItemSelected(sidebarGeneralID, in: app))
        XCTAssertEqual(app.windows.containing(.any, identifier: themePickerID).count, 1)
        closeSettings(in: app)
    }

    // AC-5
    // @note p0-1449
    @MainActor
    func testAC5_themeScenario() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let themePicker = element(in: app, identifier: themePickerID)
        app.revealInSettings(themePicker)

        let system = radio("システム", inPicker: themePickerID, in: app)
        let light = radio("ライト", inPicker: themePickerID, in: app)
        let dark = radio("ダーク", inPicker: themePickerID, in: app)
        XCTAssertTrue(system.waitForExistence(timeout: timeout))
        XCTAssertTrue(light.exists)
        XCTAssertTrue(dark.exists)
        XCTAssertEqual(themePicker.radioButtons.count, 3)
        XCTAssertTrue(isChecked(system))
        XCTAssertFalse(isChecked(light))
        XCTAssertFalse(isChecked(dark))

        // @note p0-1450
        dark.click()
        XCTAssertTrue(isChecked(dark))
        XCTAssertFalse(isChecked(system))
        XCTAssertFalse(isChecked(light))

        closeSettings(in: app)
    }

    // AC-5
    // @note p0-1452
    @MainActor
    func testAC5_rightPaddingScenario() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let scrollView = element(in: app, identifier: "settings.detailScrollView")
        XCTAssertTrue(scrollView.waitForExistence(timeout: timeout))

        let panelScreenPicker = element(in: app, identifier: "settings.panelScreenPicker")
        app.revealInSettings(panelScreenPicker)
        assertRightEdgeHasTrailingPadding(panelScreenPicker, scrollView: scrollView)

        let editor = element(in: app, identifier: sidebarEditorID)
        editor.click()
        let fontPicker = element(in: app, identifier: "settings.fontPicker")
        app.revealInSettings(fontPicker)
        assertRightEdgeHasTrailingPadding(fontPicker, scrollView: scrollView)

        let appInfo = element(in: app, identifier: sidebarAppInfoID)
        appInfo.click()
        let version = element(in: app, identifier: "settings.appInfo.version")
        app.revealInSettings(version)
        assertRightEdgeHasTrailingPadding(version, scrollView: scrollView)

        closeSettings(in: app)
    }

    // AC-7
    // @note p0-1453
    @MainActor
    func testAC7_launchAtLoginScenario() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let toggle = element(in: app, identifier: launchAtLoginToggleID)
        app.revealInSettings(toggle)
        XCTAssertFalse(isChecked(toggle))
        // @note p0-1454
        XCTAssertFalse(element(in: app, identifier: "settings.launchAtLoginOpenSettings").exists)
        XCTAssertFalse(element(in: app, identifier: "settings.launchAtLoginError").exists)

        // @note p0-1455
        toggle.click()
        XCTAssertTrue(waitUntil { self.isChecked(toggle) })
        XCTAssertFalse(element(in: app, identifier: "settings.launchAtLoginError").exists)

        // @note p0-1456
        closeSettings(in: app)
        openSettingsFromMenu(in: app)
        let toggleAfterReopen = element(in: app, identifier: launchAtLoginToggleID)
        app.revealInSettings(toggleAfterReopen)
        XCTAssertTrue(isChecked(toggleAfterReopen))

        closeSettings(in: app)
    }

    // AC-9
    // @note p0-1458
    // AC-11
    // @note p0-1459
    @MainActor
    func testAC9_AC11_hideMenuBarIconScenario() throws {
        let app = XCUIApplication()
        launch(app)

        // @note p0-1460
        XCTAssertTrue(waitUntil { self.isMenuBarIconShown(in: app) })
        openSettingsFromMenu(in: app)
        let toggle = element(in: app, identifier: hideMenuBarIconToggleID)
        app.revealInSettings(toggle)
        XCTAssertFalse(isChecked(toggle))

        toggle.click()
        XCTAssertTrue(waitUntil { self.isChecked(toggle) })
        // @note p0-1461
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertNotEqual(app.state, .notRunning, "アイコンを隠すとアプリが終了した")
        XCTAssertTrue(settingsWindow(in: app).exists, "アイコンを隠すと設定画面が閉じた")

        // @note p0-1462
        XCTAssertTrue(waitUntil { !self.isMenuBarIconShown(in: app) }, "アイコンが消えない")

        // @note p0-1463
        toggle.click()
        XCTAssertTrue(waitUntil { !self.isChecked(toggle) })
        XCTAssertTrue(waitUntil { self.isMenuBarIconShown(in: app) }, "アイコンが戻らない")

        // @note p0-1464
        toggle.click()
        XCTAssertTrue(waitUntil { self.isChecked(toggle) })
        XCTAssertTrue(waitUntil { !self.isMenuBarIconShown(in: app) })
        element(in: app, identifier: quitID).click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: timeout))

        // AC-11
        // @note p0-1465
        launch(app, dismissingPermissionGuide: false)
        XCTAssertTrue(element(in: app, identifier: "permissionGuide.status").waitForExistence(timeout: timeout))
        app.dismissPermissionGuideIfPresent()

        // @note p0-1466
        XCTAssertFalse(waitUntil(timeout: 2) { self.isMenuBarIconShown(in: app) }, "隠したまま起動し直したのにアイコンが出た")
        app.terminate()
    }

    // AC-4
    // @note p0-1467
    @MainActor
    func testAC4_quitButton() throws {
        let app = XCUIApplication()
        launch(app)
        XCTAssertTrue(waitUntil { self.isMenuBarIconShown(in: app) })

        openSettingsFromMenu(in: app)
        let quit = element(in: app, identifier: quitID)
        XCTAssertTrue(quit.waitForExistence(timeout: timeout))
        quit.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: timeout))
    }

    // AC-14
    // @note p0-1468
    @MainActor
    func testAC14_sidebarCannotCollapse() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let general = element(in: app, identifier: sidebarGeneralID)
        let quit = element(in: app, identifier: quitID)
        XCTAssertTrue(general.waitForExistence(timeout: timeout))

        // @note p0-1469
        let window = settingsWindow(in: app)
        let splitter = window.splitters.firstMatch
        if splitter.exists {
            let from = splitter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            from.press(forDuration: 0.3, thenDragTo: to)
            // @note p0-1470
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(general.isHittable, "サイドバーが畳まれた(「一般」が押せない)")
        XCTAssertTrue(quit.isHittable, "サイドバーが畳まれた(「TatakiNote を終了」が押せない)")

        // @note p0-1471
        closeSettings(in: app)
        openSettingsFromMenu(in: app)
        XCTAssertTrue(general.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { general.isHittable }, "開き直すとサイドバーが畳まれていた(「一般」が押せない)")
        XCTAssertTrue(quit.isHittable, "開き直すとサイドバーが畳まれていた(「TatakiNote を終了」が押せない)")
        closeSettings(in: app)
    }

    // AC-15
    // @note p0-1472
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
        // @note p0-1473
        if shownTitles.count == expectedTitles.count {
            XCTAssertEqual(shownTitles, expectedTitles)
        }

        // @note p0-1474
        XCTAssertFalse(app.menuItems["権限の状態…"].exists)
        XCTAssertFalse(app.menuItems["menu.permission"].exists)
        XCTAssertFalse(app.menuItems["設定…"].exists)

        // @note p0-1475
        clickShownMenuItem(settingsItem)
        XCTAssertTrue(element(in: app, identifier: sidebarGeneralID).waitForExistence(timeout: timeout))
        closeSettings(in: app)
    }

    // MARK: - 起動

    /// @note p0-1476
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
    private let sidebarEditorID = "settings.sidebar.editor"
    private let sidebarAppInfoID = "settings.sidebar.appInfo"
    private let quitID = "settings.quit"
    /// @note p0-1477
    private let settingsDetailTrailingPadding: CGFloat = 36
    private let themePickerID = "settings.themePicker"
    private let launchAtLoginToggleID = "settings.launchAtLoginToggle"
    private let hideMenuBarIconToggleID = "settings.hideMenuBarIconToggle"

    /// @note p0-1478
    private var generalIdentifiers: [String] {
        [
            "settings.commitKeyRecorder",
            "settings.commitAndSendKeyRecorder",
            "settings.panelScreenPicker",
            "settings.autoShowModePicker",
            "settings.autoShowAppList",
            themePickerID,
            launchAtLoginToggleID,
            hideMenuBarIconToggleID,
        ]
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// @note p0-1479
    @MainActor
    private func radio(_ title: String, inPicker identifier: String, in app: XCUIApplication) -> XCUIElement {
        element(in: app, identifier: identifier).radioButtons[title]
    }

    /// @note p0-1480
    @MainActor
    private func isChecked(_ element: XCUIElement) -> Bool {
        if let value = element.value as? NSNumber {
            return value.boolValue
        }
        return element.isSelected
    }

    /// @note p0-1481
    @MainActor
    private func isSidebarItemSelected(_ identifier: String, in app: XCUIApplication) -> Bool {
        if element(in: app, identifier: identifier).isSelected {
            return true
        }
        let containers = [
            app.outlineRows.containing(.any, identifier: identifier).firstMatch,
            app.tableRows.containing(.any, identifier: identifier).firstMatch,
            app.cells.containing(.any, identifier: identifier).firstMatch,
        ]
        return containers.contains { $0.exists && $0.isSelected }
    }

    // @note p0-1482
    @MainActor
    private func hotkeyRecorder(in app: XCUIApplication) -> XCUIElement {
        let byIdentifier = element(in: app, identifier: "settings.hotkeyRecorder")
        if byIdentifier.waitForExistence(timeout: timeout) {
            return byIdentifier
        }
        let byLabel = app.descendants(matching: .any)["パネルを開く・閉じる"].firstMatch
        if byLabel.exists {
            return byLabel
        }
        let notCommitRecorders = NSPredicate(
            format: "identifier != %@ AND identifier != %@", "settings.commitKeyRecorder", "settings.commitAndSendKeyRecorder"
        )
        return app.searchFields.matching(notCommitRecorders).firstMatch
    }

    /// @note p0-1483
    @MainActor
    private func assertRightEdgeHasTrailingPadding(
        _ element: XCUIElement,
        scrollView: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, file: file, line: line)
        let gap = scrollView.frame.maxX - element.frame.maxX
        XCTAssertGreaterThanOrEqual(gap, settingsDetailTrailingPadding, "余白が狭い(\(gap)pt)", file: file, line: line)
    }

    /// @note p0-1484
    @MainActor
    private func settingsWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.containing(.any, identifier: sidebarGeneralID).firstMatch
    }

    /// @note p0-1485
    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        let window = settingsWindow(in: app)
        XCTAssertTrue(window.exists)
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(element(in: app, identifier: sidebarGeneralID).waitForNonExistence(timeout: timeout))
    }

    /// @note p0-1486
    @MainActor
    private func waitUntil(timeout: TimeInterval? = nil, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout ?? self.timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    // MARK: - メニューバー

    /// @note p0-1487
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

    // @note p0-1488
    @MainActor
    private func clickShownMenuItem(_ item: XCUIElement) {
        let deadline = Date().addingTimeInterval(timeout)
        while item.frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(item.frame.isEmpty, "メニューが表示されていない(項目の枠が空)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    // @note p0-1489
    @MainActor
    private func menuItem(in app: XCUIApplication, identifier: String, title: String) -> XCUIElement {
        let byIdentifier = app.menuItems[identifier]
        if byIdentifier.exists {
            return byIdentifier
        }
        return app.menuItems[title]
    }
}
