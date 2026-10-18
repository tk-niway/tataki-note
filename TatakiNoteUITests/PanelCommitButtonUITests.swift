import XCTest

final class PanelCommitButtonUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-5
    @MainActor
    func testAC5_commitButtonWithoutPermissionClosesAndShowsGuide() throws {
        let app = try launchApp(
            permission: AccessibilityOverride.untrusted,
            seed: ["commitKey": "commandShiftEnter", "commitAndSendKey": "commandEnter"]
        )
        XCTAssertTrue(
            element(in: app, identifier: "permissionGuide.status").waitForExistence(timeout: timeout),
            "untrusted の上書きが効いていない。本物の挿入を避けるため、文章を打たずに止める"
        )
        app.dismissPermissionGuideIfPresent()

        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        app.typeText("abc")
        XCTAssertEqual(textView.promptPanelText, "abc")

        let commitButton = element(in: app, identifier: "promptPanel.status.commit")
        XCTAssertTrue(commitButton.waitForExistence(timeout: timeout))
        commitButton.click()

        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(element(in: app, identifier: "permissionGuide.draftKept").waitForExistence(timeout: timeout))
        let closeButton = app.buttons["permissionGuide.close"]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: timeout))
    }

    // AC-5
    @MainActor
    func testAC5_buttonsWithNoTargetKeepPanelOpen() throws {
        let app = try launchApp(
            permission: AccessibilityOverride.trusted,
            seed: ["commitKey": "commandShiftEnter", "commitAndSendKey": "commandEnter"],
            insertionTarget: "none"
        )
        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        app.typeText("abc")
        XCTAssertEqual(textView.promptPanelText, "abc")

        let commitAndSendButton = element(in: app, identifier: "promptPanel.status.commitAndSend")
        XCTAssertTrue(commitAndSendButton.waitForExistence(timeout: timeout))
        commitAndSendButton.click()
        XCTAssertFalse(textView.waitForNonExistence(timeout: 1.5), "送信のボタンでパネルが閉じた")
        XCTAssertTrue(element(in: app, identifier: "promptPanel.noInsertionTarget").exists)

        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(textView.promptPanelText, "")
        let commitButton = element(in: app, identifier: "promptPanel.status.commit")
        XCTAssertTrue(commitButton.exists)
        commitButton.click()
        XCTAssertFalse(textView.waitForNonExistence(timeout: 1), "空のまま挿入のボタンでパネルが閉じた")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))
    }

    // MARK: - 起動と要素の探し方

    @MainActor
    private func launchApp(
        permission: String,
        seed: [String: Any]? = nil,
        insertionTarget: String? = nil
    ) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = permission
        if let seed {
            app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = try settingsSeedJSON(seed)
        }
        if let insertionTarget {
            app.launchEnvironment["TATAKINOTE_INSERTION_TARGET"] = insertionTarget
        }
        app.launch()
        return app
    }

    private func settingsSeedJSON(_ values: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func openPanelFromMenu(in app: XCUIApplication) {
        var statusItem = app.statusItems.firstMatch
        if !statusItem.waitForExistence(timeout: timeout) {
            statusItem = app.menuBars.statusItems.firstMatch
        }
        XCTAssertTrue(statusItem.waitForExistence(timeout: timeout))
        statusItem.click()

        let item = openPanelMenuItem(in: app)
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
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
