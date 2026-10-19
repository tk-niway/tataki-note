import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct ImmediateSwitchTests {
    @MainActor
    private final class Fixture {
        let directory: URL
        let defaultsName: String
        let library: DraftLibrary
        let controller: PanelController

        init() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let defaultsName = UUID().uuidString
            let defaults = try #require(InMemoryDefaults(suiteName: defaultsName))
            let settings = AppSettings(store: SettingsStore(defaults: defaults))
            let library = DraftLibrary(store: DraftLibraryStore(directory: directory))
            let probe = FocusedElementProbeStub()
            self.directory = directory
            self.defaultsName = defaultsName
            self.library = library
            self.controller = PanelController(
                settings: settings,
                targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
                inserter: InserterStub(result: .inserted),
                permission: PermissionStub(isTrusted: true),
                fieldProbe: probe,
                library: library,
                beep: {},
                makeTargetMonitor: InsertionTargetMonitor.testFactory(
                    probe: probe,
                    ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
                )
            )
            controller.model.present(target: nil)
        }

        var model: PanelModel { controller.model }
        var session: DraftSession { controller.session }

        func cleanup() {
            controller.close()
            try? FileManager.default.removeItem(at: directory)
            InMemoryDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        }
    }

    private static func commandKey(_ characters: String, keyCode: UInt16) -> PanelKeyInput {
        PanelKeyInput(keyCode: keyCode, modifiers: [.command], hasMarkedText: false, characters: characters)
    }

    @Test("AC-4: 書きかけがあっても、下書きの行を開くと確認なしですぐ切り替わる")
    func requestDraftSwitchesAtOnce() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let draft = try #require(fixture.library.addDraft(text: "saved"))
        fixture.model.text = "typed"

        fixture.session.request(.draft(draft.id))

        #expect(fixture.model.text == "saved")
        #expect(fixture.session.document == .savedDraft(draft.id))
    }

    @Test("AC-4: 書きかけがあっても、履歴の行を開くと確認なしですぐ切り替わる")
    func requestHistorySwitchesAtOnce() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.library.recordInsertion(text: "old", appName: "Notes", bundleIdentifier: nil)
        let entry = try #require(fixture.library.history.first)
        fixture.model.text = "typed"

        fixture.session.request(.history(entry.id))

        #expect(fixture.model.text == "old")
        #expect(fixture.session.document == .fromHistory(entry.id))
    }

    @Test("AC-4: 書きかけがあっても、⌘N で確認なしにすぐ空の書きかけになり、入力欄へフォーカスを求める")
    func commandNSwitchesAtOnceAndFocusesBody() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.text = "typed"
        let before = fixture.model.focusRequest

        let handled = fixture.controller.handleKey(Self.commandKey("n", keyCode: 45))

        #expect(handled)
        #expect(fixture.model.text.isEmpty)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.model.focusRequest > before)
    }

    @Test("AC-4: 書きかけがあっても、新規作成のアイコンで確認なしにすぐ空の書きかけになり、入力欄へフォーカスを求める")
    func newDraftButtonSwitchesAtOnceAndFocusesBody() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.text = "typed"
        let before = fixture.model.focusRequest

        fixture.controller.newDraftFromButton()

        #expect(fixture.model.text.isEmpty)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.model.focusRequest > before)
    }

    @Test("AC-4: 保存した下書きの表示中の ⌘N も、すぐ空の書きかけになり、入力欄へフォーカスを求める")
    func commandNFromSavedDraftFocusesBody() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let draft = try #require(fixture.library.addDraft(text: "saved"))
        fixture.session.request(.draft(draft.id))
        let before = fixture.model.focusRequest

        #expect(fixture.controller.handleKey(Self.commandKey("n", keyCode: 45)))

        #expect(fixture.model.text.isEmpty)
        #expect(fixture.library.draft(id: draft.id)?.text == "saved")
        #expect(fixture.model.focusRequest > before)
    }
}
