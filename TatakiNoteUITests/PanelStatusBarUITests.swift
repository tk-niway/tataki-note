import XCTest

final class PanelStatusBarUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-6
    @MainActor
    func testAC6_AC8_AC12_defaultStatusBar() throws {
        let app = try launchApp(seed: nil)
        let textView = openPanel(in: app)
        XCTAssertEqual(textView.promptPanelText, "")

        XCTAssertTrue(statusBar(in: app).waitForExistence(timeout: timeout), "帯が無い")
        assertLabel(statusItem("close", in: app), "esc 閉じる")
        assertLabel(statusItem("lineBreak", in: app), "↩ 改行")
        assertLabel(statusItem("commit", in: app), "⇧⌘↩ 挿入")
        assertLabel(statusItem("commitAndSend", in: app), "⌘↩ 送信")
        assertLabel(statusItem("characterCount", in: app), "0文字")
        assertLabel(statusItem("lineCount", in: app), "0行")

        app.typeText("ab")
        assertLabel(statusItem("characterCount", in: app), "2文字")
        assertLabel(statusItem("lineCount", in: app), "1行")

        // AC-12
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))
        openPanelFromMenu(in: app)
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        XCTAssertEqual(textView.value as? String, "ab")
        assertLabel(statusItem("characterCount", in: app), "2文字")
        assertLabel(statusItem("lineCount", in: app), "1行")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))
    }

    // MARK: - 起動と要素の探し方

    @MainActor
    private func launchApp(seed: [String: Any]?) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        if let seed {
            app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = try settingsSeedJSON(seed)
        }
        app.launch()
        return app
    }

    private func settingsSeedJSON(_ values: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    @MainActor
    private func statusBar(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "promptPanel.statusBar").firstMatch
    }

    @MainActor
    private func statusItem(_ rawValue: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "promptPanel.status.\(rawValue)").firstMatch
    }

    @MainActor
    private func assertLabel(_ element: XCUIElement, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(expected) の項目が無い", file: file, line: line)
        let deadline = Date().addingTimeInterval(timeout)
        while element.label != expected && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(element.label, expected, file: file, line: line)
    }

    @MainActor
    private func openPanel(in app: XCUIApplication) -> XCUIElement {
        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        return textView
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
