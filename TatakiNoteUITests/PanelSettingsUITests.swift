import XCTest

final class PanelSettingsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    private let panelScreens = ["nearFocusedField", "targetWindow", "mouse", "main"]
    private let statusItems = ["lineBreak", "close", "commit", "commitAndSend", "characterCount", "lineCount"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-36
    @MainActor
    func testAC36_panelScreenTilesSelectAndDescribe() throws {
        let app = launchApp()
        openPanelSettings(in: app)

        let tiles = panelScreens.map { element(in: app, identifier: "settings.panelScreen.\($0)") }
        XCTAssertTrue(element(in: app, identifier: "settings.panelScreenPicker").waitForExistence(timeout: timeout))
        for (screen, tile) in zip(panelScreens, tiles) {
            XCTAssertTrue(tile.waitForExistence(timeout: timeout), screen)
        }
        let xPositions = tiles.map(\.frame.minX)
        XCTAssertEqual(xPositions, xPositions.sorted(), "タイルが左から \(panelScreens) の順に並んでいない")
        XCTAssertEqual(Set(xPositions).count, xPositions.count)
        XCTAssertEqual(tiles.map(\.label), ["入力欄の近く", "挿入先のウィンドウがある画面", "マウスの近く", "メインの画面"])

        let description = element(in: app, identifier: "settings.panelScreenDescription")
        XCTAssertTrue(tiles[0].isSelected)
        XCTAssertEqual(tiles.filter(\.isSelected).count, 1)
        XCTAssertTrue(text(of: description).contains("入力欄の位置が分からないとき"), text(of: description))

        tiles[2].click()
        XCTAssertTrue(waitUntil { tiles[2].isSelected })
        XCTAssertEqual(tiles.filter(\.isSelected).count, 1)
        XCTAssertTrue(waitUntil { self.text(of: description).contains("マウスポインタ") }, text(of: description))
        XCTAssertFalse(text(of: description).contains("入力欄の位置が分からないとき"))

        closeSettings(in: app)
    }

    // AC-41
    @MainActor
    func testAC41_statusItemOutlineAndAnimationSwitches() throws {
        let app = launchApp()
        openPanelSettings(in: app)

        for item in statusItems {
            let toggle = element(in: app, identifier: "settings.statusItem.\(item)")
            app.revealInSettings(toggle)
            XCTAssertTrue(isOn(toggle), item)
        }
        let characterCount = element(in: app, identifier: "settings.statusItem.characterCount")
        characterCount.click()
        XCTAssertTrue(waitUntil { !self.isOn(characterCount) })
        XCTAssertTrue(isOn(element(in: app, identifier: "settings.statusItem.lineCount")))

        let outline = element(in: app, identifier: "settings.insertionTargetOutlineToggle")
        app.revealInSettings(outline)
        XCTAssertTrue(outline.isEnabled)
        XCTAssertTrue(isOn(outline))

        let animation = element(in: app, identifier: "settings.panelAnimationToggle")
        app.revealInSettings(animation)
        XCTAssertTrue(animation.isEnabled)
        XCTAssertTrue(isOn(animation))

        closeSettings(in: app)
    }

    // MARK: - 起動

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        app.launch()
        app.dismissPermissionGuideIfPresent(timeout: 0.5)
        return app
    }

    // MARK: - 要素の探し方

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func text(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    @MainActor
    private func isOn(_ element: XCUIElement) -> Bool {
        if let value = element.value as? NSNumber {
            return value.boolValue
        }
        return element.isSelected
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
    private func openPanelSettings(in app: XCUIApplication) {
        openSettingsFromMenu(in: app)
        let panel = element(in: app, identifier: "settings.sidebar.panel")
        XCTAssertTrue(panel.waitForExistence(timeout: timeout))
        panel.click()
        XCTAssertTrue(element(in: app, identifier: "settings.panelScreenPicker").waitForExistence(timeout: timeout))
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
    private func openSettingsFromMenu(in app: XCUIApplication) {
        var statusItem = app.statusItems.firstMatch
        if !statusItem.waitForExistence(timeout: timeout) {
            statusItem = app.menuBars.statusItems.firstMatch
        }
        XCTAssertTrue(statusItem.waitForExistence(timeout: timeout))
        statusItem.click()

        let byIdentifier = app.menuItems["menu.settings"]
        let item = byIdentifier.exists ? byIdentifier : app.menuItems["設定"]
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        let deadline = Date().addingTimeInterval(timeout)
        while item.frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(item.frame.isEmpty, "メニューが表示されていない(項目の枠が空)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(element(in: app, identifier: "settings.sidebar.general").waitForExistence(timeout: timeout))
    }
}
