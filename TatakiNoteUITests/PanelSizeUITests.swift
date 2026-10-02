import XCTest

final class PanelSizeUITests: XCTestCase {
    private let timeout: TimeInterval = 5
    private let tolerance: CGFloat = 2
    private let defaultSize = CGSize(width: 520, height: 340)

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    @MainActor
    func testAC16_defaultSizeFromSettings() throws {
        let seededSize = CGSize(width: 600, height: 400)
        let app = makeApp()
        try seedDefaultPanelSize(seededSize, in: app)
        app.launch()

        // AC-16
        let panel = openPanel(in: app)
        assertSize(panel.frame.size, equals: seededSize, "設定の既定の大きさで開かない")
        closePanel(in: app)
    }

    @MainActor
    func testAC1_AC3_typingDoesNotChangePanelSize() throws {
        let app = makeApp()
        app.launch()

        let panel = openPanel(in: app)
        assertSize(panel.frame.size, equals: defaultSize)
        let frameBefore = panel.frame

        // AC-1
        typeLines(30, in: app)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(panel.frame, frameBefore, "行が増えるとパネルの枠が変わってしまう")

        // AC-3
        let textView = app.textViews["promptPanel.textView"]
        app.typeText("end")
        XCTAssertTrue((textView.value as? String)?.hasSuffix("end") == true, "打った文字が下書きに反映されない")
        XCTAssertEqual(panel.frame, frameBefore, "文字を打ってもパネルの枠が変わってしまう")

        closePanel(in: app)
    }

    // AC-2
    @MainActor
    func testAC2_openingHeightIgnoresDraftLength() throws {
        let app = makeApp()
        app.launch()

        let panel = openPanel(in: app)
        assertSize(panel.frame.size, equals: defaultSize)
        typeLines(30, in: app)

        closePanel(in: app)
        let reopened = openPanel(in: app)
        assertSize(reopened.frame.size, equals: defaultSize, "下書きが多いと既定の大きさで開かない")
        XCTAssertTrue((app.textViews["promptPanel.textView"].value as? String)?.isEmpty == false, "下書きが残っていない")

        clearText(in: app)
        closePanel(in: app)
    }

    @MainActor
    func testAC1_dragResize() throws {
        let app = makeApp()
        app.launch()

        let panel = openPanel(in: app)
        let initialSize = panel.frame.size

        dragBottomRightCorner(of: panel, by: CGVector(dx: -100, dy: -60))
        assertSize(panel.frame.size, equals: CGSize(width: initialSize.width - 100, height: initialSize.height - 60))
        dragBottomRightCorner(of: panel, by: CGVector(dx: 100, dy: 60))
        assertSize(panel.frame.size, equals: initialSize)

        dragBottomRightCorner(of: panel, by: CGVector(dx: -700, dy: -500))
        XCTAssertGreaterThanOrEqual(panel.frame.width, 320 - 0.5)
        XCTAssertGreaterThanOrEqual(panel.frame.height, 160 - 0.5)
        assertSize(panel.frame.size, equals: CGSize(width: 320, height: 160))
        let draggedSize = panel.frame.size

        // AC-6
        closePanel(in: app)
        let reopened = openPanel(in: app)
        assertSize(reopened.frame.size, equals: draggedSize)
        closePanel(in: app)
    }

    // AC-4
    @MainActor
    func testAC4_draggedSizeIsUnaffectedByTextChanges() throws {
        let app = makeApp()
        app.launch()

        let panel = openPanel(in: app)
        let initialSize = panel.frame.size

        dragBottomRightCorner(of: panel, by: CGVector(dx: -80, dy: -80))
        let draggedSize = panel.frame.size
        XCTAssertLessThan(draggedSize.height, initialSize.height - tolerance)

        typeLines(30, in: app)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        assertSize(panel.frame.size, equals: draggedSize, "文章を増やすとドラッグした大きさが変わってしまう")

        clearText(in: app)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        assertSize(panel.frame.size, equals: draggedSize, "文章を消すとドラッグした大きさが変わってしまう")

        closePanel(in: app)
        let reopened = openPanel(in: app)
        assertSize(reopened.frame.size, equals: draggedSize, "閉じて開き直すとドラッグした大きさが保たれない")
        closePanel(in: app)
    }

    // AC-14
    @MainActor
    func testAC14_doubleClickTitleBarDoesNotZoom() throws {
        let app = makeApp()
        app.launch()

        let panel = openPanel(in: app)
        let frameBefore = panel.frame

        panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 14)).doubleClick()
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        XCTAssertEqual(panel.frame, frameBefore)
        closePanel(in: app)
    }

    // MARK: - 補助

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        return app
    }

    private func seedDefaultPanelSize(_ size: CGSize, in app: XCUIApplication) throws {
        let values: [String: Any] = ["panelDefaultWidth": Double(size.width), "panelDefaultHeight": Double(size.height)]
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = String(decoding: data, as: UTF8.self)
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
    private func closePanel(in app: XCUIApplication) {
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.textViews["promptPanel.textView"].waitForNonExistence(timeout: timeout))
    }

    @MainActor
    private func typeLines(_ count: Int, in app: XCUIApplication) {
        for _ in 0..<count {
            app.typeText("a")
            app.typeKey(.return, modifierFlags: [])
        }
    }

    @MainActor
    private func clearText(in app: XCUIApplication) {
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(app.textViews["promptPanel.textView"].value as? String, "")
    }

    @MainActor
    private func dragBottomRightCorner(of panel: XCUIElement, by offset: CGVector) {
        let corner = panel.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.press(forDuration: 0.5, thenDragTo: corner.withOffset(offset))
    }

    private func assertSize(
        _ size: CGSize,
        equals expected: CGSize,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(size.width, expected.width, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(size.height, expected.height, accuracy: tolerance, message, file: file, line: line)
    }

    // MARK: - 要素の探し方(PromptPanelUITests と同じ方法)

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
        let item = openPanelMenuItem(in: app)
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
    private func openPanelMenuItem(in app: XCUIApplication) -> XCUIElement {
        let byIdentifier = app.menuItems["menu.openPanel"]
        if byIdentifier.exists {
            return byIdentifier
        }
        return app.menuItems["パネルを開く"]
    }
}
