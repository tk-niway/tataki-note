import XCTest

final class SettingsDescriptionsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-15
    @MainActor
    func testAC15_removedDescriptionsAndPanelSizeTexts() throws {
        let app = launchApp()
        openSettingsFromMenu(in: app)

        let general = element(in: app, identifier: "settings.sidebar.general")
        general.click()
        XCTAssertTrue(element(in: app, identifier: "settings.hideMenuBarIconToggle").waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { self.staticText(in: app, containing: "⌘, でこの画面を開きます").exists })
        XCTAssertFalse(staticText(in: app, containing: "外観モード").exists)
        XCTAssertFalse(staticText(in: app, containing: "ログインしたとき").exists)

        let panel = element(in: app, identifier: "settings.sidebar.panel")
        panel.click()
        XCTAssertTrue(element(in: app, identifier: "settings.panelScreenPicker").waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { self.staticText(in: app, containing: "帯ごと消えます").exists })
        for removed in ["フォントパネルで選んだ", "pt の間で選べます", "幅 320", "ドラッグして大きさ"] {
            XCTAssertFalse(staticText(in: app, containing: removed).exists, removed)
        }

        let sizeTitle = element(in: app, identifier: "settings.group.panelDefaultSize.title")
        XCTAssertTrue(sizeTitle.waitForExistence(timeout: timeout))
        XCTAssertEqual(text(of: sizeTitle), "パネルのサイズ")
        let useCurrent = element(in: app, identifier: "settings.useCurrentPanelSize")
        XCTAssertTrue(useCurrent.waitForExistence(timeout: timeout))
        XCTAssertEqual(useCurrent.label, "今のパネルサイズを既定にする")

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
    private func staticText(in app: XCUIApplication, containing fragment: String) -> XCUIElement {
        let predicate = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", fragment, fragment)
        return app.staticTexts.matching(predicate).firstMatch
    }

    @MainActor
    private func text(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
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
