import XCTest

final class AutoShowSettingsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-1
    // AC-3
    // AC-10
    // AC-5
    // AC-8
    @MainActor
    func testAC1_AC3_AC5_AC8_AC10_autoShowSettingsScenario() throws {
        let app = XCUIApplication()
        launch(app)

        // AC-1
        openSettingsFromMenu(in: app)
        let modePicker = element(in: app, identifier: "settings.autoShowModePicker")
        XCTAssertTrue(modePicker.waitForExistence(timeout: timeout))
        let off = app.radioButtons["オフ"]
        let allApps = app.radioButtons["全アプリ"]
        let selectedApps = app.radioButtons["選んだアプリのみ"]
        XCTAssertTrue(off.waitForExistence(timeout: timeout))
        XCTAssertTrue(allApps.exists)
        XCTAssertTrue(selectedApps.exists)
        XCTAssertTrue(isChecked(off))
        XCTAssertFalse(isChecked(allApps))
        XCTAssertFalse(isChecked(selectedApps))

        let list = element(in: app, identifier: "settings.autoShowAppList")
        let addButton = element(in: app, identifier: "settings.autoShowAppAdd")
        let removeButton = element(in: app, identifier: "settings.autoShowAppRemove")
        XCTAssertTrue(list.exists)
        XCTAssertTrue(addButton.exists)
        XCTAssertTrue(removeButton.exists)
        XCTAssertEqual(rowCount(in: list), 0)
        XCTAssertFalse(addButton.isEnabled)
        XCTAssertFalse(removeButton.isEnabled)

        selectedApps.click()
        XCTAssertTrue(isChecked(selectedApps))
        XCTAssertFalse(isChecked(off))
        XCTAssertTrue(waitUntil { addButton.isEnabled })
        XCTAssertFalse(removeButton.isEnabled)

        // AC-3
        try addFirstRunningApp(in: app, addButton: addButton)
        XCTAssertTrue(waitUntil { self.rowCount(in: list) == 1 })

        // AC-10
        XCTAssertFalse(removeButton.isEnabled)

        // AC-5
        firstRow(in: list).click()
        XCTAssertTrue(waitUntil { removeButton.isEnabled })
        removeButton.click()
        XCTAssertTrue(waitUntil { self.rowCount(in: list) == 0 })
        XCTAssertFalse(removeButton.isEnabled)

        // AC-8
        try addFirstRunningApp(in: app, addButton: addButton)
        XCTAssertTrue(waitUntil { self.rowCount(in: list) == 1 })
        allApps.click()
        XCTAssertTrue(isChecked(allApps))
        XCTAssertFalse(isChecked(selectedApps))
        XCTAssertTrue(waitUntil { !addButton.isEnabled })
        XCTAssertEqual(rowCount(in: list), 1)
        XCTAssertFalse(removeButton.isEnabled)

        closeSettings(in: app, picker: modePicker)
    }

    @MainActor
    private func launch(_ app: XCUIApplication) {
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.untrusted
        app.launch()
        app.dismissPermissionGuideIfPresent()
    }

    // MARK: - 対象のアプリの一覧

    @MainActor
    private func rowCount(in list: XCUIElement) -> Int {
        let cells = list.cells.count
        return cells > 0 ? cells : list.staticTexts.count
    }

    @MainActor
    private func firstRow(in list: XCUIElement) -> XCUIElement {
        let cell = list.cells.firstMatch
        return cell.exists ? cell : list.staticTexts.firstMatch
    }

    @MainActor
    private func addFirstRunningApp(in app: XCUIApplication, addButton: XCUIElement) throws {
        XCTAssertTrue(addButton.isEnabled)
        addButton.click()
        let candidate = try XCTUnwrap(
            firstCandidate(in: app, addButton: addButton),
            "「＋」の候補(起動中のアプリ)が無い。候補が無い環境では手動テストで確かめる"
        )
        clickShownMenuItem(candidate)
    }

    @MainActor
    private func firstCandidate(in app: XCUIApplication, addButton: XCUIElement) -> XCUIElement? {
        let otherTitle = "その他…"
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let fromButton = addButton.descendants(matching: .menuItem).allElementsBoundByIndex
            if let item = firstCandidate(among: fromButton, excluding: otherTitle) {
                return item
            }
            let openMenu = app.menus.containing(NSPredicate(format: "title == %@", otherTitle)).firstMatch
            if openMenu.exists, let item = firstCandidate(among: openMenu.menuItems.allElementsBoundByIndex, excluding: otherTitle) {
                return item
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return nil
    }

    @MainActor
    private func firstCandidate(among items: [XCUIElement], excluding otherTitle: String) -> XCUIElement? {
        items.first { !$0.title.isEmpty && $0.title != otherTitle }
    }

    // MARK: - 要素の探し方(SettingsUITests から写したもの)

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func isChecked(_ radioButton: XCUIElement) -> Bool {
        if let value = radioButton.value as? NSNumber {
            return value.boolValue
        }
        return radioButton.isSelected
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    @MainActor
    private func closeSettings(in app: XCUIApplication, picker: XCUIElement) {
        let window = app.windows.containing(.any, identifier: "settings.autoShowModePicker").firstMatch
        XCTAssertTrue(window.exists)
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(picker.waitForNonExistence(timeout: timeout))
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
    private func openSettingsFromMenu(in app: XCUIApplication) {
        openMenu(in: app)
        let item = menuItem(in: app, identifier: "menu.settings", title: "設定")
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        clickShownMenuItem(item)
        app.revealInSettings(element(in: app, identifier: "settings.autoShowAppRemove"))
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
