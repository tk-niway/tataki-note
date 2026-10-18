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

    // AC-31
    @MainActor
    func testAC31_commandKOpensSearchAndEscReturnsToBody() throws {
        let app = try launchApp()
        _ = openPanel(in: app)
        let body = textView(in: app)

        app.typeText("first")
        pressCommand("s", in: app)
        pressCommand("n", in: app)
        XCTAssertTrue(waitUntil { body.promptPanelText.isEmpty })
        app.typeText("second")
        pressCommand("s", in: app)
        pressCommand("n", in: app)
        XCTAssertTrue(waitUntil { body.promptPanelText.isEmpty })

        pressCommand("k", in: app)
        let search = element(in: app, identifier: "sidebar.searchField")
        XCTAssertTrue(search.waitForExistence(timeout: timeout), "⌘K でサイドバーの検索欄が出ない")
        XCTAssertTrue(row(in: app, containing: "first").waitForExistence(timeout: timeout))
        app.typeText("fir")
        XCTAssertTrue(waitUntil { (search.value as? String) == "fir" }, "検索欄に打てない")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil { body.promptPanelText == "first" }, "↩ で選んだ下書きがパネルに入らない")

        pressCommand("k", in: app)
        pressCommand("n", in: app)
        XCTAssertTrue(waitUntil { body.promptPanelText.isEmpty }, "検索欄にフォーカスがあるときに ⌘N が効かない")

        pressCommand("k", in: app)
        app.typeKey(.escape, modifierFlags: [])
        app.typeText("z")
        XCTAssertTrue(waitUntil { body.promptPanelText == "z" }, "esc で本文に戻って打てない")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(body.waitForNonExistence(timeout: timeout), "本文で esc を押してもパネルが閉じない")
    }

    // AC-36
    @MainActor
    func testAC36_savedDraftShowsRowAndRightClickDeletes() throws {
        let app = try launchApp(history: ["history one"])
        _ = openPanel(in: app)
        let body = textView(in: app)

        openSidebar(in: app)
        let historyTab = element(in: app, identifier: "sidebar.tab.history")
        XCTAssertTrue(historyTab.waitForExistence(timeout: timeout))
        historyTab.click()
        let historyRow = row(in: app, containing: "history one")
        XCTAssertTrue(historyRow.waitForExistence(timeout: timeout), "履歴の行が出ない")
        historyRow.click()
        XCTAssertTrue(waitUntil { body.promptPanelText == "history one" }, "履歴の行を選んでも本文に入らない")

        pressCommand("n", in: app)
        XCTAssertTrue(waitUntil { body.promptPanelText.isEmpty }, "⌘N で本文が空にならない")

        app.typeText("draft one")
        pressCommand("s", in: app)
        element(in: app, identifier: "sidebar.tab.drafts").click()
        let draftRow = row(in: app, containing: "draft one")
        XCTAssertTrue(draftRow.waitForExistence(timeout: timeout), "保存した下書きの行が出ない")
        XCTAssertFalse(app.buttons["sidebar.deleteButton"].exists, "行にゴミ箱のボタンが出ている")

        // AC-4
        draftRow.rightClick()
        let byIdentifier = app.menuItems["sidebar.row.deleteMenuItem"]
        let menuItem = byIdentifier.waitForExistence(timeout: 2) ? byIdentifier : app.menuItems["削除"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: timeout), "右クリックのメニューに削除が出ない")
        let menuItemTitle = menuItem.title.isEmpty ? menuItem.label : menuItem.title
        XCTAssertEqual(menuItemTitle, "削除", "削除の項目の題が「削除」でない")
        menuItem.click()

        XCTAssertTrue(draftRow.waitForNonExistence(timeout: timeout), "削除しても行が消えない")
        XCTAssertFalse(element(in: app, identifier: "sidebar.deleteConfirmation").exists, "削除の確認が出ている")
        XCTAssertEqual(body.promptPanelText, "draft one", "削除で本文が消えた")
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
