import XCTest

final class PanelAnimationUITests: XCTestCase {
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
    func testAC5_animationModePickerSwitches() throws {
        let app = launchApp()

        openSettingsFromMenu(in: app)
        let picker = element(in: app, identifier: animationPickerID)
        app.revealInSettings(picker)
        XCTAssertTrue(picker.waitForExistence(timeout: timeout), "アニメーションの選択が無い")
        for name in ["システム", "オン", "オフ"] {
            XCTAssertTrue(segment(name, in: picker).exists, "「\(name)」の選択肢が無い")
        }

        segment("オフ", in: picker).click()
        XCTAssertTrue(waitUntil { self.isChecked(self.segment("オフ", in: picker)) }, "「オフ」を押しても選ばれない")

        segment("システム", in: picker).click()
        XCTAssertTrue(waitUntil { self.isChecked(self.segment("システム", in: picker)) }, "「システム」を押しても選ばれない")

        segment("オン", in: picker).click()
        XCTAssertTrue(waitUntil { self.isChecked(self.segment("オン", in: picker)) }, "「オン」を押しても選ばれない")

        element(in: app, identifier: sidebarPanelID).click()
        XCTAssertTrue(element(in: app, identifier: "settings.panelScreenPicker").waitForExistence(timeout: timeout))
        XCTAssertFalse(element(in: app, identifier: "settings.panelAnimationToggle").exists, "「パネルの開閉エフェクト」が残っている")

        closeSettings(in: app)
    }

    // AC-16
    @MainActor
    func testAC16_openAndCloseWithAnimation() throws {
        let app = launchApp()
        let textView = app.textViews["promptPanel.textView"]

        let panel = openPanel(in: app)
        waitForSteadyFrame(of: panel)
        app.typeText("abc")
        XCTAssertEqual(textView.promptPanelText, "abc")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout), "esc で閉じない")

        let reopenedForButton = openPanel(in: app)
        waitForSteadyFrame(of: reopenedForButton)
        app.typeText("d")
        XCTAssertEqual(textView.promptPanelText, "abcd")
        let closeButton = app.buttons["promptPanel.closeButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: timeout))
        closeButton.click()
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout), "× ボタンで閉じない")

        let reopenedForHideKey = openPanel(in: app)
        waitForSteadyFrame(of: reopenedForHideKey)
        app.typeText("e")
        XCTAssertEqual(textView.promptPanelText, "abcde")
        app.typeKey("h", modifierFlags: [.command])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout), "⌘H で閉じない")
    }

    // MARK: - 起動と要素の探し方(PanelCloseButtonUITests・SettingsUITests と同じ方法)

    private let animationPickerID = "settings.animationModePicker"
    private let sidebarGeneralID = "settings.sidebar.general"
    private let sidebarPanelID = "settings.sidebar.panel"

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launch()
        return app
    }

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
    private func isChecked(_ element: XCUIElement) -> Bool {
        if let value = element.value as? NSNumber {
            return value.boolValue
        }
        return element.isSelected
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
    private func waitForSteadyFrame(of element: XCUIElement) {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = element.frame
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let current = element.frame
            if current == previous {
                return
            }
            previous = current
        }
        XCTFail("パネルの枠が止まらない")
    }

    @MainActor
    private func openPanel(in app: XCUIApplication) -> XCUIElement {
        openPanelFromMenu(in: app)
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForExistence(timeout: timeout))
        let panel = app.dialogs["promptPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: timeout), "パネルの窓が見つからない")
        return panel
    }

    @MainActor
    private func openSettingsFromMenu(in app: XCUIApplication) {
        openMenu(in: app)
        let item = menuItem(in: app, identifier: "menu.settings", title: "設定")
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        clickShownMenuItem(item)
        let generalSection = element(in: app, identifier: sidebarGeneralID)
        XCTAssertTrue(generalSection.waitForExistence(timeout: timeout))
        generalSection.click()
        XCTAssertTrue(element(in: app, identifier: animationPickerID).waitForExistence(timeout: timeout))
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
