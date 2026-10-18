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
}
