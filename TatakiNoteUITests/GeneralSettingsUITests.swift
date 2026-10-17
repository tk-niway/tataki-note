import XCTest

final class GeneralSettingsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"
    private var dataDirectory: URL?

    private let groupIdentifiers = ["settings.group.appearance", "settings.group.startup", "settings.group.history"]
    private let groupTitles = ["外観", "起動とメニューバー", "履歴"]

    private let sidebarGeneralID = "settings.sidebar.general"
    private let sidebarPanelID = "settings.sidebar.panel"
    private let clearHistoryID = "settings.clearHistory"
    private let cancelID = "settings.clearHistoryCancel"
    private let confirmID = "settings.clearHistoryConfirm"
    private let warningID = "settings.clearHistoryWarning"
    private let doneID = "settings.clearHistoryDone"
    private let countID = "settings.historyCount"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
        if let dataDirectory {
            try? FileManager.default.removeItem(at: dataDirectory)
        }
    }

    // AC-10
    @MainActor
    func testAC10_groupsInOrderWithoutAutoShow() throws {
        let app = try launchApp(historyCount: 0)
        openSettingsFromMenu(in: app)

        for identifier in groupIdentifiers {
            XCTAssertTrue(element(in: app, identifier: identifier).waitForExistence(timeout: timeout), identifier)
        }
        let ys = groupIdentifiers.map { element(in: app, identifier: $0).frame.minY }
        XCTAssertEqual(ys, ys.sorted(), "「一般」のまとまりが上から \(groupTitles) の順に並んでいない")
        XCTAssertEqual(Set(ys).count, ys.count)
        for (identifier, title) in zip(groupIdentifiers, groupTitles) {
            XCTAssertEqual(text(of: element(in: app, identifier: "\(identifier).title")), title, identifier)
        }

        let members = [
            "settings.themePicker",
            "settings.launchAtLoginToggle",
            "settings.hideMenuBarIconToggle",
            clearHistoryID,
        ]
        let memberYs = members.map { element(in: app, identifier: $0).frame.minY }
        for identifier in members {
            XCTAssertTrue(element(in: app, identifier: identifier).exists, identifier)
        }
        XCTAssertEqual(memberYs, memberYs.sorted(), "項目が テーマ・ログイン・アイコン・履歴 の順に並んでいない")

        for identifier in ["settings.autoShowModePicker", "settings.autoShowAppList"] {
            XCTAssertFalse(element(in: app, identifier: identifier).exists, identifier)
        }

        closeSettings(in: app)
    }

    // AC-13
    // AC-14
    // AC-52
    // AC-18
    @MainActor
    func testAC13_AC14_AC52_AC18_confirmationInTheRow() throws {
        let app = try launchApp(historyCount: 1)
        openSettingsFromMenu(in: app)

        // AC-13
        let count = element(in: app, identifier: countID)
        XCTAssertTrue(count.waitForExistence(timeout: timeout))
        XCTAssertEqual(text(of: count), "1")

        // AC-14
        let clearButton = element(in: app, identifier: clearHistoryID)
        XCTAssertTrue(clearButton.exists)
        XCTAssertTrue(clearButton.isEnabled)
        app.revealInSettings(clearButton)
        clearButton.click()
        XCTAssertTrue(element(in: app, identifier: cancelID).waitForExistence(timeout: timeout))
        XCTAssertTrue(element(in: app, identifier: confirmID).exists)
        XCTAssertEqual(text(of: count), "1")

        element(in: app, identifier: cancelID).click()
        XCTAssertTrue(element(in: app, identifier: cancelID).waitForNonExistence(timeout: timeout))
        XCTAssertTrue(element(in: app, identifier: confirmID).waitForNonExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { self.element(in: app, identifier: self.clearHistoryID).isEnabled })
        XCTAssertEqual(text(of: count), "1")

        // AC-52
        app.revealInSettings(element(in: app, identifier: clearHistoryID))
        element(in: app, identifier: clearHistoryID).click()
        let warning = element(in: app, identifier: warningID)
        XCTAssertTrue(warning.waitForExistence(timeout: timeout))
        XCTAssertTrue(text(of: warning).contains("元に戻せません"))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element(in: app, identifier: cancelID).waitForNonExistence(timeout: timeout))
        XCTAssertTrue(warning.waitForNonExistence(timeout: timeout))
        XCTAssertEqual(text(of: count), "1")

        // AC-18
        app.revealInSettings(element(in: app, identifier: clearHistoryID))
        element(in: app, identifier: clearHistoryID).click()
        XCTAssertTrue(element(in: app, identifier: cancelID).waitForExistence(timeout: timeout))
        element(in: app, identifier: sidebarPanelID).click()
        XCTAssertTrue(element(in: app, identifier: "settings.panelScreenPicker").waitForExistence(timeout: timeout))
        element(in: app, identifier: sidebarGeneralID).click()
        let clearButtonAfterSwitch = element(in: app, identifier: clearHistoryID)
        XCTAssertTrue(clearButtonAfterSwitch.waitForExistence(timeout: timeout))
        XCTAssertFalse(element(in: app, identifier: cancelID).exists)
        XCTAssertTrue(clearButtonAfterSwitch.isEnabled)
        XCTAssertEqual(text(of: element(in: app, identifier: countID)), "1")

        // AC-52
        app.revealInSettings(clearButtonAfterSwitch)
        clearButtonAfterSwitch.click()
        XCTAssertTrue(element(in: app, identifier: confirmID).waitForExistence(timeout: timeout))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element(in: app, identifier: doneID).waitForExistence(timeout: timeout))

        closeSettings(in: app)
    }

    // AC-15
    // AC-18
    @MainActor
    func testAC15_AC18_clearingEmptiesHistoryAndShowsDone() throws {
        let app = try launchApp(historyCount: 1)
        openSettingsFromMenu(in: app)

        // AC-15
        let clearButton = element(in: app, identifier: clearHistoryID)
        XCTAssertTrue(clearButton.waitForExistence(timeout: timeout))
        app.revealInSettings(clearButton)
        clearButton.click()
        let confirm = element(in: app, identifier: confirmID)
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        confirm.click()

        XCTAssertTrue(element(in: app, identifier: doneID).waitForExistence(timeout: timeout))
        XCTAssertEqual(text(of: element(in: app, identifier: countID)), "0")
        let clearAfterDone = element(in: app, identifier: clearHistoryID)
        XCTAssertTrue(!clearAfterDone.exists || !clearAfterDone.isEnabled)

        // AC-18
        element(in: app, identifier: sidebarPanelID).click()
        XCTAssertTrue(element(in: app, identifier: "settings.panelScreenPicker").waitForExistence(timeout: timeout))
        element(in: app, identifier: sidebarGeneralID).click()
        let clearButtonAfterSwitch = element(in: app, identifier: clearHistoryID)
        XCTAssertTrue(clearButtonAfterSwitch.waitForExistence(timeout: timeout))
        XCTAssertFalse(element(in: app, identifier: doneID).exists)
        XCTAssertFalse(clearButtonAfterSwitch.isEnabled)

        closeSettings(in: app)
    }

    // AC-17
    @MainActor
    func testAC17_clearIsUnavailableWithoutHistory() throws {
        let app = try launchApp(historyCount: 0)
        openSettingsFromMenu(in: app)

        let clearButton = element(in: app, identifier: clearHistoryID)
        XCTAssertTrue(clearButton.waitForExistence(timeout: timeout))
        XCTAssertFalse(clearButton.isEnabled)
        XCTAssertEqual(text(of: element(in: app, identifier: countID)), "0")
        XCTAssertFalse(element(in: app, identifier: cancelID).exists)

        closeSettings(in: app)
    }

    // MARK: - 起動と要素の探し方

    @MainActor
    private func launchApp(historyCount: Int) throws -> XCUIApplication {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TatakiNoteUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dataDirectory = directory
        let entries = (0..<historyCount).map { index in
            """
            {"id": "\(UUID().uuidString)", "text": "history \(index)", \
            "insertedAt": "2026-10-06T05:32:00Z", "appName": "Notes"}
            """
        }
        let history = "{\"version\": 1, \"history\": [\(entries.joined(separator: ","))]}"
        try Data(history.utf8).write(to: directory.appendingPathComponent("history.json"))

        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_DATA_DIRECTORY"] = directory.path
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        app.launch()
        app.dismissPermissionGuideIfPresent(timeout: 0.5)
        return app
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
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
        let window = app.windows.containing(.any, identifier: sidebarGeneralID).firstMatch
        XCTAssertTrue(window.exists)
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(element(in: app, identifier: sidebarGeneralID).waitForNonExistence(timeout: timeout))
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
        XCTAssertTrue(element(in: app, identifier: sidebarGeneralID).waitForExistence(timeout: timeout))
    }
}
