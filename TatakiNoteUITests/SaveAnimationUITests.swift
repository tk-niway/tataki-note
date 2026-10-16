import XCTest

final class SaveAnimationUITests: PanelDraftsUITestCase {
    // AC-15
    @MainActor
    func testAC15_saveButtonShowsToast() throws {
        let app = try launchApp()
        _ = openPanel(in: app)

        app.typeText("abc")
        let saveButton = app.buttons["promptPanel.saveDraftButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { saveButton.isEnabled })
        saveButton.click()

        let toast = element(in: app, identifier: "promptPanel.saveToast")
        XCTAssertTrue(toast.waitForExistence(timeout: 2), "保存のトーストが出ない")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 5), "保存のトーストが消えない")
    }

    // AC-14
    @MainActor
    func testAC14_saveFromHistoryTabSwitchesToDrafts() throws {
        let app = try launchApp(history: ["old"])
        _ = openPanel(in: app)
        openSidebar(in: app)

        element(in: app, identifier: "sidebar.tab.history").click()
        XCTAssertTrue(row(in: app, containing: "old").waitForExistence(timeout: timeout), "履歴の行が出ない")

        textView(in: app).click()
        app.typeText("abc")
        pressCommand("s", in: app)

        XCTAssertTrue(row(in: app, containing: "old").waitForNonExistence(timeout: timeout), "下書きに切り替わらない")
        XCTAssertTrue(row(in: app, containing: "abc").waitForExistence(timeout: timeout), "保存した下書きの行が出ない")
    }
}
