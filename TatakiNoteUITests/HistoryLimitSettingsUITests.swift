import XCTest

final class HistoryLimitSettingsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"
    private var dataDirectory: URL?

    private let sidebarGeneralID = "settings.sidebar.general"
    private let countID = "settings.historyCount"
    private let limitFieldID = "settings.historyLimitField"
    private let limitStepperID = "settings.historyLimitStepper"
    private let warningID = "settings.historyLimitWarning"
    private let cancelID = "settings.historyLimitCancel"
    private let confirmID = "settings.historyLimitConfirm"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
        if let dataDirectory {
            try? FileManager.default.removeItem(at: dataDirectory)
        }
    }

    // AC-29
    // AC-30
    @MainActor
    func testAC29_AC30_historyLimitStepperAndShrinkConfirmation() throws {
        let app = try launchApp(historyCount: 20, historyLimit: 20)
        openSettingsFromMenu(in: app)

        let field = element(in: app, identifier: limitFieldID)
        app.revealInSettings(field)
        XCTAssertEqual(field.value as? String, "20")
        let count = element(in: app, identifier: countID)
        XCTAssertEqual(text(of: count), "20")

        // AC-29
        let increase = arrow(ofStepper: limitStepperID, in: app, increment: true)
        app.revealInSettings(increase)
        increase.click()
        XCTAssertTrue(waitUntil { field.value as? String == "30" }, "上限が 10 増えない(\(String(describing: field.value)))")
        XCTAssertFalse(element(in: app, identifier: warningID).exists)

        let decrease = arrow(ofStepper: limitStepperID, in: app, increment: false)
        decrease.click()
        XCTAssertTrue(waitUntil { field.value as? String == "20" }, "上限が 10 減らない(\(String(describing: field.value)))")
        XCTAssertFalse(element(in: app, identifier: warningID).exists)

        // AC-30
        decrease.click()
        let warning = element(in: app, identifier: warningID)
        XCTAssertTrue(warning.waitForExistence(timeout: timeout))
        XCTAssertTrue(text(of: warning).contains("10 件消えます"), text(of: warning))
        XCTAssertTrue(element(in: app, identifier: confirmID).exists)
        XCTAssertEqual(text(of: count), "20")

        element(in: app, identifier: cancelID).click()
        XCTAssertTrue(warning.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { self.element(in: app, identifier: self.limitFieldID).value as? String == "20" })
        XCTAssertEqual(text(of: element(in: app, identifier: countID)), "20")

        arrow(ofStepper: limitStepperID, in: app, increment: false).click()
        let confirm = element(in: app, identifier: confirmID)
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        confirm.click()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { self.element(in: app, identifier: self.limitFieldID).value as? String == "10" })
        XCTAssertTrue(waitUntil { self.text(of: self.element(in: app, identifier: self.countID)) == "10" })

        closeSettings(in: app)
    }

    // MARK: - 起動と要素の探し方

    @MainActor
    private func launchApp(historyCount: Int, historyLimit: Int) throws -> XCUIApplication {
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
        let seed = try JSONSerialization.data(withJSONObject: ["historyLimit": historyLimit], options: [.sortedKeys])

        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_DATA_DIRECTORY"] = directory.path
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = String(decoding: seed, as: UTF8.self)
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
    private func arrow(ofStepper identifier: String, in app: XCUIApplication, increment: Bool) -> XCUIElement {
        let found = element(in: app, identifier: identifier)
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "ステッパーが無い: \(identifier)")
        let stepper = found.elementType == .stepper ? found : found.steppers.firstMatch
        let arrow = increment ? stepper.incrementArrows.firstMatch : stepper.decrementArrows.firstMatch
        XCTAssertTrue(arrow.waitForExistence(timeout: timeout), "ステッパーの矢印が無い: \(identifier)")
        return arrow
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
