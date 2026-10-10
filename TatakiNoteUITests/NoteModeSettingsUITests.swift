import XCTest

final class NoteModeSettingsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    private let toggleID = "settings.appModeToggle"
    private let sidebarIDs = [
        "settings.sidebar.general",
        "settings.sidebar.keys",
        "settings.sidebar.panel",
        "settings.sidebar.appInfo",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-19
    @MainActor
    func testAC19_appModeToggleIsInEverySectionAndSwitchesImmediately() throws {
        let app = try launchApp(seed: nil)
        openSettingsFromMenu(in: app)

        for identifier in sidebarIDs {
            element(in: app, identifier: identifier).click()
            XCTAssertTrue(element(in: app, identifier: toggleID).waitForExistence(timeout: timeout), "\(identifier) を開いたときにトグルが無い")
        }

        element(in: app, identifier: "settings.sidebar.keys").click()
        XCTAssertTrue(element(in: app, identifier: "settings.commitKeyRecorder").waitForExistence(timeout: timeout))
        selectMode(.note, in: app)
        XCTAssertTrue(element(in: app, identifier: "settings.commitKeyRecorder").waitForNonExistence(timeout: timeout))
        XCTAssertTrue(element(in: app, identifier: toggleID).exists)

        closeSettings(in: app)
    }

    // AC-20
    @MainActor
    func testAC20_noteModeHidesCommitKeyRecorders() throws {
        let app = try launchApp(seed: ["appMode": "note"])
        openSettingsFromMenu(in: app)
        element(in: app, identifier: "settings.sidebar.keys").click()

        XCTAssertTrue(element(in: app, identifier: "settings.hotkeyRecorder").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(in: app, identifier: "settings.shortcutList").exists)
        XCTAssertFalse(element(in: app, identifier: "settings.commitKeyRecorder").exists)
        XCTAssertFalse(element(in: app, identifier: "settings.commitAndSendKeyRecorder").exists)

        selectMode(.insert, in: app)
        XCTAssertTrue(element(in: app, identifier: "settings.commitKeyRecorder").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(in: app, identifier: "settings.commitAndSendKeyRecorder").exists)
        XCTAssertTrue(element(in: app, identifier: "settings.hotkeyRecorder").exists)
        XCTAssertTrue(element(in: app, identifier: "settings.shortcutList").exists)

        closeSettings(in: app)
    }

    // AC-21
    // AC-23
    @MainActor
    func testAC21_AC23_noteModeDisablesNearFocusedFieldAndOutline() throws {
        let app = try launchApp(seed: ["appMode": "note"])
        openSettingsFromMenu(in: app)
        element(in: app, identifier: "settings.sidebar.panel").click()

        // AC-21
        let picker = element(in: app, identifier: "settings.panelScreenPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: timeout))
        let nearFocusedField = picker.radioButtons["入力欄の近く"]
        let mouse = picker.radioButtons["マウスのある画面"]
        XCTAssertTrue(nearFocusedField.waitForExistence(timeout: timeout))
        XCTAssertTrue(mouse.exists)
        XCTAssertFalse(nearFocusedField.isEnabled)
        XCTAssertTrue(mouse.isEnabled)
        XCTAssertTrue(element(in: app, identifier: "settings.noteModeReason.nearFocusedField").exists)
        mouse.click()
        XCTAssertTrue(waitUntil { self.isChecked(mouse) })

        // AC-23
        let outline = element(in: app, identifier: "settings.insertionTargetOutlineToggle")
        app.revealInSettings(outline)
        XCTAssertFalse(outline.isEnabled)
        XCTAssertTrue(element(in: app, identifier: "settings.noteModeReason.insertionTargetOutline").exists)
        XCTAssertTrue(element(in: app, identifier: "settings.statusItemNote.commit").exists)
        XCTAssertTrue(element(in: app, identifier: "settings.statusItemNote.lineBreak").exists)

        selectMode(.insert, in: app)
        XCTAssertTrue(element(in: app, identifier: "settings.noteModeReason.insertionTargetOutline").waitForNonExistence(timeout: timeout))
        XCTAssertTrue(element(in: app, identifier: "settings.noteModeReason.nearFocusedField").waitForNonExistence(timeout: timeout))
        XCTAssertTrue(outline.isEnabled)
        XCTAssertTrue(nearFocusedField.isEnabled)

        closeSettings(in: app)
    }

    // AC-22
    @MainActor
    func testAC22_noteModeDisablesAutoShow() throws {
        let app = try launchApp(seed: ["appMode": "note", "autoShowMode": "selectedApps"])
        openSettingsFromMenu(in: app)
        element(in: app, identifier: "settings.sidebar.general").click()

        let picker = element(in: app, identifier: "settings.autoShowModePicker")
        let list = element(in: app, identifier: "settings.autoShowAppList")
        let addButton = element(in: app, identifier: "settings.autoShowAppAdd")
        let removeButton = element(in: app, identifier: "settings.autoShowAppRemove")
        XCTAssertTrue(picker.waitForExistence(timeout: timeout))
        XCTAssertTrue(list.exists)
        XCTAssertTrue(addButton.exists)
        XCTAssertFalse(app.radioButtons["オフ"].isEnabled)
        XCTAssertFalse(app.radioButtons["全アプリ"].isEnabled)
        XCTAssertFalse(app.radioButtons["選んだアプリのみ"].isEnabled)
        XCTAssertFalse(list.isEnabled)
        XCTAssertFalse(addButton.isEnabled)
        XCTAssertFalse(removeButton.isEnabled)
        XCTAssertTrue(element(in: app, identifier: "settings.noteModeReason.autoShow").exists)

        selectMode(.insert, in: app)
        XCTAssertTrue(element(in: app, identifier: "settings.noteModeReason.autoShow").waitForNonExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { addButton.isEnabled })
        XCTAssertTrue(list.isEnabled)
        XCTAssertTrue(app.radioButtons["オフ"].isEnabled)
        XCTAssertTrue(app.radioButtons["全アプリ"].isEnabled)
        XCTAssertTrue(app.radioButtons["選んだアプリのみ"].isEnabled)
        XCTAssertFalse(removeButton.isEnabled)

        closeSettings(in: app)
    }

    // MARK: - モードのトグル

    private enum Mode {
        case insert
        case note

        var identifier: String {
            switch self {
            case .insert: "settings.appMode.insert"
            case .note: "settings.appMode.note"
            }
        }

        var shortName: String {
            switch self {
            case .insert: "インサート"
            case .note: "ノート"
            }
        }
    }

    @MainActor
    private func selectMode(_ mode: Mode, in app: XCUIApplication) {
        let byIdentifier = element(in: app, identifier: mode.identifier)
        if byIdentifier.waitForExistence(timeout: 1) {
            byIdentifier.click()
            return
        }
        let toggle = element(in: app, identifier: toggleID)
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout))
        let predicate = NSPredicate(format: "label CONTAINS %@ OR title CONTAINS %@", mode.shortName, mode.shortName)
        let byName = toggle.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(byName.waitForExistence(timeout: timeout), "トグルの選択肢「\(mode.shortName)」が無い")
        byName.click()
    }

    // MARK: - 起動と要素の探し方

    @MainActor
    private func launchApp(seed: [String: Any]?) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        if let seed {
            let data = try JSONSerialization.data(withJSONObject: seed, options: [.sortedKeys])
            app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = String(decoding: data, as: UTF8.self)
        }
        app.launch()
        app.dismissPermissionGuideIfPresent(timeout: 0.5)
        return app
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func isChecked(_ radioButton: XCUIElement) -> Bool {
        if let value = radioButton.value as? NSNumber {
            return value.boolValue
        }
        return radioButton.isSelected
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
        let window = app.windows.containing(.any, identifier: "settings.sidebar.general").firstMatch
        XCTAssertTrue(window.exists)
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(element(in: app, identifier: "settings.sidebar.general").waitForNonExistence(timeout: timeout))
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
        XCTAssertTrue(element(in: app, identifier: "settings.sidebar.general").waitForExistence(timeout: timeout))
    }
}
