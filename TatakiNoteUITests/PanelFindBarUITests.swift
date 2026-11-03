import XCTest

final class PanelFindBarUITests: PanelDraftsUITestCase {
    // AC-37
    // AC-38
    // AC-44
    @MainActor
    func testAC37_AC38_AC44_findButtonCountReplaceAllAndClose() throws {
        let app = try launchApp()
        let panel = openPanel(in: app)
        let body = textView(in: app)
        app.typeText("abc abc")
        XCTAssertTrue(waitUntil { body.promptPanelText == "abc abc" }, "打った文字が入力欄に入らない")

        // AC-37
        let findButton = app.buttons["promptPanel.findButton"]
        let newDraft = app.buttons["promptPanel.newDraftButton"]
        XCTAssertTrue(findButton.waitForExistence(timeout: timeout), "虫眼鏡のボタンが無い")
        XCTAssertTrue(newDraft.waitForExistence(timeout: timeout))
        XCTAssertLessThan(findButton.frame.midX, newDraft.frame.midX, "虫眼鏡が新規より左にない")
        XCTAssertGreaterThan(findButton.frame.midX, panel.frame.midX, "虫眼鏡が窓の右半分にない")
        XCTAssertFalse(element(in: app, identifier: "findBar").exists, "検索バーが最初から出ている")

        findButton.click()
        let findBar = element(in: app, identifier: "findBar")
        XCTAssertTrue(findBar.waitForExistence(timeout: timeout), "虫眼鏡を押しても検索バーが出ない")
        let findField = element(in: app, identifier: "findBar.findField")
        XCTAssertTrue(findField.waitForExistence(timeout: timeout), "検索欄が出ない")

        // AC-38
        findField.click()
        app.typeText("abc")
        let count = element(in: app, identifier: "findBar.matchCount")
        XCTAssertTrue(count.waitForExistence(timeout: timeout), "件数が出ない")
        XCTAssertTrue(waitUntil { count.label.hasSuffix("/2") }, "検索語を打っても件数が「/2」にならない: \(count.label)")

        let toggleReplace = app.buttons["findBar.toggleReplace"]
        XCTAssertTrue(toggleReplace.waitForExistence(timeout: timeout))
        toggleReplace.click()
        let replaceField = element(in: app, identifier: "findBar.replaceField")
        XCTAssertTrue(replaceField.waitForExistence(timeout: timeout), "置換の欄が開かない")
        replaceField.click()
        app.typeText("x")

        let replaceAll = app.buttons["findBar.replaceAll"]
        XCTAssertTrue(replaceAll.waitForExistence(timeout: timeout))
        replaceAll.click()
        XCTAssertTrue(waitUntil { body.promptPanelText == "x x" }, "すべて置換で本文が置き換わらない: \(body.promptPanelText)")

        let close = app.buttons["findBar.close"]
        XCTAssertTrue(close.waitForExistence(timeout: timeout))
        close.click()
        XCTAssertTrue(waitUntil { !findBar.exists }, "閉じるボタンで検索バーが消えない")
        XCTAssertTrue(app.dialogs["promptPanel"].exists, "検索バーを閉じたらパネルまで閉じた")

        // AC-44
        findButton.click()
        XCTAssertTrue(waitUntil { element(in: app, identifier: "findBar").exists }, "虫眼鏡を押しても検索バーが出ない")
        findButton.click()
        XCTAssertTrue(waitUntil { !element(in: app, identifier: "findBar").exists }, "検索バーが出ているときに虫眼鏡を押しても閉じない")
        XCTAssertTrue(app.dialogs["promptPanel"].exists, "虫眼鏡で検索バーを閉じたらパネルまで閉じた")
    }
}
