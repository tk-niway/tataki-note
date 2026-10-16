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
}
