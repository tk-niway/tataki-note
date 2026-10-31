import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
private final class CallCounter {
    var count = 0
}

@MainActor
struct PanelControllerCommandTests {
    private struct Fixture {
        let controller: PanelController
        let settings: AppSettings
        let beeps: CallCounter
        let guideOpens: CallCounter
        let settingsOpens: CallCounter
        let chooser: ExportChooserSpy

        var model: PanelModel { controller.model }
        var session: DraftSession { controller.session }
    }

    private func withFixture(isTrusted: Bool = true, _ body: (Fixture) async throws -> Void) async throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.animationMode = .off
        let probe = FocusedElementProbeStub()
        let beeps = CallCounter()
        let chooser = ExportChooserSpy()
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: InserterStub(result: .inserted),
            permission: PermissionStub(isTrusted: isTrusted),
            fieldProbe: probe,
            exposeWebContent: { _ in },
            beep: { beeps.count += 1 },
            makeTargetMonitor: InsertionTargetMonitor.testFactory(
                probe: probe,
                ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
            ),
            exportChooser: chooser
        )
        controller.isTargetLookupDisabled = true
        let guideOpens = CallCounter()
        controller.onPermissionDenied = { guideOpens.count += 1 }
        let settingsOpens = CallCounter()
        controller.onOpenSettings = { settingsOpens.count += 1 }
        defer { controller.close() }
        try await body(
            Fixture(
                controller: controller,
                settings: settings,
                beeps: beeps,
                guideOpens: guideOpens,
                settingsOpens: settingsOpens,
                chooser: chooser
            )
        )
    }

    private func waitFor(_ condition: () -> Bool) async {
        _ = try? await waitUntil(attempts: 300, interval: .milliseconds(10), condition)
    }

    private func pressKey(_ action: PanelKeyAction, on controller: PanelController) -> Bool {
        guard let row = PanelCommandKeys.all.first(where: { $0.action == action }) else { return false }
        let input = PanelKeyInput(keyCode: 0, modifiers: row.key.modifiers, hasMarkedText: false, characters: row.key.character)
        return controller.handleKey(input)
    }

    private func composingEditor(in controller: PanelController, base: String) -> (PromptTextView, PromptTextEditor.Coordinator) {
        let model = controller.model
        let textView = PromptTextView()
        textView.isRichText = false
        let coordinator = PromptTextEditor.Coordinator(text: Binding(get: { model.text }, set: { model.text = $0 }))
        textView.delegate = coordinator
        textView.string = base
        controller.panel.contentView = textView
        controller.panel.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (base as NSString).length, length: 0))
        textView.setMarkedText(
            "にほんご",
            selectedRange: NSRange(location: 4, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        return (textView, coordinator)
    }

    // MARK: - AC-9

    @Test("AC-9: タイトルバーの保存のボタンは、変換中の文字を確定して保存し、入力欄へフォーカスを戻すよう頼む")
    func saveButtonCommitsMarkedTextAndRequestsFocus() async throws {
        try await withFixture { fixture in
            fixture.model.text = "abc"
            let (textView, coordinator) = composingEditor(in: fixture.controller, base: "abc")
            #expect(textView.hasMarkedText())
            let focusBefore = fixture.model.focusRequest

            let didPerform = fixture.controller.perform(.saveDraft, from: .button)

            #expect(didPerform)
            #expect(!textView.hasMarkedText())
            #expect(fixture.model.text == "abcにほんご")
            #expect(fixture.session.lastSaveEvent != nil)
            #expect(fixture.model.focusRequest == focusBefore + 1)
            withExtendedLifetime(coordinator) {}
        }
    }

    @Test("AC-9: ⌘S は保存するが、変換中の文字を確定せず、フォーカスを戻すよう頼まない")
    func saveKeyDoesNotRequestFocus() async throws {
        try await withFixture { fixture in
            fixture.model.text = "abc"
            let (textView, coordinator) = composingEditor(in: fixture.controller, base: "abc")
            let focusBefore = fixture.model.focusRequest

            let handled = pressKey(.saveDraft, on: fixture.controller)

            #expect(handled)
            #expect(textView.hasMarkedText())
            #expect(fixture.session.lastSaveEvent != nil)
            #expect(fixture.model.focusRequest == focusBefore)
            withExtendedLifetime(coordinator) {}
        }
    }

    @Test("AC-9: 本文が空なら、保存のボタンも ⌘S も保存せず揺れ(合図)を出す。ボタンだけがフォーカスを戻すよう頼む")
    func emptyTextSignalsInsteadOfSaving() async throws {
        try await withFixture { fixture in
            fixture.model.text = ""
            let focusBefore = fixture.model.focusRequest

            fixture.controller.perform(.saveDraft, from: .button)

            #expect(fixture.session.lastSaveEvent == nil)
            #expect(fixture.beeps.count == 1)
            #expect(fixture.model.focusRequest == focusBefore + 1)

            let handled = pressKey(.saveDraft, on: fixture.controller)

            #expect(handled)
            #expect(fixture.session.lastSaveEvent == nil)
            #expect(fixture.beeps.count == 2)
            #expect(fixture.model.focusRequest == focusBefore + 1)
        }
    }

    // MARK: - AC-10

    @Test("AC-10: ⌘B でサイドバーが開き、⌘K でもサイドバーが開いたまま検索に移る")
    func sidebarAndSearchKeys() async throws {
        try await withFixture { fixture in
            #expect(!fixture.controller.sidebarModel.isOpen)

            #expect(pressKey(.toggleSidebar, on: fixture.controller))
            #expect(fixture.controller.sidebarModel.isOpen)

            #expect(pressKey(.openSearch, on: fixture.controller))
            #expect(fixture.controller.sidebarModel.isOpen)
        }
    }

    @Test("AC-10: ⌘E でモードが変わる")
    func toggleModeKey() async throws {
        try await withFixture { fixture in
            let before = fixture.session.mode

            #expect(pressKey(.toggleMode, on: fixture.controller))

            #expect(fixture.session.mode == before.toggled)
        }
    }

    @Test("AC-10: esc でパネルが閉じ、本文は残る")
    func escapeClosesPanel() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            fixture.model.text = "draft"

            let handled = fixture.controller.handleKey(PanelKeyInput(keyCode: KeyCode.escape, modifiers: [], hasMarkedText: false))

            #expect(handled)
            #expect(!fixture.model.isPresented)
            #expect(fixture.model.text == "draft")
        }
    }

    @Test("AC-10: ⌘N で新しい書きかけに、⌘, で設定を開く処理が1回呼ばれ、⇧⌘S でファイルの書き出しが始まる")
    func newDraftSettingsAndExportKeys() async throws {
        try await withFixture { fixture in
            fixture.model.text = "saved"
            fixture.session.saveCurrent()
            #expect(fixture.session.document != .scratch)

            #expect(pressKey(.newDraft, on: fixture.controller))
            #expect(fixture.session.document == .scratch)
            #expect(fixture.model.text == "")

            #expect(pressKey(.openSettings, on: fixture.controller))
            #expect(fixture.settingsOpens.count == 1)

            fixture.model.text = "export"
            #expect(pressKey(.exportToFile, on: fixture.controller))
            #expect(fixture.chooser.requestCount == 1)
        }
    }

    @Test("AC-10: 確定キー・確定+送信キーで true を返して確定を行う(許可が無ければ案内が出てパネルが閉じる)", arguments: [false, true])
    func commitKeysArePerformed(shouldSend: Bool) async throws {
        try await withFixture(isTrusted: false) { fixture in
            fixture.controller.open()
            fixture.model.text = "draft"
            let shortcut = try #require(shouldSend ? fixture.settings.commitAndSendKey : fixture.settings.commitKey)
            let input = PanelKeyInput(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, hasMarkedText: false)

            #expect(fixture.controller.handleKey(input))

            #expect(!fixture.model.isPresented)
            await waitFor { fixture.guideOpens.count > 0 }
            #expect(fixture.guideOpens.count == 1)
        }
    }

    @Test("AC-10: 表にも esc にも確定キーにも当たらないキーは false を返し、何もしない")
    func unrelatedKeyPassesThrough() async throws {
        try await withFixture { fixture in
            let before = fixture.session.mode
            let input = PanelKeyInput(keyCode: 7, modifiers: [.command], hasMarkedText: false, characters: "x")

            #expect(!fixture.controller.handleKey(input))
            #expect(!fixture.controller.handleKey(PanelKeyInput(keyCode: 0, modifiers: [], hasMarkedText: false, characters: "a")))

            #expect(fixture.session.mode == before)
            #expect(!fixture.controller.sidebarModel.isOpen)
        }
    }

    @Test("AC-10: ノートの書きかけでは、帯の挿入・送信のボタンは false を返して何もしない", arguments: [PanelCommand.commit, PanelCommand.commitAndSend])
    func statusBarButtonsDoNothingInNote(command: PanelCommand) async throws {
        try await withFixture(isTrusted: false) { fixture in
            fixture.controller.open()
            fixture.model.text = "memo"
            fixture.session.toggleMode()
            #expect(fixture.session.mode == .note)

            let didPerform = fixture.controller.perform(command, from: .button)

            #expect(!didPerform)
            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "memo")
            #expect(fixture.guideOpens.count == 0)
        }
    }

    // MARK: - AC-11

    @Test("AC-11: 閉じるは、キーでもボタンでも、閉じて本文が残る", arguments: PanelCommandSource.allCases)
    func closeBehavesTheSame(source: PanelCommandSource) async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            fixture.model.text = "下書き"

            #expect(fixture.controller.perform(.close, from: source))

            #expect(!fixture.model.isPresented)
            #expect(fixture.model.text == "下書き")
        }
    }

    @Test("AC-11: 新規は、キーでもボタンでも、新しい書きかけになる", arguments: PanelCommandSource.allCases)
    func newDraftBehavesTheSame(source: PanelCommandSource) async throws {
        try await withFixture { fixture in
            fixture.model.text = "saved"
            fixture.session.saveCurrent()
            #expect(fixture.session.document != .scratch)

            #expect(fixture.controller.perform(.newDraft, from: source))

            #expect(fixture.session.document == .scratch)
            #expect(fixture.model.text == "")
        }
    }

    @Test("AC-11: サイドバーの開閉は、キーでもボタンでも、開閉が切り替わる", arguments: PanelCommandSource.allCases)
    func toggleSidebarBehavesTheSame(source: PanelCommandSource) async throws {
        try await withFixture { fixture in
            #expect(!fixture.controller.sidebarModel.isOpen)

            #expect(fixture.controller.perform(.toggleSidebar, from: source))
            #expect(fixture.controller.sidebarModel.isOpen)

            #expect(fixture.controller.perform(.toggleSidebar, from: source))
            #expect(!fixture.controller.sidebarModel.isOpen)
        }
    }

    @Test("AC-11: 設定を開くは、キーでもボタンでも、onOpenSettings が1回呼ばれる", arguments: PanelCommandSource.allCases)
    func openSettingsBehavesTheSame(source: PanelCommandSource) async throws {
        try await withFixture { fixture in
            #expect(fixture.controller.perform(.openSettings, from: source))

            #expect(fixture.settingsOpens.count == 1)
        }
    }

    // MARK: - AC-14

    @Test("AC-14: アクセシビリティの許可が無いとき、帯の挿入・送信のボタンで、パネルが閉じ、権限の案内が1回呼ばれ、本文は残る",
          arguments: [PanelCommand.commit, PanelCommand.commitAndSend])
    func permissionDeniedButtonsOpenGuide(command: PanelCommand) async throws {
        try await withFixture(isTrusted: false) { fixture in
            fixture.controller.open()
            fixture.model.text = "draft"

            let didPerform = fixture.controller.perform(command, from: .button)

            #expect(didPerform)
            #expect(!fixture.model.isPresented)
            await waitFor { fixture.guideOpens.count > 0 }
            #expect(fixture.guideOpens.count == 1)
            #expect(fixture.model.text == "draft")
        }
    }
}
