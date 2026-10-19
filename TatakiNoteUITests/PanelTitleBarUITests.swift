import XCTest

final class PanelTitleBarUITests: PanelDraftsUITestCase {
    // AC-46
    // AC-17
    @MainActor
    func testAC46_AC17_titleBarLayoutSaveNewDraftAndShareIcons() throws {
        let app = try launchApp()
        let panel = openPanel(in: app)
        let body = textView(in: app)

        let closeButton = app.buttons["promptPanel.closeButton"]
        let toggle = app.buttons["promptPanel.sidebarToggle"]
        let newDraft = app.buttons["promptPanel.newDraftButton"]
        let save = app.buttons["promptPanel.saveDraftButton"]
        let share = app.buttons["promptPanel.shareButton"]
        for button in [closeButton, toggle, newDraft, save, share] {
            XCTAssertTrue(button.waitForExistence(timeout: timeout), "タイトルバーのボタンが無い")
        }
        let middle = panel.frame.midX
        XCTAssertLessThan(closeButton.frame.midX, middle, "閉じるボタンが窓の左側にない")
        XCTAssertLessThan(toggle.frame.midX, middle, "開閉ボタンが窓の左側にない")
        XCTAssertGreaterThan(newDraft.frame.midX, middle, "新規作成のアイコンが窓の右側にない")
        XCTAssertGreaterThan(save.frame.midX, middle, "保存のアイコンが窓の右側にない")
        let titleText = panel.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@ OR value == %@", "TatakiNote", "TatakiNote"))
        XCTAssertEqual(titleText.count, 0, "タイトルの文字が出ている")

        share.click()
        let toast = element(in: app, identifier: "promptPanel.saveToast")
        XCTAssertTrue(toast.waitForExistence(timeout: timeout), "空のパネルでシェアのボタンを押してもトーストが出ない")
        XCTAssertEqual(toast.label, "共有する文章がありません")

        app.typeText("abc")
        XCTAssertTrue(waitUntil { save.isEnabled })
        save.click()
        openSidebar(in: app)
        XCTAssertTrue(row(in: app, containing: "abc").waitForExistence(timeout: timeout), "保存のアイコンで行が増えない")

        XCTAssertTrue(waitUntil { newDraft.isEnabled })
        newDraft.click()
        XCTAssertTrue(waitUntil { body.promptPanelText.isEmpty }, "新規作成のアイコンで本文が空にならない")
    }

    // AC-45
    @MainActor
    func testAC45_insertionTargetShowsTipOnHover() throws {
        let app = try launchApp(showsTutorial: true)
        XCTAssertTrue(app.windows["tutorial"].waitForExistence(timeout: timeout), "チュートリアルの窓が開かない")
        let field = element(in: app, identifier: "tutorial.practiceField")
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.click()

        let panel = openPanel(in: app)
        let badge = element(in: app, identifier: "promptPanel.insertionTarget")
        XCTAssertTrue(badge.waitForExistence(timeout: timeout), "挿入先の表示が出ない")
        let save = app.buttons["promptPanel.saveDraftButton"]
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        XCTAssertGreaterThan(badge.frame.midX, panel.frame.midX, "挿入先の表示が窓の右側にない")
        XCTAssertGreaterThanOrEqual(badge.frame.minX, save.frame.maxX - tolerance, "挿入先の表示が保存のアイコンより左にある")
        let tip = element(in: app, identifier: "promptPanel.insertionTargetTip")
        XCTAssertFalse(tip.exists, "マウスを乗せる前にチップが出ている")

        badge.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).hover()
        XCTAssertTrue(tip.waitForExistence(timeout: timeout), "アイコンにマウスを乗せてもチップが出ない")
        let tipText = [tip.label, tip.value as? String ?? ""].joined(separator: " ")
        XCTAssertTrue(tipText.contains("TatakiNote に挿入します"), "チップの文が違う: \(tipText)")

        textView(in: app).hover()
        XCTAssertTrue(tip.waitForNonExistence(timeout: timeout), "マウスを外してもチップが消えない")
    }
}
