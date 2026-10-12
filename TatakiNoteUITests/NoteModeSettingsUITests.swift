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

    // AC-7
    @MainActor
    func testAC7_appModeToggleIsInEverySectionAndSwitchesImmediately() throws {
        let app = try launchApp(seed: nil)
        openSettingsFromMenu(in: app)

        for identifier in sidebarIDs {
            element(in: app, identifier: identifier).click()
            XCTAssertTrue(element(in: app, identifier: toggleID).waitForExistence(timeout: timeout), "\(identifier) を開いたときにトグルが無い")
        }

        element(in: app, identifier: "settings.sidebar.keys").click()
        let commitRecorder = element(in: app, identifier: "settings.commitKeyRecorder")
        let banner = element(in: app, identifier: "settings.noteModeBanner.insertAndSend")
        XCTAssertTrue(commitRecorder.waitForExistence(timeout: timeout))
        XCTAssertFalse(banner.exists)
        selectMode(.note, in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { !commitRecorder.isEnabled })
        XCTAssertTrue(element(in: app, identifier: toggleID).exists)

        closeSettings(in: app)
    }

    // AC-27
    @MainActor
    func testAC27_noteModeDimsCommitKeyRecorders() throws {
        let app = try launchApp(seed: ["appMode": "note"])
        openSettingsFromMenu(in: app)
        element(in: app, identifier: "settings.sidebar.keys").click()

        let hotkey = element(in: app, identifier: "settings.hotkeyRecorder")
        let commitRecorder = element(in: app, identifier: "settings.commitKeyRecorder")
        let commitAndSendRecorder = element(in: app, identifier: "settings.commitAndSendKeyRecorder")
        let banner = element(in: app, identifier: "settings.noteModeBanner.insertAndSend")
        let switchToInsert = element(in: app, identifier: "settings.noteModeBanner.insertAndSend.switchToInsert")
        XCTAssertTrue(hotkey.waitForExistence(timeout: timeout))
        app.revealInSettings(commitRecorder)
        XCTAssertTrue(commitAndSendRecorder.exists)
        XCTAssertTrue(banner.exists)
        XCTAssertTrue(switchToInsert.exists)
        XCTAssertFalse(commitRecorder.isEnabled)
        XCTAssertFalse(commitAndSendRecorder.isEnabled)
        commitRecorder.click()
        XCTAssertNotEqual(commitRecorder.value as? String, "ショートカットを押す")
        XCTAssertTrue(hotkey.isEnabled)
        XCTAssertTrue(element(in: app, identifier: "settings.shortcutList").exists)

        switchToInsert.click()
        XCTAssertTrue(banner.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { commitRecorder.isEnabled && commitAndSendRecorder.isEnabled })
        XCTAssertTrue(hotkey.isEnabled)

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
        let mouse = picker.radioButtons["マウスの近く"]
        XCTAssertTrue(nearFocusedField.waitForExistence(timeout: timeout))
        XCTAssertTrue(mouse.exists)
        XCTAssertFalse(nearFocusedField.isEnabled)
        XCTAssertTrue(mouse.isEnabled)
        XCTAssertTrue(element(in: app, identifier: "settings.noteModeReason.nearFocusedField").exists)
        XCTAssertTrue(isChecked(mouse))
        XCTAssertFalse(isChecked(nearFocusedField))

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
        XCTAssertTrue(waitUntil { self.isChecked(nearFocusedField) })
        XCTAssertFalse(isChecked(mouse))

        closeSettings(in: app)
    }

    // AC-26
    @MainActor
    func testAC26_noteModeDisablesAutoShow() throws {
        let app = try launchApp(seed: ["appMode": "note", "autoShowMode": "selectedApps"])
        openSettingsFromMenu(in: app)
        element(in: app, identifier: "settings.sidebar.keys").click()

        let picker = element(in: app, identifier: "settings.autoShowModePicker")
        let addButton = element(in: app, identifier: "settings.autoShowAppAdd")
        let banner = element(in: app, identifier: "settings.noteModeBanner.autoShow")
        let switchToInsert = element(in: app, identifier: "settings.noteModeBanner.autoShow.switchToInsert")
        let segmentNames = ["オフ", "全アプリ", "選んだアプリのみ"]
        XCTAssertTrue(picker.waitForExistence(timeout: timeout))
        app.revealInSettings(picker)
        XCTAssertTrue(banner.exists)
        XCTAssertTrue(switchToInsert.exists)
        XCTAssertTrue(addButton.exists)
        for name in segmentNames {
            XCTAssertFalse(segment(name, in: picker).isEnabled, name)
        }
        XCTAssertFalse(addButton.isEnabled)

        switchToInsert.click()
        XCTAssertTrue(banner.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(switchToInsert.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { addButton.isEnabled })
        for name in segmentNames {
            XCTAssertTrue(segment(name, in: picker).isEnabled, name)
        }

        closeSettings(in: app)
    }

    @MainActor
    private func segment(_ name: String, in picker: XCUIElement) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ OR title == %@", name, name)
        return picker.descendants(matching: .any).matching(predicate).firstMatch
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
