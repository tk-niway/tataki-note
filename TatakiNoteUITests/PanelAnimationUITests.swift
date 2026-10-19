import XCTest

final class PanelAnimationUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-16
    @MainActor
    func testAC16_openAndCloseWithAnimation() throws {
        let app = launchApp()
        let textView = app.textViews["promptPanel.textView"]

        let panel = openPanel(in: app)
        waitForSteadyFrame(of: panel)
        app.typeText("abc")
        XCTAssertEqual(textView.promptPanelText, "abc")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout), "esc で閉じない")

        let reopenedForButton = openPanel(in: app)
        waitForSteadyFrame(of: reopenedForButton)
        app.typeText("d")
        XCTAssertEqual(textView.promptPanelText, "abcd")
        let closeButton = app.buttons["promptPanel.closeButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: timeout))
        closeButton.click()
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout), "× ボタンで閉じない")

        let reopenedForHideKey = openPanel(in: app)
        waitForSteadyFrame(of: reopenedForHideKey)
        app.typeText("e")
        XCTAssertEqual(textView.promptPanelText, "abcde")
        app.typeKey("h", modifierFlags: [.command])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout), "⌘H で閉じない")
    }

    // MARK: - 起動と要素の探し方(PanelCloseButtonUITests・SettingsUITests と同じ方法)

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launch()
        return app
    }

    @MainActor
    private func waitForSteadyFrame(of element: XCUIElement) {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = element.frame
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let current = element.frame
            if current == previous {
                return
            }
            previous = current
        }
        XCTFail("パネルの枠が止まらない")
    }

    @MainActor
    private func openPanel(in app: XCUIApplication) -> XCUIElement {
        openPanelFromMenu(in: app)
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForExistence(timeout: timeout))
        let panel = app.dialogs["promptPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: timeout), "パネルの窓が見つからない")
        return panel
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
