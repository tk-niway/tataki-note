import XCTest

final class PanelRedesignUITests: PanelDraftsUITestCase {
    private let titleBarHeight: CGFloat = 38

    // AC-19
    @MainActor
    func testAC19_titleBarButtonsAreLaidOutLeftAndRight() throws {
        let app = try launchApp()
        let panel = openPanel(in: app)

        let closeButton = app.buttons["promptPanel.closeButton"]
        let sidebarToggle = app.buttons["promptPanel.sidebarToggle"]
        let newDraftButton = app.buttons["promptPanel.newDraftButton"]
        let saveDraftButton = app.buttons["promptPanel.saveDraftButton"]
        for button in [closeButton, sidebarToggle, newDraftButton, saveDraftButton] {
            XCTAssertTrue(button.waitForExistence(timeout: timeout), "\(button.identifier) が無い")
        }

        let panelFrame = panel.frame
        XCTAssertLessThan(closeButton.frame.midX, panelFrame.midX)
        XCTAssertLessThan(sidebarToggle.frame.midX, panelFrame.midX)
        XCTAssertGreaterThan(newDraftButton.frame.midX, panelFrame.midX)
        XCTAssertGreaterThan(saveDraftButton.frame.midX, panelFrame.midX)
        XCTAssertLessThan(closeButton.frame.midX, sidebarToggle.frame.midX)

        for button in [closeButton, sidebarToggle, newDraftButton, saveDraftButton] {
            XCTAssertLessThanOrEqual(
                button.frame.midY - panelFrame.minY,
                titleBarHeight,
                "\(button.identifier) が上の帯の外にある"
            )
        }
    }

    // AC-19
    @MainActor
    func testAC19_statusBarCommitButtonsAreHittable() throws {
        let app = try launchApp()
        _ = openPanel(in: app)

        let commitButton = element(in: app, identifier: "promptPanel.status.commit")
        let commitAndSendButton = element(in: app, identifier: "promptPanel.status.commitAndSend")
        XCTAssertTrue(commitButton.waitForExistence(timeout: timeout))
        XCTAssertTrue(commitAndSendButton.waitForExistence(timeout: timeout))
        XCTAssertTrue(commitButton.isHittable)
        XCTAssertTrue(commitAndSendButton.isHittable)
    }

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
