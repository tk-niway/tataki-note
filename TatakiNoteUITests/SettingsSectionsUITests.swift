import XCTest

final class SettingsSectionsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-4
    // AC-5
    // AC-6
    @MainActor
    func testAC4_AC5_AC6_sectionContents() throws {
        let app = XCUIApplication()
        launch(app)
        openSettingsFromMenu(in: app)

        // AC-4
        let generalOrder = [
            "settings.autoShowModePicker",
            "settings.autoShowAppList",
            "settings.themePicker",
            "settings.launchAtLoginToggle",
            "settings.hideMenuBarIconToggle",
        ]
        assertAppearInOrder(generalOrder, in: app)
        for identifier in [
            "settings.hotkeyRecorder",
            "settings.commitKeyRecorder",
            "settings.commitAndSendKeyRecorder",
            "settings.panelScreenPicker",
        ] {
            XCTAssertFalse(element(in: app, identifier: identifier).exists, identifier)
        }
        XCTAssertFalse(app.descendants(matching: .any)["パネルを開く・閉じる"].firstMatch.exists)

        // AC-5
        element(in: app, identifier: "settings.sidebar.keys").click()
        XCTAssertTrue(element(in: app, identifier: "settings.commitKeyRecorder").waitForExistence(timeout: timeout))
        let hotkey = hotkeyRecorder(in: app)
        XCTAssertTrue(hotkey.exists)
        let keysOrder = [
            "settings.commitKeyRecorder",
            "settings.commitAndSendKeyRecorder",
            "settings.shortcutList",
        ]
        for identifier in keysOrder {
            XCTAssertTrue(element(in: app, identifier: identifier).exists, identifier)
        }
        let keyFrames = [hotkey] + keysOrder.map { element(in: app, identifier: $0) }
        let keyYPositions = keyFrames.map(\.frame.minY)
        XCTAssertEqual(keyYPositions, keyYPositions.sorted(), "「キー」の項目が上から ホットキー・確定キー・確定+送信キー・ショートカットキー の順に並んでいない")
        XCTAssertEqual(Set(keyYPositions).count, keyYPositions.count)
        for identifier in ["settings.panelScreenPicker", "settings.fontName"] {
            XCTAssertFalse(element(in: app, identifier: identifier).exists, identifier)
        }

        // AC-6
        element(in: app, identifier: "settings.sidebar.panel").click()
        XCTAssertTrue(element(in: app, identifier: "settings.panelScreenPicker").waitForExistence(timeout: timeout))
        let panelOrder = [
            "settings.panelScreenPicker",
            "settings.fontName",
            "settings.fontSizeStepper",
            "settings.opacitySlider",
            "settings.panelDefaultWidthField",
            "settings.statusItem.close",
        ]
        assertAppearInOrder(panelOrder, in: app)
        for identifier in ["settings.commitKeyRecorder", "settings.shortcutList"] {
            XCTAssertFalse(element(in: app, identifier: identifier).exists, identifier)
        }

        closeSettings(in: app)
    }

    @MainActor
    private func launch(_ app: XCUIApplication) {
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        app.launch()
        app.dismissPermissionGuideIfPresent(timeout: 0.5)
    }

    // MARK: - 設定画面の部品

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func assertAppearInOrder(
        _ identifiers: [String],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for identifier in identifiers {
            XCTAssertTrue(
                element(in: app, identifier: identifier).waitForExistence(timeout: timeout),
                identifier,
                file: file,
                line: line
            )
        }
        let yPositions = identifiers.map { element(in: app, identifier: $0).frame.minY }
        XCTAssertEqual(yPositions, yPositions.sorted(), "\(identifiers) の順に並んでいない", file: file, line: line)
        XCTAssertEqual(Set(yPositions).count, yPositions.count, file: file, line: line)
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
            format: "identifier != %@ AND identifier != %@", "settings.commitKeyRecorder", "settings.commitAndSendKeyRecorder"
        )
        return app.searchFields.matching(notCommitRecorders).firstMatch
    }

    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        let window = app.windows.containing(.any, identifier: "settings.sidebar.general").firstMatch
        XCTAssertTrue(window.exists)
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(element(in: app, identifier: "settings.sidebar.general").waitForNonExistence(timeout: timeout))
    }

    // MARK: - メニューバー

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
        XCTAssertTrue(element(in: app, identifier: "settings.sidebar.general").waitForExistence(timeout: timeout))
    }
}
