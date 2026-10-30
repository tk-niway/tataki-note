import XCTest

final class DraftModePanelUITests: PanelDraftsUITestCase {
    private let noteButtonID = "promptPanel.noteModeButton"
    private let targetIDs = ["promptPanel.insertionTarget", "promptPanel.noInsertionTarget"]

    // AC-17
    // AC-12
    @MainActor
    func testAC17_AC12_titleBarFollowsDraftMode() throws {
        let app = try launchApp()
        let panel = openPanel(in: app)
        let save = app.buttons["promptPanel.saveDraftButton"]
        XCTAssertTrue(save.waitForExistence(timeout: timeout))

        XCTAssertTrue(waitUntil { self.hasInsertionTarget(in: app) }, "挿入先の表示が出ない")
        XCTAssertFalse(element(in: app, identifier: noteButtonID).exists, "インサートで「ノート」が出ている")
        let modeText = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "インサート", "インサート")
        XCTAssertEqual(panel.descendants(matching: .any).matching(modeText).count, 0, "「インサート」の文字が出ている")
        XCTAssertTrue(element(in: app, identifier: "promptPanel.status.commit").waitForExistence(timeout: timeout))

        pressCommand("e", in: app)
        let noteButton = element(in: app, identifier: noteButtonID)
        XCTAssertTrue(noteButton.waitForExistence(timeout: timeout), "⌘E でノートにならない")
        XCTAssertTrue(waitUntil { !self.hasInsertionTarget(in: app) }, "ノートで挿入先の表示が残っている")
        XCTAssertGreaterThanOrEqual(noteButton.frame.minX, save.frame.maxX - tolerance, "「ノート」が保存のアイコンより左にある")
        XCTAssertTrue(element(in: app, identifier: "promptPanel.status.commit").waitForNonExistence(timeout: timeout))
        XCTAssertFalse(element(in: app, identifier: "promptPanel.status.commitAndSend").exists)
        XCTAssertTrue(element(in: app, identifier: "promptPanel.status.lineBreak").exists, "ノートで「改行」が出ない")

        noteButton.click()
        XCTAssertTrue(noteButton.waitForNonExistence(timeout: timeout), "「ノート」のクリックでインサートに戻らない")
        XCTAssertTrue(waitUntil { self.hasInsertionTarget(in: app) }, "インサートに戻っても挿入先の表示が出ない")
        XCTAssertTrue(element(in: app, identifier: "promptPanel.status.commit").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(in: app, identifier: "promptPanel.status.commitAndSend").exists)

        pressCommand("e", in: app)
        XCTAssertTrue(noteButton.waitForExistence(timeout: timeout))
        pressCommand("e", in: app)
        XCTAssertTrue(noteButton.waitForNonExistence(timeout: timeout), "⌘E でインサートに戻らない")
        XCTAssertTrue(waitUntil { self.hasInsertionTarget(in: app) })

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(textView(in: app).waitForNonExistence(timeout: timeout))
    }

    // AC-4
    // AC-12
    @MainActor
    func testAC4_AC12_newDraftButtonWorksOnEmptyBodyAndLeavesNote() throws {
        let app = try launchApp()
        _ = openPanel(in: app)
        let newDraft = app.buttons["promptPanel.newDraftButton"]
        XCTAssertTrue(newDraft.waitForExistence(timeout: timeout))
        XCTAssertTrue(textView(in: app).promptPanelText.isEmpty)
        XCTAssertTrue(newDraft.isEnabled, "本文が空だと新規作成のアイコンが押せない")

        pressCommand("e", in: app)
        let noteButton = element(in: app, identifier: noteButtonID)
        XCTAssertTrue(noteButton.waitForExistence(timeout: timeout), "⌘E でノートにならない")

        newDraft.click()
        XCTAssertTrue(noteButton.waitForNonExistence(timeout: timeout), "新規作成のアイコンでインサートに戻らない")
        XCTAssertTrue(waitUntil { self.hasInsertionTarget(in: app) }, "挿入先の表示が戻らない")
    }

    // MARK: - 要素の探し方

    @MainActor
    private func hasInsertionTarget(in app: XCUIApplication) -> Bool {
        targetIDs.contains { element(in: app, identifier: $0).exists }
    }
}
