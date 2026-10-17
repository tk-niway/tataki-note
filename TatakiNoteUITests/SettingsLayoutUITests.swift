import XCTest

final class SettingsLayoutUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    private let sidebarIDs = [
        "settings.sidebar.general",
        "settings.sidebar.keys",
        "settings.sidebar.panel",
        "settings.sidebar.appInfo",
    ]
    private let sidebarTitles = ["一般", "ホットキーとキー操作", "パネル", "情報"]
    private let scrollViewID = "settings.detailScrollView"
    private let detailTitleID = "settings.detailTitle"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-1
    // AC-5
    @MainActor
    func testAC1_AC5_sidebarOrderSelectionAndDetailTitle() throws {
        let app = launchApp()
        openSettingsFromMenu(in: app)

        let buttons = sidebarIDs.map { element(in: app, identifier: $0) }
        for button in buttons {
            XCTAssertTrue(button.waitForExistence(timeout: timeout))
        }
        let ys = buttons.map(\.frame.minY)
        XCTAssertEqual(ys, ys.sorted(), "サイドバーの種類が上から「一般」「ホットキーとキー操作」「パネル」「情報」の順に並んでいない")
        XCTAssertEqual(Set(ys).count, ys.count)

        XCTAssertTrue(waitUntil { self.detailTitle(in: app) == "一般" })
        XCTAssertTrue(buttons[0].isSelected)

        // AC-1
        for index in [2, 1, 3, 0] {
            buttons[index].click()
            XCTAssertTrue(waitUntil { buttons[index].isSelected }, "\(sidebarTitles[index]) が選択中に見えない")
            for (other, button) in buttons.enumerated() where other != index {
                XCTAssertFalse(button.isSelected, "\(sidebarTitles[other]) も選択中に見える")
            }
            XCTAssertTrue(waitUntil { self.detailTitle(in: app) == self.sidebarTitles[index] }, "見出しが「\(self.sidebarTitles[index])」にならない")
        }

        closeSettings(in: app)
    }

    // AC-6
    @MainActor
    func testAC6_switchingSectionStartsAtTop() throws {
        let app = launchApp()
        openSettingsFromMenu(in: app)

        let keys = element(in: app, identifier: "settings.sidebar.keys")
        let panel = element(in: app, identifier: "settings.sidebar.panel")
        let scrollView = element(in: app, identifier: scrollViewID)
        XCTAssertTrue(keys.waitForExistence(timeout: timeout))

        keys.click()
        let hotkey = element(in: app, identifier: "settings.hotkeyRecorder")
        XCTAssertTrue(hotkey.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { self.isVisible(hotkey, in: scrollView) })
        scrollToBottom(scrollView)
        XCTAssertFalse(isVisible(hotkey, in: scrollView), "下までスクロールしたのに「ホットキーとキー操作」の先頭の部品が見えたまま")

        panel.click()
        let screenPicker = element(in: app, identifier: "settings.panelScreenPicker")
        XCTAssertTrue(screenPicker.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { self.isVisible(screenPicker, in: scrollView) }, "「パネル」が先頭から出ない")
        scrollToBottom(scrollView)
        XCTAssertFalse(isVisible(screenPicker, in: scrollView), "下までスクロールしたのに「パネル」の先頭の部品が見えたまま")

        keys.click()
        XCTAssertTrue(waitUntil { self.isVisible(element(in: app, identifier: "settings.hotkeyRecorder"), in: scrollView) }, "「ホットキーとキー操作」が先頭から出ない")

        closeSettings(in: app)
    }

    // MARK: - 起動と要素の探し方

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
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
    private func detailTitle(in app: XCUIApplication) -> String? {
        let title = element(in: app, identifier: detailTitleID)
        guard title.exists else { return nil }
        return (title.value as? String) ?? title.label
    }

    @MainActor
    private func isVisible(_ element: XCUIElement, in scrollView: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let visible = scrollView.frame
        let target = element.frame
        return target.minY >= visible.minY && target.maxY <= visible.maxY
    }

    @MainActor
    private func scrollToBottom(_ scrollView: XCUIElement) {
        for _ in 0..<12 {
            scrollView.scroll(byDeltaX: 0, deltaY: -400)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
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
