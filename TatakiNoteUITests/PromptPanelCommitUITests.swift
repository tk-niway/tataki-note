import XCTest

// @note p0-1327
final class PromptPanelCommitUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    /// @note p0-1328
    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-12
    // @note p0-1329
    @MainActor
    func testAC12_emptyPanelKeysWithDefaultCommitKey() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        // @note p0-1330
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.untrusted
        app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = try settingsSeedJSON(["commitKey": "commandEnter"])
        app.launch()
        app.dismissPermissionGuideIfPresent()

        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        // @note p0-1331
        XCTAssertEqual(textView.value as? String, "")

        // @note p0-1332
        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(textView.exists)
        XCTAssertEqual(textView.value as? String, "\n")

        // @note p0-1333
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(textView.exists)
        XCTAssertEqual(textView.value as? String, "\n\n")
        app.typeKey(.return, modifierFlags: [.shift])
        XCTAssertTrue(textView.exists)
        XCTAssertEqual(textView.value as? String, "\n\n\n")

        // @note p0-1334
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(textView.value as? String, "")
        app.typeKey(.return, modifierFlags: [.command])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))
    }

    /// @note p0-1335
    private func settingsSeedJSON(_ values: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - 要素の探し方(PromptPanelUITests と同じ方法)

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

    // @note p0-1336
    @MainActor
    private func clickShownMenuItem(_ item: XCUIElement) {
        let deadline = Date().addingTimeInterval(timeout)
        while item.frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(item.frame.isEmpty, "メニューが表示されていない(項目の枠が空)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    // @note p0-1337
    @MainActor
    private func openPanelMenuItem(in app: XCUIApplication) -> XCUIElement {
        let byIdentifier = app.menuItems["menu.openPanel"]
        if byIdentifier.exists {
            return byIdentifier
        }
        return app.menuItems["パネルを開く"]
    }
}
