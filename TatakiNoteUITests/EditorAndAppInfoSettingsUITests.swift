import XCTest

// @note p0-1166
final class EditorAndAppInfoSettingsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    /// @note p0-1167
    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-1
    // @note p0-1168
    @MainActor
    func testAC1_sidebar() throws {
        let app = XCUIApplication()
        launch(app)

        openSettingsFromMenu(in: app)
        let general = element(in: app, identifier: sidebarGeneralID)
        let editor = element(in: app, identifier: sidebarEditorID)
        let appInfo = element(in: app, identifier: sidebarAppInfoID)
        XCTAssertTrue(general.waitForExistence(timeout: timeout))
        XCTAssertTrue(editor.exists)
        XCTAssertTrue(appInfo.exists)
        // @note p0-1169
        XCTAssertLessThan(general.frame.minY, editor.frame.minY)
        XCTAssertLessThan(editor.frame.minY, appInfo.frame.minY)
        XCTAssertTrue(isSidebarItemSelected(sidebarGeneralID, in: app))

        // @note p0-1170
        editor.click()
        XCTAssertTrue(element(in: app, identifier: fontNameID).waitForExistence(timeout: timeout))
        XCTAssertTrue(isSidebarItemSelected(sidebarEditorID, in: app))

        // @note p0-1171
        appInfo.click()
        XCTAssertTrue(element(in: app, identifier: appInfoVersionID).waitForExistence(timeout: timeout))
        XCTAssertFalse(element(in: app, identifier: fontNameID).exists)

        // @note p0-1172
        closeSettings(in: app)
        openSettingsFromMenu(in: app)
        XCTAssertTrue(element(in: app, identifier: "settings.commitKeyRecorder").waitForExistence(timeout: timeout))
        XCTAssertTrue(isSidebarItemSelected(sidebarGeneralID, in: app))
        XCTAssertFalse(element(in: app, identifier: appInfoVersionID).exists)
        closeSettings(in: app)
    }

    // AC-2
    // @note p0-1173
    // AC-3
    // @note p0-1174
    // AC-4
    // @note p0-1175
    // AC-5
    // @note p0-1176
    @MainActor
    func testAC2_AC3_AC4_AC5_AC6_editorScenario() throws {
        let app = XCUIApplication()
        launch(app, permission: AccessibilityOverride.untrusted)
        openEditorSettings(in: app)

        // AC-4
        // @note p0-1179
        let fontSizeValue = element(in: app, identifier: fontSizeValueID)
        XCTAssertTrue(text(of: fontSizeValue).contains("14"))
        let fontSizeUp = incrementArrow(ofStepper: fontSizeStepperID, in: app)
        app.revealInSettings(fontSizeUp)
        fontSizeUp.click()
        XCTAssertTrue(waitUntil { self.text(of: fontSizeValue).contains("15") }, "文字サイズが 15 pt にならない")

        // AC-5
        // @note p0-1180
        let opacityValue = element(in: app, identifier: opacityValueID)
        XCTAssertEqual(text(of: opacityValue), "100%")
        let opacitySlider = slider(identifier: opacitySliderID, in: app)
        app.revealInSettings(opacitySlider)
        opacitySlider.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertTrue(waitUntil { self.text(of: opacityValue) != "100%" }, "透明度の表示が変わらない")
        let adjustedOpacity = text(of: opacityValue)
        XCTAssertTrue(adjustedOpacity.hasSuffix("%"), adjustedOpacity)

        // AC-6
        // @note p0-1181
        let characterCount = element(in: app, identifier: statusItemID("characterCount"))
        app.revealInSettings(characterCount)
        XCTAssertTrue(isChecked(characterCount))
        characterCount.click()
        XCTAssertTrue(waitUntil { !self.isChecked(characterCount) })

        // @note p0-1182
        let commit = element(in: app, identifier: statusItemID("commit"))
        app.revealInSettings(commit)
        XCTAssertTrue(isChecked(commit))
        XCTAssertTrue(element(in: app, identifier: statusItemNoteID("commit")).exists)
        XCTAssertFalse(element(in: app, identifier: statusItemNoteID("commitAndSend")).exists)
        XCTAssertFalse(element(in: app, identifier: statusItemNoteID("characterCount")).exists)

        closeSettings(in: app)
    }

    // AC-1
    @MainActor
    func testAC1_fontControls() throws {
        let app = XCUIApplication()
        launch(app)
        openEditorSettings(in: app)

        let fontName = element(in: app, identifier: fontNameID)
        app.revealInSettings(fontName)
        XCTAssertEqual(text(of: fontName), "システムフォント")
        let showFontPanel = element(in: app, identifier: showFontPanelID)
        XCTAssertTrue(showFontPanel.exists)
        let resetFont = element(in: app, identifier: resetFontToSystemID)
        XCTAssertTrue(resetFont.exists)
        XCTAssertFalse(element(in: app, identifier: "settings.fontPicker").exists)

        app.revealInSettings(showFontPanel)
        showFontPanel.click()
        XCTAssertTrue(fontPanelWindow(in: app).waitForExistence(timeout: timeout), "フォントパネルが開かない")
        closeSettings(in: app)
    }

    // AC-6
    @MainActor
    func testAC6_resetFontToSystem() throws {
        let app = XCUIApplication()
        launch(app, seed: ["panelFontName": "Menlo-Regular"])
        openEditorSettings(in: app)

        let fontName = element(in: app, identifier: fontNameID)
        app.revealInSettings(fontName)
        XCTAssertTrue(text(of: fontName).contains("Menlo"), text(of: fontName))
        let resetFont = element(in: app, identifier: resetFontToSystemID)
        app.revealInSettings(resetFont)
        XCTAssertTrue(resetFont.isEnabled)

        resetFont.click()
        XCTAssertTrue(waitUntil { self.text(of: fontName) == "システムフォント" }, "名前の表示がシステムフォントにならない")
        XCTAssertTrue(waitUntil { !resetFont.isEnabled }, "システムフォントに戻した後も押せる")
        closeSettings(in: app)
    }

    // AC-11
    @MainActor
    func testAC11_closingSettingsClosesFontPanel() throws {
        let app = XCUIApplication()
        launch(app)
        openEditorSettings(in: app)

        let showFontPanel = element(in: app, identifier: showFontPanelID)
        app.revealInSettings(showFontPanel)
        showFontPanel.click()
        let fontPanel = fontPanelWindow(in: app)
        XCTAssertTrue(fontPanel.waitForExistence(timeout: timeout), "フォントパネルが開かない")

        closeSettings(in: app)
        XCTAssertTrue(fontPanel.waitForNonExistence(timeout: timeout), "設定ウィンドウを閉じてもフォントパネルが残る")
    }

    // AC-7
    // @note p0-1184
    @MainActor
    func testAC7_shortcutList() throws {
        let app = XCUIApplication()
        launch(app)
        openEditorSettings(in: app)

        let list = element(in: app, identifier: shortcutListID)
        XCTAssertTrue(list.waitForExistence(timeout: timeout))
        // @note p0-1185
        let rows = list.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "settings.shortcut."))
            .allElementsBoundByIndex
        XCTAssertEqual(rows.count, 7)
        let rowTexts = rows.map { combinedText(of: $0) }
        for keys in ["⌥↑", "⌘L", "⌘D"] {
            XCTAssertTrue(rowTexts.contains { $0.contains(keys) }, "\(keys) の行が無い: \(rowTexts)")
        }
        // @note p0-1186
        XCTAssertTrue(rowTexts.contains { $0.contains("⌘D") && $0.contains("単語") }, "\(rowTexts)")
        XCTAssertFalse(rowTexts.contains { $0.contains("esc") }, "\(rowTexts)")
        closeSettings(in: app)
    }

    // AC-8
    // @note p0-1187
    // AC-9
    // @note p0-1188
    @MainActor
    func testAC8_AC9_appInfoUntrusted() throws {
        let app = XCUIApplication()
        launch(app, permission: AccessibilityOverride.untrusted)
        openAppInfoSettings(in: app)

        // AC-8
        // @note p0-1189
        let version = text(of: element(in: app, identifier: appInfoVersionID))
        XCTAssertTrue(version.contains { $0.isNumber }, version)
        XCTAssertFalse(version.contains("不明"), version)

        // AC-9
        // @note p0-1190
        XCTAssertTrue(element(in: app, identifier: appInfoPermissionStatusID).exists)
        XCTAssertTrue(element(in: app, identifier: appInfoPermissionStepsID).exists)
        XCTAssertTrue(element(in: app, identifier: appInfoOpenSystemSettingsID).exists)
        closeSettings(in: app)
    }

    // AC-9
    // @note p0-1191
    @MainActor
    func testAC9_appInfoTrusted() throws {
        let app = XCUIApplication()
        launch(app)
        openAppInfoSettings(in: app)

        XCTAssertTrue(element(in: app, identifier: appInfoPermissionStatusID).exists)
        XCTAssertFalse(element(in: app, identifier: appInfoPermissionStepsID).exists)
        XCTAssertFalse(element(in: app, identifier: appInfoOpenSystemSettingsID).exists)
        closeSettings(in: app)
    }

    // AC-12
    // @note p0-1192
    @MainActor
    func testAC12_permissionGuideUnchanged() throws {
        let app = XCUIApplication()
        launch(app, permission: AccessibilityOverride.untrusted, dismissingPermissionGuide: false)

        // @note p0-1193
        XCTAssertTrue(element(in: app, identifier: "permissionGuide.status").waitForExistence(timeout: timeout))
        XCTAssertEqual(guideStatusCount(in: app), 1)

        // @note p0-1194
        openAppInfoSettings(in: app)
        XCTAssertTrue(element(in: app, identifier: appInfoPermissionStatusID).exists)
        XCTAssertTrue(element(in: app, identifier: appInfoPermissionStepsID).exists)

        // @note p0-1195
        XCTAssertEqual(guideStatusCount(in: app), 1)
        XCTAssertTrue(element(in: app, identifier: "permissionGuide.steps").exists)
        XCTAssertTrue(app.buttons["permissionGuide.openSystemSettings"].exists)

        // @note p0-1196
        closeSettings(in: app)
        let closeButton = app.buttons["permissionGuide.close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: timeout))
        closeButton.click()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: timeout))
        XCTAssertEqual(guideStatusCount(in: app), 0)
        openAppInfoSettings(in: app)
        XCTAssertTrue(element(in: app, identifier: appInfoPermissionStatusID).exists)
        closeSettings(in: app)
    }

    // AC-14
    // @note p0-1203
    // AC-15
    // @note p0-1204
    @MainActor
    func testAC14_AC15_useCurrentPanelSizeAndReset() throws {
        let app = XCUIApplication()
        launch(app)
        openEditorSettings(in: app)

        // AC-14
        // @note p0-1205
        let useCurrent = element(in: app, identifier: useCurrentPanelSizeID)
        app.revealInSettings(useCurrent)
        XCTAssertFalse(useCurrent.isEnabled)

        // AC-14
        // @note p0-1206
        let panel = openPanel(in: app)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(useCurrent.isEnabled, "パネルを開いただけで押せる")

        // @note p0-1207
        let sizeBeforeDrag = panel.frame.size
        dragBottomRightCorner(of: panel, by: CGVector(dx: -100, dy: -60))
        let dragged = panel.frame.size
        XCTAssertNotEqual(dragged.width, sizeBeforeDrag.width, accuracy: 1, "ドラッグで幅が変わらない")
        XCTAssertNotEqual(dragged.height, sizeBeforeDrag.height, accuracy: 1, "ドラッグで高さが変わらない")
        closePanel(in: app)

        // AC-14
        // @note p0-1208
        XCTAssertTrue(waitUntil { useCurrent.isEnabled }, "ドラッグした後も押せない")
        app.revealInSettings(useCurrent)
        useCurrent.click()
        let widthField = element(in: app, identifier: widthFieldID)
        let heightField = element(in: app, identifier: heightFieldID)
        XCTAssertTrue(waitUntil { self.number(in: widthField).map { abs($0 - dragged.width) <= 1 } ?? false },
                      "幅がドラッグした大きさにならない(\(String(describing: widthField.value)) / \(dragged.width))")
        XCTAssertTrue(waitUntil { self.number(in: heightField).map { abs($0 - dragged.height) <= 1 } ?? false },
                      "高さがドラッグした大きさにならない(\(String(describing: heightField.value)) / \(dragged.height))")

        // AC-15
        // @note p0-1210
        let reset = element(in: app, identifier: resetPanelDefaultSizeID)
        app.revealInSettings(reset)
        reset.click()
        XCTAssertTrue(waitUntil { widthField.value as? String == "520" })
        XCTAssertTrue(waitUntil { heightField.value as? String == "340" })
        closeSettings(in: app)
    }

    // MARK: - 起動

    /// @note p0-1212
    @MainActor
    private func launch(
        _ app: XCUIApplication,
        permission: String = AccessibilityOverride.trusted,
        dismissingPermissionGuide: Bool = true,
        seed: [String: Any]? = nil
    ) {
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        if let seed, let data = try? JSONSerialization.data(withJSONObject: seed, options: [.sortedKeys]) {
            app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = String(decoding: data, as: UTF8.self)
        }
        app.launchEnvironment[AccessibilityOverride.key] = permission
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        app.launch()
        if dismissingPermissionGuide {
            app.dismissPermissionGuideIfPresent(timeout: permission == AccessibilityOverride.untrusted ? 3 : 0.5)
        }
    }

    // MARK: - 設定画面の部品

    private let sidebarGeneralID = "settings.sidebar.general"
    private let sidebarEditorID = "settings.sidebar.editor"
    private let sidebarAppInfoID = "settings.sidebar.appInfo"
    private let fontNameID = "settings.fontName"
    private let showFontPanelID = "settings.showFontPanel"
    private let resetFontToSystemID = "settings.resetFontToSystem"
    private let fontSizeStepperID = "settings.fontSizeStepper"
    private let fontSizeValueID = "settings.fontSizeValue"
    private let opacitySliderID = "settings.opacitySlider"
    private let opacityValueID = "settings.opacityValue"
    private let widthFieldID = "settings.panelDefaultWidthField"
    private let heightFieldID = "settings.panelDefaultHeightField"
    private let widthStepperID = "settings.panelDefaultWidthStepper"
    private let useCurrentPanelSizeID = "settings.useCurrentPanelSize"
    private let resetPanelDefaultSizeID = "settings.resetPanelDefaultSize"
    private let shortcutListID = "settings.shortcutList"
    private let appInfoVersionID = "settings.appInfo.version"
    private let appInfoPermissionStatusID = "settings.appInfo.permissionStatus"
    private let appInfoPermissionStepsID = "settings.appInfo.permissionSteps"
    private let appInfoOpenSystemSettingsID = "settings.appInfo.openSystemSettings"

    private func statusItemID(_ rawValue: String) -> String {
        "settings.statusItem.\(rawValue)"
    }

    private func statusItemNoteID(_ rawValue: String) -> String {
        "settings.statusItemNote.\(rawValue)"
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// @note p0-1213
    @MainActor
    private func openEditorSettings(in app: XCUIApplication) {
        openSettingsFromMenu(in: app)
        let editor = element(in: app, identifier: sidebarEditorID)
        XCTAssertTrue(editor.waitForExistence(timeout: timeout))
        editor.click()
        XCTAssertTrue(element(in: app, identifier: fontNameID).waitForExistence(timeout: timeout))
    }

    /// @note p0-1214
    @MainActor
    private func openAppInfoSettings(in app: XCUIApplication) {
        openSettingsFromMenu(in: app)
        let appInfo = element(in: app, identifier: sidebarAppInfoID)
        XCTAssertTrue(appInfo.waitForExistence(timeout: timeout))
        appInfo.click()
        XCTAssertTrue(element(in: app, identifier: appInfoVersionID).waitForExistence(timeout: timeout))
    }

    @MainActor
    private func fontPanelWindow(in app: XCUIApplication) -> XCUIElement {
        element(in: app, identifier: "fontPanel")
    }

    /// @note p0-1216
    @MainActor
    private func incrementArrow(ofStepper identifier: String, in app: XCUIApplication) -> XCUIElement {
        let found = element(in: app, identifier: identifier)
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "ステッパーが無い: \(identifier)")
        let stepper = found.elementType == .stepper ? found : found.steppers.firstMatch
        let arrow = stepper.incrementArrows.firstMatch
        XCTAssertTrue(arrow.waitForExistence(timeout: timeout), "ステッパーの上向きの矢印が無い: \(identifier)")
        return arrow
    }

    /// @note p0-1217
    @MainActor
    private func slider(identifier: String, in app: XCUIApplication) -> XCUIElement {
        let found = element(in: app, identifier: identifier)
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "スライダーが無い: \(identifier)")
        return found.elementType == .slider ? found : found.sliders.firstMatch
    }

    /// @note p0-1219
    @MainActor
    private func text(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    /// @note p0-1220
    @MainActor
    private func combinedText(of element: XCUIElement) -> String {
        [element.label, element.value as? String ?? ""].joined(separator: " ")
    }

    /// @note p0-1221
    @MainActor
    private func number(in field: XCUIElement) -> CGFloat? {
        (field.value as? String).flatMap { Double($0) }.map { CGFloat($0) }
    }

    /// @note p0-1222
    @MainActor
    private func isChecked(_ element: XCUIElement) -> Bool {
        if let value = element.value as? NSNumber {
            return value.boolValue
        }
        return element.isSelected
    }

    /// @note p0-1223
    @MainActor
    private func isSidebarItemSelected(_ identifier: String, in app: XCUIApplication) -> Bool {
        if element(in: app, identifier: identifier).isSelected {
            return true
        }
        let containers = [
            app.outlineRows.containing(.any, identifier: identifier).firstMatch,
            app.tableRows.containing(.any, identifier: identifier).firstMatch,
            app.cells.containing(.any, identifier: identifier).firstMatch,
        ]
        return containers.contains { $0.exists && $0.isSelected }
    }

    /// @note p0-1224
    @MainActor
    private func guideStatusCount(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(identifier: "permissionGuide.status").count
    }

    /// @note p0-1225
    @MainActor
    private func settingsWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.containing(.any, identifier: sidebarGeneralID).firstMatch
    }

    /// @note p0-1226
    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        let window = settingsWindow(in: app)
        XCTAssertTrue(window.exists)
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(element(in: app, identifier: sidebarGeneralID).waitForNonExistence(timeout: timeout))
    }

    /// @note p0-1227
    @MainActor
    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    // MARK: - パネル

    /// @note p0-1228
    @MainActor
    private func openPanel(in app: XCUIApplication) -> XCUIElement {
        openPanelFromMenu(in: app)
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForExistence(timeout: timeout))
        // @note p0-1229
        let panel = app.dialogs["promptPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: timeout), "パネルの窓が見つからない")
        return panel
    }

    /// @note p0-1230
    @MainActor
    private func closePanel(in app: XCUIApplication) {
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForNonExistence(timeout: timeout))
    }

    /// @note p0-1231
    @MainActor
    private func dragBottomRightCorner(of panel: XCUIElement, by offset: CGVector) {
        let corner = panel.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.press(forDuration: 0.5, thenDragTo: corner.withOffset(offset))
    }

    // MARK: - メニューバー

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
    }

    @MainActor
    private func openPanelFromMenu(in app: XCUIApplication) {
        openMenu(in: app)
        let item = menuItem(in: app, identifier: "menu.openPanel", title: "パネルを開く")
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        clickShownMenuItem(item)
    }

    // @note p0-1232
    @MainActor
    private func clickShownMenuItem(_ item: XCUIElement) {
        let deadline = Date().addingTimeInterval(timeout)
        while item.frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(item.frame.isEmpty, "メニューが表示されていない(項目の枠が空)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    // @note p0-1233
    @MainActor
    private func menuItem(in app: XCUIApplication, identifier: String, title: String) -> XCUIElement {
        let byIdentifier = app.menuItems[identifier]
        if byIdentifier.exists {
            return byIdentifier
        }
        return app.menuItems[title]
    }
}
