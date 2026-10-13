import XCTest

final class SettingsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-31
    // AC-35
    @MainActor
    func testAC31_AC35_recorderDisplayAndRegistration() throws {
        let app = XCUIApplication()
        launch(app)

        openKeySettings(in: app)
        let commitRecorder = element(in: app, identifier: commitKeyRecorderID)
        let commitAndSendRecorder = element(in: app, identifier: commitAndSendKeyRecorderID)
        XCTAssertTrue(commitRecorder.waitForExistence(timeout: timeout))
        XCTAssertTrue(hotkeyRecorder(in: app).exists)

        // AC-31
        XCTAssertEqual(recorderDisplayText(commitRecorder), "⇧⌘↩")
        XCTAssertFalse(isRecording(commitRecorder))
        XCTAssertEqual(recorderDisplayText(commitAndSendRecorder), "⌘↩")
        commitRecorder.click()
        XCTAssertEqual(commitRecorder.value as? String, recordingValue)
        XCTAssertTrue(isRecording(commitRecorder))
        app.typeKey("j", modifierFlags: [.command])
        XCTAssertTrue(waitUntil { self.recorderDisplayText(commitRecorder) == "⌘J" })

        closeSettings(in: app)

        // AC-35
        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        XCTAssertEqual(textView.promptPanelText, "")
        app.typeKey("j", modifierFlags: [.command])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))
    }

    @MainActor
    func testRecorderRejectsInvalidKeys() throws {
        let app = XCUIApplication()
        launch(app)

        openKeySettings(in: app)
        let commitRecorder = element(in: app, identifier: commitKeyRecorderID)
        XCTAssertTrue(commitRecorder.waitForExistence(timeout: timeout))
        let commitRejection = element(in: app, identifier: commitKeyRejectionID)

        commitRecorder.click()
        app.typeKey("k", modifierFlags: [])
        XCTAssertTrue(commitRejection.waitForExistence(timeout: timeout))
        XCTAssertTrue(isRecording(commitRecorder))

        app.typeKey("c", modifierFlags: [.command])
        XCTAssertTrue(waitUntil { self.text(of: commitRejection).contains("編集ショートカット") })
        XCTAssertTrue(isRecording(commitRecorder))

        app.typeKey(.return, modifierFlags: [.command])
        XCTAssertTrue(waitUntil { self.text(of: commitRejection).contains("確定+送信キー") })
        XCTAssertTrue(isRecording(commitRecorder))

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.recorderDisplayText(commitRecorder) == "⇧⌘↩" })
        commitRecorder.click()
        app.typeKey("j", modifierFlags: [.command])
        XCTAssertTrue(waitUntil { self.recorderDisplayText(commitRecorder) == "⌘J" })
        XCTAssertFalse(commitRejection.exists)

        closeSettings(in: app)
    }

    // AC-33
    @MainActor
    func testAC33_openingSettingsDoesNotStartRecording() throws {
        let app = XCUIApplication()
        launch(app)

        openKeySettings(in: app)
        let commitRecorder = element(in: app, identifier: commitKeyRecorderID)
        let commitAndSendRecorder = element(in: app, identifier: commitAndSendKeyRecorderID)
        XCTAssertTrue(commitRecorder.waitForExistence(timeout: timeout))

        XCTAssertFalse(isRecording(commitRecorder))
        XCTAssertEqual(recorderDisplayText(commitAndSendRecorder), "⌘↩")

        app.typeKey("k", modifierFlags: [.command])
        XCTAssertFalse(isRecording(commitRecorder))
        XCTAssertEqual(recorderDisplayText(commitRecorder), "⇧⌘↩")

        closeSettings(in: app)
        openKeySettings(in: app)
        let commitRecorderAfterReopen = element(in: app, identifier: commitKeyRecorderID)
        XCTAssertTrue(commitRecorderAfterReopen.waitForExistence(timeout: timeout))
        XCTAssertEqual(recorderDisplayText(commitRecorderAfterReopen), "⇧⌘↩")
        closeSettings(in: app)
    }

    // AC-33
    @MainActor
    func testAC33_recordingCancelledByEscOrOutsideClick() throws {
        let app = XCUIApplication()
        launch(app)

        openKeySettings(in: app)
        let commitRecorder = element(in: app, identifier: commitKeyRecorderID)
        let commitAndSendRecorder = element(in: app, identifier: commitAndSendKeyRecorderID)
        XCTAssertTrue(commitRecorder.waitForExistence(timeout: timeout))

        commitRecorder.click()
        XCTAssertTrue(isRecording(commitRecorder))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { !self.isRecording(commitRecorder) })
        XCTAssertTrue(waitUntil { self.recorderDisplayText(commitRecorder) == "⇧⌘↩" })

        commitRecorder.click()
        XCTAssertTrue(isRecording(commitRecorder))
        let heading = element(in: app, identifier: "settings.group.shortcuts.title")
        XCTAssertTrue(heading.exists)
        heading.click()
        XCTAssertTrue(waitUntil { !self.isRecording(commitRecorder) })

        app.typeKey("k", modifierFlags: [.command])
        XCTAssertEqual(recorderDisplayText(commitRecorder), "⇧⌘↩")

        commitRecorder.click()
        XCTAssertTrue(isRecording(commitRecorder))
        heading.rightClick()
        XCTAssertTrue(waitUntil { !self.isRecording(commitRecorder) })

        commitRecorder.click()
        XCTAssertTrue(isRecording(commitRecorder))
        XCTAssertTrue(commitAndSendRecorder.exists)
        commitAndSendRecorder.click()
        XCTAssertTrue(waitUntil { !self.isRecording(commitRecorder) })
        XCTAssertTrue(waitUntil { self.isRecording(commitAndSendRecorder) })
        XCTAssertEqual(recorderDisplayText(commitRecorder), "⇧⌘↩")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { !self.isRecording(commitAndSendRecorder) })
        XCTAssertEqual(recorderDisplayText(commitAndSendRecorder), "⌘↩")
        closeSettings(in: app)
    }

    // AC-36
    @MainActor
    func testAC36_panelScreenTilesOrderAndChangeScenario() throws {
        let app = XCUIApplication()
        launch(app)

        openPanelScreenSettings(in: app)
        let panelScreenPicker = element(in: app, identifier: panelScreenPickerID)
        XCTAssertTrue(panelScreenPicker.waitForExistence(timeout: timeout))

        let screens = ["nearFocusedField", "targetWindow", "mouse", "main"]
        let tiles = screens.map { element(in: app, identifier: "settings.panelScreen.\($0)") }
        XCTAssertTrue(tiles[0].waitForExistence(timeout: timeout))
        for (screen, tile) in zip(screens, tiles) {
            XCTAssertTrue(tile.exists, screen)
        }
        let xPositions = tiles.map(\.frame.minX)
        XCTAssertEqual(xPositions, xPositions.sorted(), "タイルが左から \(screens) の順に並んでいない")
        XCTAssertEqual(Set(xPositions).count, xPositions.count)
        let titles = ["入力欄の近く", "挿入先のウィンドウがある画面", "マウスの近く", "メインの画面"]
        for (title, tile) in zip(titles, tiles) {
            XCTAssertEqual(tile.label, title)
        }

        let description = element(in: app, identifier: panelScreenDescriptionID)
        XCTAssertTrue(description.exists)
        XCTAssertTrue(text(of: description).contains("入力欄の位置が分からないとき"), text(of: description))
        XCTAssertTrue(tiles[0].isSelected)
        XCTAssertFalse(tiles[2].isSelected)

        tiles[2].click()
        XCTAssertTrue(waitUntil { tiles[2].isSelected })
        XCTAssertFalse(tiles[0].isSelected)
        XCTAssertFalse(tiles[1].isSelected)
        XCTAssertFalse(tiles[3].isSelected)
        XCTAssertTrue(waitUntil { self.text(of: description).contains("マウスポインタ") }, text(of: description))

        closeSettings(in: app)
    }

    // AC-33
    // AC-35
    @MainActor
    func testAC33_AC35_recordingEndsWhenSwitchingSection() throws {
        let app = XCUIApplication()
        launch(app)

        openKeySettings(in: app)
        let commitRecorder = element(in: app, identifier: commitKeyRecorderID)
        XCTAssertTrue(commitRecorder.waitForExistence(timeout: timeout))
        commitRecorder.click()
        XCTAssertTrue(isRecording(commitRecorder))

        element(in: app, identifier: sidebarPanelID).click()
        XCTAssertTrue(element(in: app, identifier: panelScreenPickerID).waitForExistence(timeout: timeout))

        element(in: app, identifier: sidebarKeysID).click()
        let commitRecorderAfterSwitch = element(in: app, identifier: commitKeyRecorderID)
        XCTAssertTrue(commitRecorderAfterSwitch.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { !self.isRecording(commitRecorderAfterSwitch) })
        XCTAssertEqual(recorderDisplayText(commitRecorderAfterSwitch), "⇧⌘↩")

        closeSettings(in: app)

        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))
    }

    @MainActor
    func testAC14_clearHistoryAsksForConfirmationInTheRow() throws {
        let dataDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TatakiNoteUITests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dataDirectory) }
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let history = """
        {"version": 1, "history": [{"id": "\(UUID().uuidString)", "text": "history one", \
        "insertedAt": "2026-10-06T05:32:00Z", "appName": "Notes"}]}
        """
        try Data(history.utf8).write(to: dataDirectory.appendingPathComponent("history.json"))

        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_DATA_DIRECTORY"] = dataDirectory.path
        launch(app)

        openSettingsFromMenu(in: app)
        // AC-14
        let clearButton = element(in: app, identifier: "settings.clearHistory")
        app.revealInSettings(clearButton)
        XCTAssertTrue(clearButton.isEnabled)

        clearButton.click()
        let cancelButton = element(in: app, identifier: "settings.clearHistoryCancel")
        XCTAssertTrue(cancelButton.waitForExistence(timeout: timeout))
        XCTAssertTrue(element(in: app, identifier: "settings.clearHistoryConfirm").exists)
        XCTAssertFalse(app.sheets.firstMatch.exists)

        cancelButton.click()
        XCTAssertTrue(cancelButton.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { self.element(in: app, identifier: "settings.clearHistory").isEnabled })

        closeSettings(in: app)
    }

    @MainActor
    private func launch(_ app: XCUIApplication) {
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.untrusted
        app.launch()
        app.dismissPermissionGuideIfPresent()
    }

    // MARK: - 要素の探し方(PromptPanelUITests と同じ方法)

    private let commitKeyRecorderID = "settings.commitKeyRecorder"
    private let commitAndSendKeyRecorderID = "settings.commitAndSendKeyRecorder"
    private let commitKeyRejectionID = "settings.commitKeyRejection"
    private let panelScreenPickerID = "settings.panelScreenPicker"
    private let panelScreenDescriptionID = "settings.panelScreenDescription"
    private let sidebarGeneralID = "settings.sidebar.general"
    private let sidebarKeysID = "settings.sidebar.keys"
    private let sidebarPanelID = "settings.sidebar.panel"

    private let recordingValue = "ショートカットを押す"
    private let unregisteredValue = "登録なし"

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func isRecording(_ element: XCUIElement) -> Bool {
        element.value as? String == recordingValue
    }

    @MainActor
    private func recorderDisplayText(_ element: XCUIElement) -> String? {
        guard let value = element.value as? String, !value.isEmpty,
              value != recordingValue, value != unregisteredValue else { return nil }
        return value
    }

    @MainActor
    private func text(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    @MainActor
    private func hotkeyRecorder(in app: XCUIApplication) -> XCUIElement {
        let byIdentifier = element(in: app, identifier: "settings.hotkeyRecorder")
        if byIdentifier.waitForExistence(timeout: timeout) {
            return byIdentifier
        }
        let byLabel = app.descendants(matching: .any)["パネルを開く・閉じる"].firstMatch
        if byLabel.exists {
            return byLabel
        }
        let notCommitRecorders = NSPredicate(
            format: "identifier != %@ AND identifier != %@", commitKeyRecorderID, commitAndSendKeyRecorderID
        )
        return app.searchFields.matching(notCommitRecorders).firstMatch
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval? = nil, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout ?? self.timeout)
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
    private func openMenu(in app: XCUIApplication) {
        var statusItem = app.statusItems.firstMatch
        if !statusItem.waitForExistence(timeout: timeout) {
            statusItem = app.menuBars.statusItems.firstMatch
        }
        XCTAssertTrue(statusItem.waitForExistence(timeout: timeout))
        statusItem.click()
    }

    @MainActor
    private func openSettingsFromMenu(in app: XCUIApplication) {
        openMenu(in: app)
        let item = menuItem(in: app, identifier: "menu.settings", title: "設定")
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        clickShownMenuItem(item)
        XCTAssertTrue(element(in: app, identifier: sidebarGeneralID).waitForExistence(timeout: timeout))
    }

    @MainActor
    private func openKeySettings(in app: XCUIApplication) {
        openSettingsFromMenu(in: app)
        let keys = element(in: app, identifier: sidebarKeysID)
        XCTAssertTrue(keys.waitForExistence(timeout: timeout))
        keys.click()
        XCTAssertTrue(element(in: app, identifier: commitKeyRecorderID).waitForExistence(timeout: timeout))
    }

    @MainActor
    private func openPanelScreenSettings(in app: XCUIApplication) {
        openSettingsFromMenu(in: app)
        let panel = element(in: app, identifier: sidebarPanelID)
        XCTAssertTrue(panel.waitForExistence(timeout: timeout))
        panel.click()
        app.revealInSettings(element(in: app, identifier: panelScreenPickerID))
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
