import XCTest

final class DraftsSidebarUITests: PanelDraftsUITestCase {
    // AC-30
    @MainActor
    func testAC30_sidebarToggleWidensWindowAndRemembersState() throws {
        let app = try launchApp()
        let panel = openPanel(in: app)
        let closedFrame = panel.frame

        let toggle = app.buttons["promptPanel.sidebarToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout))
        let tab = element(in: app, identifier: "sidebar.tab.drafts")
        XCTAssertFalse(tab.exists, "閉じているのにサイドバーが出ている")

        toggle.click()
        XCTAssertTrue(tab.waitForExistence(timeout: timeout), "サイドバーが出ない")
        XCTAssertTrue(waitUntil { panel.frame.width > closedFrame.width + 150 }, "窓が広がらない")
        XCTAssertEqual(panel.frame.maxX, closedFrame.maxX, accuracy: tolerance, "窓の右端が動いた")
        XCTAssertLessThan(tab.frame.midX, panel.frame.minX + 230, "サイドバーが窓の左側に出ていない")

        toggle.click()
        XCTAssertTrue(tab.waitForNonExistence(timeout: timeout), "サイドバーが消えない")
        XCTAssertTrue(waitUntil { abs(panel.frame.width - closedFrame.width) <= self.tolerance }, "元の幅に戻らない")
        XCTAssertEqual(panel.frame.maxX, closedFrame.maxX, accuracy: tolerance)

        toggle.click()
        XCTAssertTrue(tab.waitForExistence(timeout: timeout))
        app.buttons["promptPanel.closeButton"].click()
        XCTAssertTrue(textView(in: app).waitForNonExistence(timeout: timeout))

        openPanelFromMenu(in: app)
        XCTAssertTrue(textView(in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(
            element(in: app, identifier: "sidebar.tab.drafts").waitForExistence(timeout: timeout),
            "開き直したときにサイドバーが出ていない"
        )
    }

    // AC-40
    @MainActor
    func testAC40_typingContinuesDuringSaveAnimation() throws {
        let app = try launchApp()
        _ = openPanel(in: app)
        let body = textView(in: app)
        XCTAssertFalse(element(in: app, identifier: "sidebar.tab.drafts").exists)

        app.typeText("abc")
        pressCommand("s", in: app)
        app.typeText("def")
        XCTAssertTrue(waitUntil { body.promptPanelText == "abcdef" }, "保存のアニメーション中に本文へ打てない")
    }

    @MainActor
    func testCommandBTogglesSidebar() throws {
        let app = try launchApp()
        _ = openPanel(in: app)
        let tab = element(in: app, identifier: "sidebar.tab.drafts")
        XCTAssertFalse(tab.exists, "閉じているのにサイドバーが出ている")

        pressCommand("b", in: app)
        XCTAssertTrue(tab.waitForExistence(timeout: timeout), "⌘B でサイドバーが出ない")

        pressCommand("b", in: app)
        XCTAssertTrue(tab.waitForNonExistence(timeout: timeout), "⌘B でサイドバーが消えない")
    }

    // AC-20
    @MainActor
    func testAC20_settingsKeepsPanelAndReturnsInput() throws {
        let app = try launchApp(seed: ["panelScreen": "main", "animationMode": "off"])
        let general = element(in: app, identifier: "settings.sidebar.general")
        let settings = app.windows.containing(.any, identifier: "settings.sidebar.general").firstMatch
        let body = textView(in: app)

        _ = openPanel(in: app)
        app.typeText("abc")
        XCTAssertTrue(waitUntil { body.promptPanelText == "abc" }, "パネルに打てない")
        openSidebar(in: app)
        let button = app.buttons["sidebar.settingsButton"]
        XCTAssertTrue(button.waitForExistence(timeout: timeout))
        button.click()
        XCTAssertTrue(general.waitForExistence(timeout: timeout), "歯車のボタンで設定が開かない")
        XCTAssertTrue(body.exists, "設定を開くとパネルが閉じる")
        settings.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(general.waitForNonExistence(timeout: timeout))
        app.typeText("d")
        XCTAssertTrue(waitUntil { body.promptPanelText == "abcd" }, "設定を閉じた後にパネルへ打てない")

        pressCommand(",", in: app)
        XCTAssertTrue(general.waitForExistence(timeout: timeout), "⌘, で設定が開かない")
        XCTAssertTrue(body.exists, "⌘, でパネルが閉じる")
        settings.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(general.waitForNonExistence(timeout: timeout))
        app.typeText("e")
        XCTAssertTrue(waitUntil { body.promptPanelText == "abcde" }, "⌘, で開いた設定を閉じた後にパネルへ打てない")
    }
}
