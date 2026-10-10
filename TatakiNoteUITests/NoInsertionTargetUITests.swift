import XCTest

final class NoInsertionTargetUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-21
    @MainActor
    func testAC21_noInsertionTargetKeepsPanelOpenOnCommit() throws {
        let app = launchApp()

        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))

        let noTarget = element(in: app, identifier: "promptPanel.noInsertionTarget")
        XCTAssertTrue(noTarget.waitForExistence(timeout: timeout), "「挿入先なし」が出ない")
        XCTAssertEqual(noTarget.label, "挿入先なし")
        XCTAssertFalse(element(in: app, identifier: "promptPanel.insertionTarget").exists, "アプリのアイコンが出ている")

        app.typeText("abc")
        XCTAssertEqual(textView.promptPanelText, "abc")

        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertFalse(textView.waitForNonExistence(timeout: 1.5), "確定キーでパネルが閉じた")
        XCTAssertEqual(textView.promptPanelText, "abc")
        XCTAssertTrue(noTarget.exists)
        XCTAssertFalse(element(in: app, identifier: "insertionFailureBubble").exists, "吹き出しが出ている")

        app.typeKey(.return, modifierFlags: [.command])
        XCTAssertFalse(textView.waitForNonExistence(timeout: 1.5), "確定+送信キーでパネルが閉じた")
        XCTAssertEqual(textView.promptPanelText, "abc")
        XCTAssertTrue(noTarget.exists)
        XCTAssertFalse(element(in: app, identifier: "insertionFailureBubble").exists, "吹き出しが出ている")
    }

    // MARK: - 起動と要素の探し方(PermissionGuideUITests と同じ方法)

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launchEnvironment["TATAKINOTE_INSERTION_TARGET"] = "none"
        app.launch()
        return app
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
