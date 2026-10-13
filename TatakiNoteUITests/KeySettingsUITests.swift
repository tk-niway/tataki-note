import XCTest

final class KeySettingsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    private let groupIdentifiers = [
        "settings.group.hotkey",
        "settings.group.autoShow",
        "settings.group.insertAndSend",
        "settings.group.shortcuts",
    ]
    private let groupTitles = ["ホットキーで開く", "自動で開く", "挿入と送信", "パネルの中で使えるキー"]
    private let shortcutGroupTitles = [
        "line": "行の操作",
        "clipboard": "コピーと貼り付け",
        "drafts": "下書き",
        "view": "表示",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-19
    // AC-29
    @MainActor
    func testAC19_AC29_groupsRecordersAndInsertOnlyBadges() throws {
        let app = try launchApp(seed: nil)
        openKeySettings(in: app)

        // AC-19
        for identifier in groupIdentifiers {
            XCTAssertTrue(element(in: app, identifier: identifier).waitForExistence(timeout: timeout), identifier)
        }
        let ys = groupIdentifiers.map { element(in: app, identifier: $0).frame.minY }
        XCTAssertEqual(ys, ys.sorted(), "「開き方とキー」のまとまりが上から \(groupTitles) の順に並んでいない")
        XCTAssertEqual(Set(ys).count, ys.count)
        for (identifier, title) in zip(groupIdentifiers, groupTitles) {
            XCTAssertEqual(text(of: element(in: app, identifier: "\(identifier).title")), title, identifier)
        }
        for identifier in ["settings.hotkeyRecorder", "settings.commitKeyRecorder", "settings.commitAndSendKeyRecorder"] {
            XCTAssertTrue(element(in: app, identifier: identifier).exists, identifier)
        }

        // AC-29
        for identifier in ["settings.group.autoShow", "settings.group.insertAndSend"] {
            let badge = element(in: app, identifier: "\(identifier).badge")
            XCTAssertTrue(badge.exists, identifier)
            XCTAssertEqual(text(of: badge), "インサートのみ", identifier)
        }
        for identifier in ["settings.group.hotkey", "settings.group.shortcuts"] {
            XCTAssertFalse(element(in: app, identifier: "\(identifier).badge").exists, identifier)
        }

        closeSettings(in: app)
    }

    // AC-30
    @MainActor
    func testAC30_shortcutGroupsAndRows() throws {
        let app = try launchApp(seed: nil)
        openKeySettings(in: app)

        let list = element(in: app, identifier: "settings.shortcutList")
        app.revealInSettings(list)
        for (id, title) in shortcutGroupTitles {
            XCTAssertTrue(element(in: app, identifier: "settings.shortcutGroup.\(id)").exists, id)
            XCTAssertEqual(text(of: element(in: app, identifier: "settings.shortcutGroup.\(id).title")), title, id)
        }
        XCTAssertEqual(rowCount(prefix: "settings.shortcut.", in: list), 7)
        XCTAssertEqual(rowCount(prefix: "settings.panelCommand.", in: list), 5)

        for keys in ["⌥↑", "⌘L", "⌘D", "⌘K", "⌘,"] {
            let row = list.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", keys)).firstMatch
            XCTAssertTrue(row.exists, "\(keys) の行が無い")
        }
        let wordRow = list.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "⌘D", "単語"))
            .firstMatch
        XCTAssertTrue(wordRow.exists)

        closeSettings(in: app)
    }

    // AC-28
    @MainActor
    func testAC28_switchToInsertFromBannerEnablesRecorders() throws {
        let app = try launchApp(seed: ["appMode": "note"])
        openKeySettings(in: app)

        let commitRecorder = element(in: app, identifier: "settings.commitKeyRecorder")
        let commitAndSendRecorder = element(in: app, identifier: "settings.commitAndSendKeyRecorder")
        let banner = element(in: app, identifier: "settings.noteModeBanner.insertAndSend")
        let switchToInsert = element(in: app, identifier: "settings.noteModeBanner.insertAndSend.switchToInsert")
        app.revealInSettings(commitRecorder)
        XCTAssertTrue(banner.exists)
        XCTAssertFalse(commitRecorder.isEnabled)
        XCTAssertFalse(commitAndSendRecorder.isEnabled)
        XCTAssertTrue(element(in: app, identifier: "settings.appMode.note").isSelected)

        switchToInsert.click()
        XCTAssertTrue(banner.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(waitUntil { commitRecorder.isEnabled && commitAndSendRecorder.isEnabled })
        XCTAssertTrue(waitUntil { self.element(in: app, identifier: "settings.appMode.insert").isSelected })

        closeSettings(in: app)
    }

    // MARK: - 起動と要素の探し方

    @MainActor
    private func launchApp(seed: [String: Any]?) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        if let seed {
            let data = try JSONSerialization.data(withJSONObject: seed, options: [.sortedKeys])
            app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = String(decoding: data, as: UTF8.self)
        }
        app.launch()
        app.dismissPermissionGuideIfPresent(timeout: 0.5)
        return app
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func text(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    @MainActor
    private func rowCount(prefix: String, in list: XCUIElement) -> Int {
        list.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).count
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
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
