import XCTest

final class DraftModeSettingsUITests: PanelDraftsUITestCase {
    private let noteButtonID = "promptPanel.noteModeButton"

    // AC-24
    @MainActor
    func testAC24_modeRowSelectsNoteForNewDrafts() throws {
        let app = try launchApp()
        openKeySettings(in: app)

        let row = element(in: app, identifier: "settings.row.newDraftMode")
        app.revealInSettings(row)
        let title = row.staticTexts
            .matching(NSPredicate(format: "label == %@ OR value == %@", "モード", "モード"))
            .firstMatch
        XCTAssertTrue(title.exists, "行の名前が「モード」ではない")

        let picker = row.descendants(matching: .any)["settings.newDraftModePicker"].firstMatch
        XCTAssertTrue(picker.exists, "「モード」の行に選択肢が無い")
        XCTAssertTrue(segment("インサート", in: picker).exists)
        let note = segment("ノート", in: picker)
        XCTAssertTrue(note.exists)
        note.click()

        closeSettings(in: app)

        _ = openPanel(in: app)
        XCTAssertFalse(element(in: app, identifier: noteButtonID).exists, "設定を変えただけで今の書きかけがノートになった")
        pressCommand("n", in: app)
        XCTAssertTrue(
            element(in: app, identifier: noteButtonID).waitForExistence(timeout: timeout),
            "⌘N の後の書きかけがノートで始まらない"
        )
    }

    // AC-27
    @MainActor
    func testAC27_settingsHaveNoModeSwitchOrRestrictions() throws {
        for seed: [String: Any] in [[:], ["newDraftMode": "note"]] {
            let app = try launchApp(seed: seed)
            openSettingsFromMenu(in: app)
            XCTAssertTrue(element(in: app, identifier: "settings.sidebar.keys").waitForExistence(timeout: timeout))
            XCTAssertFalse(element(in: app, identifier: "settings.appModeToggle").exists, "サイドバーにモードの切り替えが残っている")

            element(in: app, identifier: "settings.sidebar.keys").click()
            XCTAssertTrue(element(in: app, identifier: "settings.hotkeyRecorder").waitForExistence(timeout: timeout))
            for identifier in [
                "settings.group.autoShow.badge",
                "settings.group.insertAndSend.badge",
                "settings.noteModeBanner.autoShow",
                "settings.noteModeBanner.insertAndSend",
            ] {
                XCTAssertFalse(element(in: app, identifier: identifier).exists, identifier)
            }
            for identifier in [
                "settings.autoShowModePicker",
                "settings.commitKeyRecorder",
                "settings.commitAndSendKeyRecorder",
            ] {
                let target = element(in: app, identifier: identifier)
                app.revealInSettings(target)
                XCTAssertTrue(target.isEnabled, "\(identifier) が押せない")
            }

            element(in: app, identifier: "settings.sidebar.panel").click()
            let tile = element(in: app, identifier: "settings.panelScreen.nearFocusedField")
            app.revealInSettings(tile)
            XCTAssertTrue(tile.isEnabled, "「入力欄の近く」のタイルが押せない")
            XCTAssertFalse(element(in: app, identifier: "settings.noteModeReason.nearFocusedField").exists)

            let outline = element(in: app, identifier: "settings.insertionTargetOutlineToggle")
            app.revealInSettings(outline)
            XCTAssertTrue(outline.isEnabled, "「挿入先の枠線」のスイッチが押せない")
            XCTAssertFalse(element(in: app, identifier: "settings.noteModeReason.insertionTargetOutline").exists)

            closeSettings(in: app)
            app.terminate()
        }
    }

    // MARK: - 設定画面

    @MainActor
    private func segment(_ name: String, in picker: XCUIElement) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ OR title == %@", name, name)
        return picker.descendants(matching: .any).matching(predicate).firstMatch
    }

    @MainActor
    private func openKeySettings(in app: XCUIApplication) {
        openSettingsFromMenu(in: app)
        let keys = element(in: app, identifier: "settings.sidebar.keys")
        XCTAssertTrue(keys.waitForExistence(timeout: timeout))
        keys.click()
        XCTAssertTrue(element(in: app, identifier: "settings.hotkeyRecorder").waitForExistence(timeout: timeout))
    }

    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        let window = app.windows.containing(.any, identifier: "settings.sidebar.general").firstMatch
        XCTAssertTrue(window.exists)
        let closeButton = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()
        XCTAssertTrue(element(in: app, identifier: "settings.sidebar.general").waitForNonExistence(timeout: timeout))
    }

    @MainActor
    private func openSettingsFromMenu(in app: XCUIApplication) {
        var statusItem = app.statusItems.firstMatch
        if !statusItem.waitForExistence(timeout: timeout) {
            statusItem = app.menuBars.statusItems.firstMatch
        }
        XCTAssertTrue(statusItem.waitForExistence(timeout: timeout))
        statusItem.click()

        let byIdentifier = app.menuItems["menu.settings"]
        let item = byIdentifier.exists ? byIdentifier : app.menuItems["設定"]
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        let deadline = Date().addingTimeInterval(timeout)
        while item.frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(item.frame.isEmpty, "メニューが表示されていない(項目の枠が空)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(element(in: app, identifier: "settings.sidebar.general").waitForExistence(timeout: timeout))
    }
}
