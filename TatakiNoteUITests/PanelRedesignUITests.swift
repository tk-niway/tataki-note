import XCTest

final class PanelRedesignUITests: PanelDraftsUITestCase {

    // AC-19
    @MainActor
    func testAC19_sidebarTabsSwitchTheList() throws {
        let app = try launchApp(history: ["old"])
        _ = openPanel(in: app)
        openSidebar(in: app)

        let draftsTab = element(in: app, identifier: "sidebar.tab.drafts")
        let historyTab = element(in: app, identifier: "sidebar.tab.history")
        XCTAssertTrue(draftsTab.exists)
        XCTAssertTrue(historyTab.exists)
        XCTAssertTrue(element(in: app, identifier: "sidebar.settingsButton").exists)

        historyTab.click()
        XCTAssertTrue(row(in: app, containing: "old").waitForExistence(timeout: timeout), "履歴の行が出ない")

        draftsTab.click()
        XCTAssertTrue(row(in: app, containing: "old").waitForNonExistence(timeout: timeout), "下書きに戻しても履歴の行が残っている")
    }
}
