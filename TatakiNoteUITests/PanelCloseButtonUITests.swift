import XCTest

final class PanelCloseButtonUITests: XCTestCase {
    private let timeout: TimeInterval = 5
    private let tolerance: CGFloat = 2

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    @MainActor
    func testAC1_AC2_closeButtonClosesAndKeepsDraft() throws {
        let app = try launchApp(seed: nil)
        _ = openPanel(in: app)
        let closeButton = app.buttons["promptPanel.closeButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: timeout), "文章が空のときにボタンが無い")

        app.typeText("abc")
        closeButton.click()
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForNonExistence(timeout: timeout))

        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        XCTAssertEqual(textView.value as? String, "abc")
    }

    // AC-1
    @MainActor
    func testAC1_closeButtonVisibleWithoutStatusBar() throws {
        let app = try launchApp(seed: [
            "hiddenPanelStatusItems": ["lineBreak", "close", "commit", "commitAndSend", "characterCount", "lineCount"],
        ])
        _ = openPanel(in: app)
        let closeButton = app.buttons["promptPanel.closeButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: timeout), "帯なしのときにボタンが無い")

        closeButton.click()
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForNonExistence(timeout: timeout))
    }

    // AC-3
    @MainActor
    func testAC3_closeButtonKeepsDraggedSize() throws {
        let app = try launchApp(seed: nil)
        let panel = openPanel(in: app)

        dragBottomRightCorner(of: panel, by: CGVector(dx: -100, dy: -60))
        let draggedSize = panel.frame.size

        app.buttons["promptPanel.closeButton"].click()
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForNonExistence(timeout: timeout))

        let reopened = openPanel(in: app)
        assertSize(reopened.frame.size, equals: draggedSize)
    }

    // MARK: - 起動と要素の探し方(PanelSizeUITests・PanelStatusBarUITests と同じ方法)

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
    private func openPanel(in app: XCUIApplication) -> XCUIElement {
        openPanelFromMenu(in: app)
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForExistence(timeout: timeout))
        let panel = app.dialogs["promptPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: timeout), "パネルの窓が見つからない")
        return panel
    }

    @MainActor
    private func dragBottomRightCorner(of panel: XCUIElement, by offset: CGVector) {
        let corner = panel.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.press(forDuration: 0.5, thenDragTo: corner.withOffset(offset))
    }

    private func assertSize(
        _ size: CGSize,
        equals expected: CGSize,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(size.width, expected.width, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(size.height, expected.height, accuracy: tolerance, message, file: file, line: line)
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
