import XCTest

final class NoteModeTutorialUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    // AC-28
    @MainActor
    func testAC28_noteModeTutorialShowsOpenAndSaveSteps() throws {
        let app = try launchApp(seed: ["appMode": "note"])

        XCTAssertTrue(app.windows["tutorial"].waitForExistence(timeout: timeout), "チュートリアルの窓が開かない")
        XCTAssertTrue(element(in: app, identifier: "tutorial.step.openPanel").waitForExistence(timeout: timeout), "「パネルを開く」の行が無い")
        XCTAssertTrue(element(in: app, identifier: "tutorial.step.saveDraft").exists, "「書いて保存する」の行が無い")
        XCTAssertTrue(element(in: app, identifier: "tutorial.step.nextSteps").exists, "「次の一歩」の行が無い")
        XCTAssertFalse(element(in: app, identifier: "tutorial.step.writeWithNewline").exists, "「Enter で改行しながら書く」の行が出ている")
        XCTAssertFalse(element(in: app, identifier: "tutorial.step.send").exists, "「送る」の行が出ている")
        XCTAssertFalse(element(in: app, identifier: "tutorial.practiceField").exists, "練習用のチャットの入力欄が出ている")
        XCTAssertTrue(app.buttons["tutorial.skip"].exists)
    }

    // MARK: - 起動と要素の探し方

    @MainActor
    private func launchApp(seed: [String: Any]) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        app.launchEnvironment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] = "memory"
        app.launchEnvironment["TATAKINOTE_FIRST_LAUNCH_TUTORIAL"] = "enabled"
        app.launchEnvironment["TATAKINOTE_SETTINGS_SEED"] = try settingsSeedJSON(seed)
        app.launch()
        return app
    }

    private func settingsSeedJSON(_ values: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
