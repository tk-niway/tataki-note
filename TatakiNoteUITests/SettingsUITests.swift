import XCTest

// @note p0-1384
final class SettingsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    /// @note p0-1385
    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-9
    // @note p0-1386
    // AC-11
    // @note p0-1387
    // AC-18
    // @note p0-1388
    @MainActor
    func testAC9_AC11_AC18_recorderInitialDisplayAndRegistration() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let commitRecorder = element(in: app, identifier: commitKeyRecorderID)
        let commitAndSendRecorder = element(in: app, identifier: commitAndSendKeyRecorderID)
        XCTAssertTrue(commitRecorder.waitForExistence(timeout: timeout))
        // @note p0-1389
        XCTAssertTrue(hotkeyRecorder(in: app).exists)

        // AC-9
        // @note p0-1390
        XCTAssertNil(recorderDisplayText(commitRecorder))
        XCTAssertEqual(commitRecorder.placeholderValue, idlePlaceholder)
        XCTAssertEqual(recorderDisplayText(commitAndSendRecorder), "⌘↩")

        // AC-11
        // @note p0-1391
        commitRecorder.click()
        XCTAssertEqual(commitRecorder.placeholderValue, recordingPlaceholder)
        app.typeKey("k", modifierFlags: [.command])
        XCTAssertTrue(waitUntil { self.recorderDisplayText(commitRecorder) == "⌘K" })

        closeSettings(in: app)

        // AC-18
        // @note p0-1393
        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        XCTAssertEqual(textView.value as? String, "")
        app.typeKey("k", modifierFlags: [.command])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))
    }

    // AC-12
    // @note p0-1394
    // AC-14
    // @note p0-1395
    // AC-15
    // @note p0-1396
    @MainActor
    func testAC12_AC14_AC15_recorderRejectsInvalidKeys() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let commitRecorder = element(in: app, identifier: commitKeyRecorderID)
        XCTAssertTrue(commitRecorder.waitForExistence(timeout: timeout))
        let commitRejection = element(in: app, identifier: commitKeyRejectionID)

        // AC-12
        // @note p0-1397
        commitRecorder.click()
        app.typeKey("k", modifierFlags: [])
        XCTAssertTrue(commitRejection.waitForExistence(timeout: timeout))
        XCTAssertNil(recorderDisplayText(commitRecorder))

        // AC-15
        // @note p0-1398
        app.typeKey("c", modifierFlags: [.command])
        XCTAssertTrue(waitUntil { self.text(of: commitRejection).contains("編集ショートカット") })
        XCTAssertNil(recorderDisplayText(commitRecorder))

        // AC-14
        // @note p0-1399
        app.typeKey(.return, modifierFlags: [.command])
        XCTAssertTrue(waitUntil { self.text(of: commitRejection).contains("確定+送信キー") })
        XCTAssertNil(recorderDisplayText(commitRecorder))

        // @note p0-1400
        app.typeKey("k", modifierFlags: [.command])
        XCTAssertTrue(waitUntil { self.recorderDisplayText(commitRecorder) == "⌘K" })
        XCTAssertFalse(commitRejection.exists)

        closeSettings(in: app)
    }

    // AC-26
    // @note p0-1405
    @MainActor
    func testAC26_openingSettingsDoesNotStartRecording() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let commitRecorder = element(in: app, identifier: commitKeyRecorderID)
        let commitAndSendRecorder = element(in: app, identifier: commitAndSendKeyRecorderID)
        XCTAssertTrue(commitRecorder.waitForExistence(timeout: timeout))

        // @note p0-1406
        XCTAssertEqual(commitRecorder.placeholderValue, idlePlaceholder)
        XCTAssertEqual(recorderDisplayText(commitAndSendRecorder), "⌘↩")

        // @note p0-1407
        app.typeKey("k", modifierFlags: [.command])
        XCTAssertEqual(commitRecorder.placeholderValue, idlePlaceholder)
        XCTAssertNil(recorderDisplayText(commitRecorder))

        // @note p0-1408
        closeSettings(in: app)
        openSettingsFromMenu(in: app)
        let commitRecorderAfterReopen = element(in: app, identifier: commitKeyRecorderID)
        XCTAssertTrue(commitRecorderAfterReopen.waitForExistence(timeout: timeout))
        XCTAssertNil(recorderDisplayText(commitRecorderAfterReopen))
        closeSettings(in: app)
    }

    // AC-27
    // @note p0-1409
    @MainActor
    func testAC27_recordingCancelledByEscOrOutsideClick() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let commitRecorder = element(in: app, identifier: commitKeyRecorderID)
        XCTAssertTrue(commitRecorder.waitForExistence(timeout: timeout))

        // @note p0-1410
        commitRecorder.click()
        XCTAssertEqual(commitRecorder.placeholderValue, recordingPlaceholder)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { commitRecorder.placeholderValue == self.idlePlaceholder })
        XCTAssertNil(recorderDisplayText(commitRecorder))

        // @note p0-1411
        commitRecorder.click()
        XCTAssertEqual(commitRecorder.placeholderValue, recordingPlaceholder)
        let heading = app.descendants(matching: .any)["パネルを出す位置"].firstMatch
        XCTAssertTrue(heading.exists)
        heading.click()
        XCTAssertTrue(waitUntil { commitRecorder.placeholderValue == self.idlePlaceholder })

        // @note p0-1412
        app.typeKey("k", modifierFlags: [.command])
        XCTAssertNil(recorderDisplayText(commitRecorder))

        // @note p0-1413
        commitRecorder.click()
        XCTAssertEqual(commitRecorder.placeholderValue, recordingPlaceholder)
        heading.rightClick()
        XCTAssertTrue(waitUntil { commitRecorder.placeholderValue == self.idlePlaceholder })

        // @note p0-1414
        commitRecorder.click()
        XCTAssertEqual(commitRecorder.placeholderValue, recordingPlaceholder)
        let mainScreen = radio("メインの画面", inPicker: panelScreenPickerID, in: app)
        XCTAssertTrue(mainScreen.exists)
        mainScreen.click()
        XCTAssertTrue(waitUntil { commitRecorder.placeholderValue == self.idlePlaceholder })
        XCTAssertTrue(isChecked(mainScreen))
        XCTAssertNil(recorderDisplayText(commitRecorder))

        // @note p0-1415
        radio("入力欄の近く", inPicker: panelScreenPickerID, in: app).click()
        closeSettings(in: app)
    }

    // AC-6
    // @note p0-1416
    // AC-32
    // @note p0-1417
    @MainActor
    func testAC6_AC32_panelScreenDefaultOrderAndChangeScenario() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let panelScreenPicker = element(in: app, identifier: panelScreenPickerID)
        XCTAssertTrue(panelScreenPicker.waitForExistence(timeout: timeout))

        // AC-32
        // @note p0-1419
        let titlesInOrder = ["入力欄の近く", "挿入先のウィンドウがある画面", "マウスのある画面", "メインの画面"]
        let nearFocusedField = radio("入力欄の近く", inPicker: panelScreenPickerID, in: app)
        XCTAssertTrue(nearFocusedField.waitForExistence(timeout: timeout))
        XCTAssertEqual(panelScreenPicker.radioButtons.count, titlesInOrder.count)
        let radiosInOrder = titlesInOrder.map { radio($0, inPicker: panelScreenPickerID, in: app) }
        for (title, element) in zip(titlesInOrder, radiosInOrder) {
            XCTAssertTrue(element.exists, title)
        }
        let yPositions = radiosInOrder.map(\.frame.minY)
        XCTAssertEqual(yPositions, yPositions.sorted(), "選択肢が上から \(titlesInOrder) の順に並んでいない")

        // AC-6
        // @note p0-1420
        XCTAssertTrue(isChecked(nearFocusedField))
        let mouseScreen = radio("マウスのある画面", inPicker: panelScreenPickerID, in: app)
        XCTAssertFalse(isChecked(mouseScreen))

        // @note p0-1421
        mouseScreen.click()
        XCTAssertTrue(isChecked(mouseScreen))
        XCTAssertFalse(isChecked(nearFocusedField))
        XCTAssertFalse(isChecked(radio("挿入先のウィンドウがある画面", inPicker: panelScreenPickerID, in: app)))
        XCTAssertFalse(isChecked(radio("メインの画面", inPicker: panelScreenPickerID, in: app)))

        // @note p0-1422
        closeSettings(in: app)
    }

    /// @note p0-1424
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

    /// @note p0-1425
    private let idlePlaceholder = "ショートカットを記録"
    private let recordingPlaceholder = "ショートカットを押す"

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// @note p0-1426
    @MainActor
    private func radio(_ title: String, inPicker identifier: String, in app: XCUIApplication) -> XCUIElement {
        element(in: app, identifier: identifier).radioButtons[title]
    }

    /// @note p0-1427
    @MainActor
    private func recorderDisplayText(_ element: XCUIElement) -> String? {
        guard let value = element.value as? String, !value.isEmpty else { return nil }
        return value
    }

    /// @note p0-1428
    @MainActor
    private func text(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    // @note p0-1429
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
    private func isChecked(_ radioButton: XCUIElement) -> Bool {
        if let value = radioButton.value as? NSNumber {
            return value.boolValue
        }
        return radioButton.isSelected
    }

    /// @note p0-1430
    @MainActor
    private func waitUntil(timeout: TimeInterval? = nil, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout ?? self.timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    /// @note p0-1431
    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        let window = app.windows.containing(.any, identifier: panelScreenPickerID).firstMatch
        XCTAssertTrue(window.exists)
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(element(in: app, identifier: panelScreenPickerID).waitForNonExistence(timeout: timeout))
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

    // @note p0-1432
    @MainActor
    private func openSettingsFromMenu(in app: XCUIApplication) {
        openMenu(in: app)
        let item = menuItem(in: app, identifier: "menu.settings", title: "設定")
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        clickShownMenuItem(item)
        app.revealInSettings(element(in: app, identifier: panelScreenPickerID))
    }

    @MainActor
    private func openPanelFromMenu(in app: XCUIApplication) {
        openMenu(in: app)
        let item = menuItem(in: app, identifier: "menu.openPanel", title: "パネルを開く")
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        clickShownMenuItem(item)
    }

    // @note p0-1433
    @MainActor
    private func clickShownMenuItem(_ item: XCUIElement) {
        let deadline = Date().addingTimeInterval(timeout)
        while item.frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(item.frame.isEmpty, "メニューが表示されていない(項目の枠が空)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    // @note p0-1434
    @MainActor
    private func menuItem(in app: XCUIApplication, identifier: String, title: String) -> XCUIElement {
        let byIdentifier = app.menuItems[identifier]
        if byIdentifier.exists {
            return byIdentifier
        }
        return app.menuItems[title]
    }
}
