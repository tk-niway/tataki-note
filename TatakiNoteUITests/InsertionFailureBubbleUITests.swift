import XCTest

final class InsertionFailureBubbleUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-1
    // AC-5
    @MainActor
    func testAC1_AC5_bubbleOpensPanel() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launchEnvironment["TATAKINOTE_INSERTION_TARGET"] = "none"
        app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = try settingsSeedJSON(["commitKey": "commandEnter"])
        app.launch()
        app.dismissPermissionGuideIfPresent(timeout: 0.5)

        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        app.typeText("abc")
        XCTAssertEqual(textView.value as? String, "abc")

        app.typeKey(.return, modifierFlags: [.command])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))

        // AC-1
        let bubble = app.descendants(matching: .any)["insertionFailureBubble"].firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: timeout))

        bubble.click()
        XCTAssertTrue(bubble.waitForNonExistence(timeout: timeout))

        // AC-5
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        XCTAssertEqual(textView.value as? String, "abc")
    }

    private func settingsSeedJSON(_ values: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - 要素の探し方(PromptPanelCommitUITests と同じ方法)

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
        let byIdentifier = app.menuItems["menu.openPanel"]
        if byIdentifier.exists {
            return byIdentifier
        }
        return app.menuItems["パネルを開く"]
    }
}
