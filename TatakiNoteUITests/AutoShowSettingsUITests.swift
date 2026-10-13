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

    // AC-22
    // AC-23
    // AC-24
    // AC-25
    @MainActor
    func testAC22_AC23_AC24_AC25_autoShowSettingsScenario() throws {
        let app = XCUIApplication()
        launch(app)

        // AC-22
        openSettingsFromMenu(in: app)
        element(in: app, identifier: "settings.sidebar.general").click()
        XCTAssertFalse(element(in: app, identifier: "settings.autoShowModePicker").exists)
        XCTAssertFalse(element(in: app, identifier: "settings.autoShowAppList").exists)
        element(in: app, identifier: "settings.sidebar.keys").click()
        let modePicker = element(in: app, identifier: "settings.autoShowModePicker")
        XCTAssertTrue(modePicker.waitForExistence(timeout: timeout))
        app.revealInSettings(modePicker)
        let off = segment("オフ", in: modePicker)
        let allApps = segment("全アプリ", in: modePicker)
        let selectedApps = segment("選んだアプリのみ", in: modePicker)
        XCTAssertTrue(off.waitForExistence(timeout: timeout))
        XCTAssertTrue(allApps.exists)
        XCTAssertTrue(selectedApps.exists)
        XCTAssertTrue(isChecked(off))
        XCTAssertFalse(isChecked(allApps))
        XCTAssertFalse(isChecked(selectedApps))

        let list = element(in: app, identifier: "settings.autoShowAppList")
        let addButton = element(in: app, identifier: "settings.autoShowAppAdd")
        XCTAssertTrue(list.exists)
        XCTAssertTrue(addButton.exists)
        XCTAssertEqual(chipCount(in: app), 0)
        XCTAssertFalse(addButton.isEnabled)

        selectedApps.click()
        XCTAssertTrue(isChecked(selectedApps))
        XCTAssertFalse(isChecked(off))
        XCTAssertTrue(waitUntil { addButton.isEnabled })

        // AC-25
        app.revealInSettings(addButton)
        try addFirstRunningApp(in: app, addButton: addButton)
        XCTAssertTrue(waitUntil { self.chipCount(in: app) == 1 })

        // AC-23
        let remove = removeButton(in: app)
        XCTAssertTrue(remove.exists)
        XCTAssertTrue(remove.isEnabled)
        remove.click()
        XCTAssertTrue(waitUntil { self.chipCount(in: app) == 0 })

        // AC-24
        try addFirstRunningApp(in: app, addButton: addButton)
        XCTAssertTrue(waitUntil { self.chipCount(in: app) == 1 })
        allApps.click()
        XCTAssertTrue(isChecked(allApps))
        XCTAssertFalse(isChecked(selectedApps))
        XCTAssertTrue(waitUntil { !addButton.isEnabled })
        XCTAssertEqual(chipCount(in: app), 1)
        XCTAssertFalse(removeButton(in: app).isEnabled)

        closeSettings(in: app, picker: modePicker)
    }

    // AC-26
    @MainActor
    func testAC26_noteModeDisablesRemoveButtonUntilSwitchedToInsert() throws {
        let app = XCUIApplication()
        launch(app)
        openSettingsFromMenu(in: app)
        element(in: app, identifier: "settings.sidebar.keys").click()
        let modePicker = element(in: app, identifier: "settings.autoShowModePicker")
        XCTAssertTrue(modePicker.waitForExistence(timeout: timeout))
        app.revealInSettings(modePicker)
        segment("選んだアプリのみ", in: modePicker).click()
        let addButton = element(in: app, identifier: "settings.autoShowAppAdd")
        XCTAssertTrue(waitUntil { addButton.isEnabled })
        app.revealInSettings(addButton)
        try addFirstRunningApp(in: app, addButton: addButton)
        XCTAssertTrue(waitUntil { self.chipCount(in: app) == 1 })
        XCTAssertTrue(waitUntil { self.removeButton(in: app).isEnabled })

        element(in: app, identifier: "settings.appMode.note").click()
        let banner = element(in: app, identifier: "settings.noteModeBanner.autoShow")
        XCTAssertTrue(banner.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { !self.removeButton(in: app).isEnabled })
        XCTAssertFalse(addButton.isEnabled)
        XCTAssertEqual(chipCount(in: app), 1)

        element(in: app, identifier: "settings.noteModeBanner.autoShow.switchToInsert").click()
        XCTAssertTrue(banner.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { self.removeButton(in: app).isEnabled })
        removeButton(in: app).click()
        XCTAssertTrue(waitUntil { self.chipCount(in: app) == 0 })

        closeSettings(in: app, picker: modePicker)
    }

    @MainActor
    private func launch(_ app: XCUIApplication) {
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.untrusted
        app.launch()
        app.dismissPermissionGuideIfPresent()
    }

    // MARK: - 対象のアプリのチップ

    @MainActor
    private func chipCount(in app: XCUIApplication) -> Int {
        let predicate = NSPredicate(
            format: "identifier BEGINSWITH %@ AND NOT (identifier ENDSWITH %@)",
            "settings.autoShowApp.", ".remove"
        )
        return app.descendants(matching: .any).matching(predicate).count
    }

    @MainActor
    private func removeButton(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "settings.autoShowApp.", ".remove")
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    @MainActor
    private func segment(_ name: String, in picker: XCUIElement) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ OR title == %@", name, name)
        return picker.descendants(matching: .any).matching(predicate).firstMatch
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
    private func isChecked(_ segment: XCUIElement) -> Bool {
        if let value = segment.value as? NSNumber {
            return value.boolValue
        }
        return segment.isSelected
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
        let window = app.windows.containing(.any, identifier: "settings.sidebar.general").firstMatch
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
        XCTAssertTrue(element(in: app, identifier: "settings.sidebar.general").waitForExistence(timeout: timeout))
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
