import XCTest

final class PromptPanelUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        return app
    }

    // AC-10
    @MainActor
    func testAC10_launchOpensNoWindow() throws {
        let app = makeApp()
        app.launch()

        XCTAssertEqual(app.windows.count, 0)
    }

    @MainActor
    func testAC1_AC2_AC3_AC5_AC9_AC14_AC17_panelScenario() throws {
        let app = makeApp()
        app.launch()

        // AC-9
        openMenu(in: app)
        let openItem = openPanelMenuItem(in: app)
        XCTAssertTrue(openItem.waitForExistence(timeout: timeout))
        XCTAssertTrue(quitMenuItem(in: app).exists)
        clickShownMenuItem(openItem)

        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))

        // AC-2
        XCTAssertEqual(textView.value as? String, "")
        app.typeText("hello")
        XCTAssertEqual(textView.value as? String, "hello")

        // AC-5
        app.typeKey(.return, modifierFlags: [])
        app.typeText("world")
        XCTAssertEqual(textView.value as? String, "hello\nworld")
        XCTAssertTrue(textView.exists)

        // AC-3
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))

        // AC-1
        openPanelFromMenu(in: app)
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        XCTAssertEqual(textView.value as? String, "hello\nworld")

        // AC-17
        let panel = panelElement(in: app, fallback: textView)
        let frameBefore = panel.frame
        openPanelFromMenu(in: app)
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        XCTAssertEqual(textView.value as? String, "hello\nworld")
        XCTAssertEqual(panel.frame, frameBefore)
        app.typeText("!")
        XCTAssertEqual(textView.value as? String, "hello\nworld!")

        // AC-14
        app.typeKey("a", modifierFlags: [.command])
        app.typeText("x")
        XCTAssertEqual(textView.value as? String, "x")
        app.typeKey("z", modifierFlags: [.command])
        XCTAssertEqual(textView.value as? String, "hello\nworld!")
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(textView.value as? String, "x")

        // AC-9
        openMenu(in: app)
        let quitItem = quitMenuItem(in: app)
        XCTAssertTrue(quitItem.waitForExistence(timeout: timeout))
        clickShownMenuItem(quitItem)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: timeout))
    }

    // MARK: - 要素の探し方

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
        let item = openPanelMenuItem(in: app)
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
    private func openPanelMenuItem(in app: XCUIApplication) -> XCUIElement {
        menuItem(in: app, identifier: "menu.openPanel", title: "パネルを開く")
    }

    @MainActor
    private func quitMenuItem(in app: XCUIApplication) -> XCUIElement {
        menuItem(in: app, identifier: "menu.quit", title: "終了")
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
    private func panelElement(in app: XCUIApplication, fallback: XCUIElement) -> XCUIElement {
        let panel = app.windows["promptPanel"]
        return panel.exists ? panel : fallback
    }
}
