import AppKit
import XCTest

final class PromptPanelLineEditingUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    private let settingsSuiteName = "TatakiNoteUITests.\(UUID().uuidString)"

    private var clipboardBackup: ClipboardBackup?

    override func setUpWithError() throws {
        continueAfterFailure = false
        clipboardBackup = ClipboardBackup.capture(from: .general)
    }

    override func tearDownWithError() throws {
        clipboardBackup?.restore(to: .general)
        UserDefaults(suiteName: settingsSuiteName)?.removePersistentDomain(forName: settingsSuiteName)
    }

    @MainActor
    func testAC1_AC4_AC14_AC15_moveAndDuplicate() throws {
        let app = makeApp()
        app.launch()
        let textView = openPanel(in: app)
        XCTAssertEqual(textView.promptPanelText, "")

        typeLines(["one", "two", "three"], in: app)
        XCTAssertEqual(textView.value as? String, "one\ntwo\nthree")

        // AC-1
        app.typeKey(.upArrow, modifierFlags: [.option])
        XCTAssertEqual(textView.value as? String, "one\nthree\ntwo")
        app.typeText("X")
        XCTAssertEqual(textView.value as? String, "one\nthreeX\ntwo")

        // AC-4
        app.typeKey(.downArrow, modifierFlags: [.option, .shift])
        XCTAssertEqual(textView.value as? String, "one\nthreeX\nthreeX\ntwo")

        // AC-14
        app.typeKey("z", modifierFlags: [.command])
        XCTAssertEqual(textView.value as? String, "one\nthreeX\ntwo")
        app.typeKey("z", modifierFlags: [.command])
        XCTAssertEqual(textView.value as? String, "one\nthree\ntwo")
        app.typeKey("z", modifierFlags: [.command])
        XCTAssertEqual(textView.value as? String, "one\ntwo\nthree")

        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(textView.value as? String, "one\nthree\ntwo")

        // AC-15
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(textView.waitForNonExistence(timeout: timeout))
        openPanelFromMenu(in: app)
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        XCTAssertEqual(textView.value as? String, "one\nthree\ntwo")
    }

    @MainActor
    func testAC5_AC6_AC7_AC8_AC9_lineClipboard() throws {
        let app = makeApp()
        app.launch()
        let textView = openPanel(in: app)

        typeLines(["alpha", "beta", "gamma"], in: app)
        XCTAssertEqual(textView.value as? String, "alpha\nbeta\ngamma")
        // AC-16
        app.typeKey(.upArrow, modifierFlags: [])

        // AC-5
        app.typeKey("c", modifierFlags: [.command])
        assertClipboardString("beta\n")
        XCTAssertEqual(textView.value as? String, "alpha\nbeta\ngamma")

        // AC-6
        app.typeKey("x", modifierFlags: [.command])
        XCTAssertEqual(textView.value as? String, "alpha\ngamma")
        assertClipboardString("beta\n")

        // AC-7
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey("v", modifierFlags: [.command])
        XCTAssertEqual(textView.value as? String, "alpha\nbeta\ngamma")

        // AC-9
        app.typeKey(.leftArrow, modifierFlags: [.shift])
        app.typeKey(.leftArrow, modifierFlags: [.shift])
        app.typeKey("c", modifierFlags: [.command])
        assertClipboardString("ga")

        // AC-8
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey("v", modifierFlags: [.command])
        XCTAssertEqual(textView.value as? String, "alpha\nbeta\ngagamma")

        // AC-9
        app.typeKey(.leftArrow, modifierFlags: [.shift])
        app.typeKey(.leftArrow, modifierFlags: [.shift])
        app.typeKey("x", modifierFlags: [.command])
        XCTAssertEqual(textView.value as? String, "alpha\nbeta\ngamma")
        assertClipboardString("ga")

        // AC-8
        app.typeKey("c", modifierFlags: [.command])
        assertClipboardString("gamma\n")
        app.typeKey(.leftArrow, modifierFlags: [.shift])
        app.typeKey(.leftArrow, modifierFlags: [.shift])
        app.typeKey("v", modifierFlags: [.command])
        XCTAssertEqual(textView.value as? String, "alpha\nbeta\ngamma\nmma")
    }

    // MARK: - 補助

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TATAKINOTE_SETTINGS_SUITE"] = settingsSuiteName
        app.launchEnvironment[AccessibilityOverride.key] = AccessibilityOverride.trusted
        return app
    }

    @MainActor
    private func openPanel(in app: XCUIApplication) -> XCUIElement {
        openPanelFromMenu(in: app)
        let textView = app.textViews["promptPanel.textView"]
        XCTAssertTrue(textView.waitForExistence(timeout: timeout))
        return textView
    }

    @MainActor
    private func typeLines(_ lines: [String], in app: XCUIApplication) {
        for (index, line) in lines.enumerated() {
            if index > 0 {
                app.typeKey(.return, modifierFlags: [])
            }
            app.typeText(line)
        }
    }

    @MainActor
    private func assertClipboardString(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while NSPasteboard.general.string(forType: .string) != expected && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), expected, file: file, line: line)
    }

    // MARK: - 要素の探し方(PromptPanelUITests と同じ方法)

    @MainActor
    private func openMenu(in app: XCUIApplication) {
        var statusItem = app.statusItems.firstMatch
        if !statusItem.waitForExistence(timeout: timeout) {
            statusItem = app.menuBars.statusItems.firstMatch
        }
        XCTAssertTrue(statusItem.waitForExistence(timeout: timeout))
        statusItem.click()
    }

    @MainActor
    private func openPanelFromMenu(in app: XCUIApplication) {
        openMenu(in: app)
        let item = openPanelMenuItem(in: app)
        XCTAssertTrue(item.waitForExistence(timeout: timeout))
        clickShownMenuItem(item)
    }

    @MainActor
    private func clickShownMenuItem(_ item: XCUIElement) {
        let deadline = Date().addingTimeInterval(timeout)
        while item.frame.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(item.frame.isEmpty, "メニューが表示されていない(項目の枠が空)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    @MainActor
    private func openPanelMenuItem(in app: XCUIApplication) -> XCUIElement {
        menuItem(in: app, identifier: "menu.openPanel", title: "パネルを開く")
    }

    @MainActor
    private func menuItem(in app: XCUIApplication, identifier: String, title: String) -> XCUIElement {
        let byIdentifier = app.menuItems[identifier]
        if byIdentifier.exists {
            return byIdentifier
        }
        return app.menuItems[title]
    }
}

private struct ClipboardBackup {
    var items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    static func capture(from pasteboard: NSPasteboard) -> ClipboardBackup {
        let items = (pasteboard.pasteboardItems ?? []).compactMap { item -> [(type: NSPasteboard.PasteboardType, data: Data)]? in
            let entries = item.types.compactMap { type in
                item.data(forType: type).map { (type: type, data: $0) }
            }
            return entries.isEmpty ? nil : entries
        }
        return ClipboardBackup(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let pasteboardItems = items.map { entries in
            let item = NSPasteboardItem()
            for entry in entries {
                item.setData(entry.data, forType: entry.type)
            }
            return item
        }
        pasteboard.writeObjects(pasteboardItems)
    }
}
