import XCTest

// @note p0-1308
final class PermissionGuideUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    /// @note p0-1309
    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-1
    // @note p0-1310
    // AC-8
    // @note p0-1311
    @MainActor
    func testAC1_AC8_launchWithoutPermissionShowsGuide() throws {
        let app = try launchApp(override: AccessibilityOverride.untrusted)

        // AC-1
        XCTAssertTrue(guideElement(in: app, identifier: "permissionGuide.status").waitForExistence(timeout: timeout))
        XCTAssertTrue(guideElement(in: app, identifier: "permissionGuide.steps").exists)
        XCTAssertTrue(app.buttons["permissionGuide.openSystemSettings"].exists)
        XCTAssertFalse(guideElement(in: app, identifier: "permissionGuide.draftKept").exists)

        // AC-8
        let closeButton = app.buttons["permissionGuide.close"]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(guideElement(in: app, identifier: "permissionGuide.status").waitForNonExistence(timeout: timeout))
        XCTAssertNotEqual(app.state, .notRunning)

        openPanelFromMenu(in: app)
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForExistence(timeout: timeout))
    }

    // AC-3
    // @note p0-1312
    @MainActor
    func testAC3_commitWithoutPermissionShowsGuideAndKeepsDraft() throws {
        let app = try launchApp(override: AccessibilityOverride.untrusted, seed: ["commitKey": "commandEnter"])

        // @note p0-1313
        XCTAssertTrue(
            guideElement(in: app, identifier: "permissionGuide.status").waitForExistence(timeout: timeout),
            "untrusted の上書きが効いていない。本物の挿入を避けるため、文章を打たずに止める"
        )
        app.dismissPermissionGuideIfPresent()

        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        app.typeText("abc")
        XCTAssertEqual(textView.value as? String, "abc")

        // @note p0-1314
        app.typeKey(.return, modifierFlags: [.command])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(guideElement(in: app, identifier: "permissionGuide.draftKept").waitForExistence(timeout: timeout))
        XCTAssertTrue(guideElement(in: app, identifier: "permissionGuide.status").exists)
        XCTAssertTrue(guideElement(in: app, identifier: "permissionGuide.steps").exists)

        // @note p0-1315
        let closeButton = app.buttons["permissionGuide.close"]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: timeout))

        openPanelFromMenu(in: app)
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        XCTAssertEqual(textView.value as? String, "abc")
    }

    // @note p0-1316

    // AC-13
    // @note p0-1317
    @MainActor
    func testAC13_reopeningDoesNotAddWindows() throws {
        let app = try launchApp(override: AccessibilityOverride.untrusted, seed: ["commitKey": "commandEnter"])
        let status = guideElement(in: app, identifier: "permissionGuide.status")
        // @note p0-1318
        XCTAssertTrue(
            status.waitForExistence(timeout: timeout),
            "untrusted の上書きが効いていない。本物の挿入を避けるため、文章を打たずに止める"
        )
        XCTAssertEqual(guideStatusCount(in: app), 1)

        // @note p0-1319
        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        app.typeText("abc")
        XCTAssertEqual(textView.value as? String, "abc")

        // @note p0-1320
        app.typeKey(.return, modifierFlags: [.command])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(guideElement(in: app, identifier: "permissionGuide.draftKept").waitForExistence(timeout: timeout))
        XCTAssertTrue(status.exists)
        XCTAssertEqual(guideStatusCount(in: app), 1)
    }

    // AC-2
    // @note p0-1321
    @MainActor
    func testAC2_launchWithPermission() throws {
        let app = try launchApp(override: AccessibilityOverride.trusted)

        // AC-2
        // @note p0-1322
        let status = guideElement(in: app, identifier: "permissionGuide.status")
        XCTAssertFalse(status.waitForExistence(timeout: 2))
        XCTAssertEqual(app.windows.count, 0)
    }

    // MARK: - 起動

    /// @note p0-1323
    @MainActor
    private func launchApp(override: String, seed: [String: Any]? = nil) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = override
        if let seed {
            app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = try settingsSeedJSON(seed)
        }
        app.launch()
        return app
    }

    /// @note p0-1324
    private func settingsSeedJSON(_ values: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - 要素の探し方(PromptPanelUITests と同じ方法)

    @MainActor
    private func guideElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func guideStatusCount(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(identifier: "permissionGuide.status").count
    }

    @MainActor
    @discardableResult
    private func openMenu(in app: XCUIApplication) -> XCUIElement {
        var statusItem = app.statusItems.firstMatch
        if !statusItem.waitForExistence(timeout: timeout) {
            statusItem = app.menuBars.statusItems.firstMatch
        }
        XCTAssertTrue(statusItem.waitForExistence(timeout: timeout))
        statusItem.click()
        return statusItem
    }

    @MainActor
    private func openPanelFromMenu(in app: XCUIApplication) {
        openMenu(in: app)
        let item = menuItem(in: app, identifier: "menu.openPanel", title: "パネルを開く")
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        clickShownMenuItem(item)
    }

    // @note p0-1325
    @MainActor
    private func clickShownMenuItem(_ item: XCUIElement) {
        let deadline = Date().addingTimeInterval(timeout)
        while item.frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(item.frame.isEmpty, "メニューが表示されていない(項目の枠が空)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    // @note p0-1326
    @MainActor
    private func menuItem(in app: XCUIApplication, identifier: String, title: String) -> XCUIElement {
        let byIdentifier = app.menuItems[identifier]
        if byIdentifier.exists {
            return byIdentifier
        }
        return app.menuItems[title]
    }
}
