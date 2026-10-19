import XCTest

final class SettingsRestoreUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-47
    @MainActor
    func testAC47_componentsShowSeededValues() throws {
        let app = launchApp(seed: [
            "appTheme": "dark",
            "autoShowMode": "selectedApps",
            "panelScreen": "mouse",
            "hiddenPanelStatusItems": ["characterCount"],
        ])
        openSettingsFromMenu(in: app)

        let themePicker = element(in: app, identifier: "settings.themePicker")
        app.revealInSettings(themePicker)
        XCTAssertTrue(isOn(segment("ダーク", in: themePicker)), "テーマの「ダーク」が選ばれていない")
        XCTAssertFalse(isOn(segment("システム", in: themePicker)))
        XCTAssertFalse(isOn(segment("ライト", in: themePicker)))

        selectSection("keys", waitingFor: "settings.autoShowModePicker", in: app)
        let autoShowPicker = element(in: app, identifier: "settings.autoShowModePicker")
        app.revealInSettings(autoShowPicker)
        XCTAssertTrue(isOn(segment("選んだアプリのみ", in: autoShowPicker)), "自動表示の「選んだアプリのみ」が選ばれていない")
        XCTAssertFalse(isOn(segment("オフ", in: autoShowPicker)))
        XCTAssertFalse(isOn(segment("全アプリ", in: autoShowPicker)))

        selectSection("panel", waitingFor: "settings.panelScreenPicker", in: app)
        let mouse = element(in: app, identifier: "settings.panelScreen.mouse")
        XCTAssertTrue(mouse.waitForExistence(timeout: timeout))
        XCTAssertTrue(mouse.isSelected, "パネルを出す位置の「マウスの近く」が選ばれていない")
        XCTAssertFalse(element(in: app, identifier: "settings.panelScreen.nearFocusedField").isSelected)

        let characterCount = element(in: app, identifier: "settings.statusItem.characterCount")
        app.revealInSettings(characterCount)
        XCTAssertFalse(isOn(characterCount), "帯の「文字数」が切になっていない")
        let lineCount = element(in: app, identifier: "settings.statusItem.lineCount")
        app.revealInSettings(lineCount)
        XCTAssertTrue(isOn(lineCount), "種にしていない帯の項目が入になっていない")

        closeSettings(in: app)
    }

    // MARK: - 起動

    @MainActor
    private func launchApp(seed: [String: Any]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        if let data = try? JSONSerialization.data(withJSONObject: seed, options: [.sortedKeys]) {
            app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = String(decoding: data, as: UTF8.self)
        }
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        app.launch()
        app.dismissPermissionGuideIfPresent(timeout: 0.5)
        return app
    }

    // MARK: - 要素の探し方

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func segment(_ name: String, in picker: XCUIElement) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ OR title == %@", name, name)
        return picker.descendants(matching: .any).matching(predicate).firstMatch
    }

    @MainActor
    private func isOn(_ element: XCUIElement) -> Bool {
        if let value = element.value as? NSNumber {
            return value.boolValue
        }
        return element.isSelected
    }

    @MainActor
    private func selectSection(_ rawValue: String, waitingFor identifier: String, in app: XCUIApplication) {
        let button = element(in: app, identifier: "settings.sidebar.\(rawValue)")
        XCTAssertTrue(button.waitForExistence(timeout: timeout))
        button.click()
        XCTAssertTrue(element(in: app, identifier: identifier).waitForExistence(timeout: timeout))
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
