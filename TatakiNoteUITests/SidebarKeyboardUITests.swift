import XCTest

final class SidebarKeyboardUITests: PanelDraftsUITestCase {
    // AC-4
    @MainActor
    func testAC4_commandNSwitchesAtOnceWithoutConfirmation() throws {
        let app = try launchApp()
        _ = openPanel(in: app)
        let body = textView(in: app)

        app.typeText("abc")
        pressCommand("n", in: app)

        XCTAssertTrue(waitUntil { body.promptPanelText.isEmpty }, "⌘N で本文が空にならない")
        XCTAssertFalse(element(in: app, identifier: "promptPanel.confirmation").exists, "確認が出ている")

        app.typeText("xyz")
        XCTAssertTrue(waitUntil { body.promptPanelText == "xyz" }, "⌘N の後に入力欄へ打てない")
    }

    // AC-15
    @MainActor
    func testAC15_archivingScratchShowsToastThatDisappears() throws {
        let app = try launchApp()
        _ = openPanel(in: app)
        let body = textView(in: app)

        app.typeText("abc")
        XCTAssertTrue(waitUntil { body.promptPanelText == "abc" })
        pressCommand("n", in: app)

        let toast = element(in: app, identifier: "promptPanel.saveToast")
        XCTAssertTrue(toast.waitForExistence(timeout: 2), "書きかけを履歴に残したトーストが出ない")
        XCTAssertTrue(waitUntil { body.promptPanelText.isEmpty }, "⌘N で本文が空にならない")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 5), "トーストが消えない")
    }

    // AC-32
    @MainActor
    func testAC32_toastIsCenteredInBodyColumn() throws {
        let app = try launchApp()
        let panel = openPanel(in: app)

        app.typeText("abc")
        let saveButton = app.buttons["promptPanel.saveDraftButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { saveButton.isEnabled })
        saveButton.click()

        let toast = element(in: app, identifier: "promptPanel.saveToast")
        XCTAssertTrue(toast.waitForExistence(timeout: 2), "保存のトーストが出ない")
        XCTAssertLessThanOrEqual(abs(toast.frame.midX - panel.frame.midX), 4, "トーストが入力欄の中央に出ていない")
    }

    // AC-18
    // AC-19
    // AC-22
    @MainActor
    func testAC18_arrowKeysShowRowsAndRightArrowReturnsToBody() throws {
        let app = try launchApp()
        _ = openPanel(in: app)
        let body = textView(in: app)

        app.typeText("abc")
        pressCommand("s", in: app)
        pressCommand("n", in: app)
        XCTAssertTrue(waitUntil { body.promptPanelText.isEmpty })
        app.typeText("def")
        pressCommand("s", in: app)
        pressCommand("n", in: app)
        XCTAssertTrue(waitUntil { body.promptPanelText.isEmpty })
        app.typeText("xyz")

        pressCommand("b", in: app)
        XCTAssertTrue(row(in: app, containing: "def").waitForExistence(timeout: timeout), "⌘B でサイドバーが開かない")
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { body.promptPanelText == "def" }, "↓ で先頭の下書きが本文に出ない")
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { body.promptPanelText == "abc" }, "↓ で次の下書きが本文に出ない")
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { body.promptPanelText == "def" }, "↑ で前の下書きが本文に出ない")

        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeText("1")
        XCTAssertTrue(waitUntil { body.promptPanelText == "def1" }, "→ の後に入力欄へ打てない")

        pressCommand("b", in: app)
        XCTAssertTrue(element(in: app, identifier: "sidebar.tab.drafts").waitForNonExistence(timeout: timeout))
        app.typeText("2")
        XCTAssertTrue(waitUntil { body.promptPanelText == "def12" }, "⌘B で閉じた後に入力欄へ打てない")

        pressCommand("b", in: app)
        XCTAssertTrue(row(in: app, containing: "abc").waitForExistence(timeout: timeout))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { body.promptPanelText == "abc" }, "開き直した後の ↓ で本文が替わらない")
        app.typeKey(.return, modifierFlags: [])
        app.typeText("3")
        XCTAssertTrue(waitUntil { body.promptPanelText == "abc3" }, "↩ の後に入力欄へ打てない")
    }

    // AC-20
    // AC-21
    @MainActor
    func testAC20_tabSwitchesSideAndEscapeClosesPanel() throws {
        let app = try launchApp(history: ["old"])
        _ = openPanel(in: app)
        let body = textView(in: app)

        pressCommand("b", in: app)
        XCTAssertTrue(element(in: app, identifier: "sidebar.tab.history").waitForExistence(timeout: timeout))
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(row(in: app, containing: "old").waitForExistence(timeout: timeout), "Tab で履歴の側に替わらない")

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { body.promptPanelText == "old" }, "↓ で履歴が本文に出ない")
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertEqual(body.promptPanelText, "old", "← で本文が変わった")

        app.typeKey(.tab, modifierFlags: .shift)
        XCTAssertTrue(row(in: app, containing: "old").waitForNonExistence(timeout: timeout), "⇧Tab で下書きの側に戻らない")
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(row(in: app, containing: "old").waitForExistence(timeout: timeout), "Tab で履歴の側に戻らない")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(body.waitForNonExistence(timeout: timeout), "一覧で esc を押してもパネルが閉じない")
    }

    // AC-23
    @MainActor
    func testAC23_reopenedPanelFocusesBody() throws {
        let app = try launchApp()
        _ = openPanel(in: app)

        pressCommand("b", in: app)
        XCTAssertTrue(element(in: app, identifier: "sidebar.tab.drafts").waitForExistence(timeout: timeout))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(textView(in: app).waitForNonExistence(timeout: timeout), "一覧で esc を押してもパネルが閉じない")

        openPanelFromMenu(in: app)
        let body = textView(in: app)
        XCTAssertTrue(body.waitForExistence(timeout: timeout))
        app.typeText("q")
        XCTAssertTrue(waitUntil { body.promptPanelText == "q" }, "開き直した後に入力欄へ打てない")
    }

    // AC-24
    @MainActor
    func testAC24_clickingRowShowsItAndKeepsFocusInList() throws {
        let app = try launchApp(history: ["one", "two"])
        _ = openPanel(in: app)
        let body = textView(in: app)

        openSidebar(in: app)
        element(in: app, identifier: "sidebar.tab.history").click()
        let first = row(in: app, containing: "one")
        XCTAssertTrue(first.waitForExistence(timeout: timeout), "履歴の行が出ない")
        first.click()
        XCTAssertTrue(waitUntil { body.promptPanelText == "one" }, "行のクリックで本文に出ない")

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { body.promptPanelText == "two" }, "クリックの後に ↓ で次の行が出ない")
    }
}
