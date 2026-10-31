import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct DraftModeKeyTests {
    private static let ownPid: pid_t = 4242
    private static let noReplacement = NSRange(location: NSNotFound, length: 0)
    private let own = InsertionTarget(processIdentifier: DraftModeKeyTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")

    @MainActor
    private struct Fixture {
        let controller: PanelController
        let settings: AppSettings
        let inserter: InserterStub

        var model: PanelModel { controller.model }
        var session: DraftSession { controller.session }
    }

    private func withFixture(
        mode: DraftMode = .insert,
        registeredKeys: (commit: PanelShortcut, send: PanelShortcut)? = nil,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.panelScreen = .main
        settings.animationMode = .off
        settings.commitKey = registeredKeys?.commit ?? .commandShiftReturn
        settings.commitAndSendKey = registeredKeys?.send ?? .commandReturn
        let inserter = InserterStub(result: .inserted)
        let probe = FocusedElementProbeStub()
        let controller = PanelControllerFactory.make(
            settings: settings,
            probe: probe,
            inserter: inserter,
            ownProcessIdentifier: Self.ownPid,
            animator: FakePanelFrameAnimator(),
            shaker: PanelShakerSpy()
        )
        controller.targetOverride = { own }
        defer { controller.panel.orderOut(nil) }
        if mode == .note {
            controller.session.toggleMode()
        }
        try await body(Fixture(controller: controller, settings: settings, inserter: inserter))
    }

    private static func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let match = firstSubview(of: type, in: subview) {
                return match
            }
        }
        return nil
    }

    private func attachEditor(_ controller: PanelController) throws -> PromptTextView {
        let hostingView = try #require(controller.panel.contentView)
        for _ in 0..<5 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            hostingView.layoutSubtreeIfNeeded()
        }
        let textView = try #require(Self.firstSubview(of: PromptTextView.self, in: hostingView))
        controller.panel.makeFirstResponder(textView)
        return textView
    }

    private static func key(
        _ characters: String = "",
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        hasMarkedText: Bool = false
    ) -> PanelKeyInput {
        PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: hasMarkedText, characters: characters)
    }

    private static let toggleKey = key("e", keyCode: 14, modifiers: [.command])
    private static let commitKey = key(keyCode: KeyCode.returnKey, modifiers: [.command, .shift])
    private static let commitAndSendKey = key(keyCode: KeyCode.returnKey, modifiers: [.command])

    private static func keyEvent(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    // MARK: - ⌘E で切り替える

    @Test("AC-9: ⌘E の判定は、どちらのモードでも切り替え。⇧⌘E・⌥⌘E・変換中は切り替えにならない", arguments: DraftMode.allCases)
    func resolverTable(mode: DraftMode) {
        #expect(PanelKeyResolver.action(for: Self.toggleKey, mode: mode) == .toggleMode)
        #expect(PanelKeyResolver.action(for: Self.key("e", keyCode: 14, modifiers: [.command, .shift]), mode: mode) == .passThrough)
        #expect(PanelKeyResolver.action(for: Self.key("e", keyCode: 14, modifiers: [.command, .option]), mode: mode) == .passThrough)
        #expect(PanelKeyResolver.action(for: Self.key("e", keyCode: 14, modifiers: [.command], hasMarkedText: true), mode: mode) == .passThrough)
    }

    @Test("AC-9: ⌘E を押すと、インサートとノートが入れ替わる")
    func commandETogglesMode() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            #expect(fixture.session.mode == .insert)

            #expect(fixture.controller.handleKey(Self.toggleKey))
            #expect(fixture.session.mode == .note)

            #expect(fixture.controller.handleKey(Self.toggleKey))
            #expect(fixture.session.mode == .insert)
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-9: 変換中の ⌘E と、⇧⌘E・⌥⌘E ではモードは変わらず、キーは入力メソッドや入力欄に渡る", arguments: DraftMode.allCases)
    func commandEDoesNotToggleInOtherCases(mode: DraftMode) async throws {
        try await withFixture(mode: mode) { fixture in
            fixture.controller.open()
            let others = [
                Self.key("e", keyCode: 14, modifiers: [.command], hasMarkedText: true),
                Self.key("e", keyCode: 14, modifiers: [.command, .shift]),
                Self.key("e", keyCode: 14, modifiers: [.command, .option]),
            ]

            for input in others {
                #expect(fixture.controller.handleKey(input) == false, "\(input)")
                #expect(fixture.session.mode == mode, "\(input)")
            }
        }
    }

    @Test("AC-9: 一覧・検索欄にフォーカスがあるときも、⌘E はパネルのキーとして届き、切り替わる。入力欄の外の確定の処理は ⌘E を取らない")
    func commandEFromListAndSearchField() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            let event = try Self.keyEvent(characters: "e", keyCode: 14, modifiers: [.command])

            let input = try #require(PromptPanel.panelCommandInput(for: event, hasMarkedText: false))
            #expect(input == Self.toggleKey)
            #expect(fixture.controller.handleKeyOutsideEditor(input) == false)
            #expect(fixture.session.mode == .insert)

            let onKeyEquivalent = try #require(fixture.controller.panel.onKeyEquivalent)
            #expect(onKeyEquivalent(input))
            #expect(fixture.session.mode == .note)
        }
    }

    @Test("AC-9: パネルのキーとして扱う ⌘E は、⇧⌘E・⌥⌘E では届かず、変換中の印は引き継ぐ")
    func panelCommandInputForCommandE() throws {
        let shifted = try Self.keyEvent(characters: "e", keyCode: 14, modifiers: [.command, .shift])
        let optioned = try Self.keyEvent(characters: "e", keyCode: 14, modifiers: [.command, .option])
        let plain = try Self.keyEvent(characters: "e", keyCode: 14, modifiers: [.command])

        #expect(PromptPanel.panelCommandInput(for: shifted, hasMarkedText: false) == nil)
        #expect(PromptPanel.panelCommandInput(for: optioned, hasMarkedText: false) == nil)
        #expect(PromptPanel.panelCommandInput(for: plain, hasMarkedText: true)?.hasMarkedText == true)
    }

    // MARK: - ノートの確定キー

    @Test("AC-13: ノートの判定は、確定+挿入キー・確定+送信キーを改行にし、変換中は入力メソッドに渡す。インサートは今のまま")
    func resolverNoteTable() {
        let commit = Self.commitKey
        let send = Self.commitAndSendKey

        #expect(PanelKeyResolver.action(for: commit, mode: .note) == .insertNewline)
        #expect(PanelKeyResolver.action(for: send, mode: .note) == .insertNewline)
        #expect(PanelKeyResolver.action(for: commit, mode: .insert) == .commit)
        #expect(PanelKeyResolver.action(for: send, mode: .insert) == .commitAndSend)

        let marked = Self.key(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: true)
        #expect(PanelKeyResolver.action(for: marked, mode: .note) == .passThrough)

        let escape = Self.key(keyCode: KeyCode.escape)
        #expect(PanelKeyResolver.action(for: escape, mode: .note) == .cancel)
        let commandK = Self.key("k", keyCode: 40, modifiers: [.command])
        #expect(PanelKeyResolver.action(for: commandK, mode: .note) == .openSearch)
    }

    @Test("AC-13: ノートの書きかけで確定+挿入キー・確定+送信キー(初期値)を押すと、カーソルの位置に改行が1つ入り、パネルは開いたまま、挿入は頼まれない", arguments: [false, true])
    func noteDefaultCommitKeysInsertNewline(shouldSend: Bool) async throws {
        try await withFixture(mode: .note) { fixture in
            fixture.controller.open()
            let textView = try attachEditor(fixture.controller)
            textView.string = "ab"
            textView.setSelectedRange(NSRange(location: 1, length: 0))

            #expect(fixture.controller.handleKey(shouldSend ? Self.commitAndSendKey : Self.commitKey))

            #expect(textView.string == "a\nb")
            #expect(fixture.model.text == "a\nb")
            #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
            #expect(fixture.model.isPresented)
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.session.mode == .note)
        }
    }

    @Test("AC-13: ノートの書きかけで、登録したキー(⇧↩・⌘J)を押しても、カーソルの位置に改行が1つ入り、挿入は頼まれない")
    func noteRegisteredCommitKeysInsertNewline() async throws {
        let commandJ = PanelShortcut(keyCode: 38, modifiers: [.command])
        try await withFixture(mode: .note, registeredKeys: (commit: .shiftReturn, send: commandJ)) { fixture in
            fixture.controller.open()
            let textView = try attachEditor(fixture.controller)
            textView.string = "ab"
            textView.setSelectedRange(NSRange(location: 1, length: 0))
            let shiftReturn = Self.key(keyCode: KeyCode.returnKey, modifiers: [.shift])
            let commandJInput = Self.key("j", keyCode: 38, modifiers: [.command])

            #expect(fixture.controller.handleKey(shiftReturn))
            #expect(textView.string == "a\nb")

            #expect(fixture.controller.handleKey(commandJInput))
            #expect(textView.string == "a\n\nb")

            #expect(fixture.model.isPresented)
            #expect(fixture.inserter.calls.isEmpty)
        }
    }

    @Test("AC-13: ノートの書きかけでも、変換中の確定キーは入力メソッドに渡り、改行も入らない")
    func noteMarkedTextCommitKeyIsPassedThrough() async throws {
        try await withFixture(mode: .note) { fixture in
            fixture.controller.open()
            let textView = try attachEditor(fixture.controller)
            textView.string = "ab"
            textView.setSelectedRange(NSRange(location: 1, length: 0))
            let marked = Self.key(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: true)

            #expect(fixture.controller.handleKey(marked) == false)

            #expect(textView.string == "ab")
            #expect(fixture.inserter.calls.isEmpty)
        }
    }

    @Test("AC-13: 入力欄にフォーカスが無いときにノートで確定キーを押しても、何もせずキーを渡す")
    func noteCommitKeyWithoutEditorDoesNothing() async throws {
        try await withFixture(mode: .note) { fixture in
            fixture.controller.open()
            fixture.model.text = "ab"

            #expect(fixture.controller.handleKey(Self.commitKey) == false)

            #expect(fixture.model.text == "ab")
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-13: インサートの書きかけでは、同じキーで確定する(挿入が頼まれる)")
    func insertCommitKeyStillCommits() async throws {
        try await withFixture(mode: .insert) { fixture in
            fixture.controller.open()
            fixture.model.text = "ab"

            #expect(fixture.controller.handleKey(Self.commitKey))

            for _ in 0..<100 where fixture.inserter.calls.isEmpty {
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.text == "ab")
        }
    }

    // MARK: - ノートでは確定しない

    @Test("AC-14: 入力欄の外の判定は、ノートでは確定キーに何も返さず、インサートでは今までどおり確定を返す")
    func resolverOutsideEditor() {
        #expect(PanelKeyResolver.actionOutsideEditor(for: Self.commitKey, commitKey: .commandShiftReturn, commitAndSendKey: .commandReturn, mode: .note) == nil)
        #expect(PanelKeyResolver.actionOutsideEditor(for: Self.commitAndSendKey, commitKey: .commandShiftReturn, commitAndSendKey: .commandReturn, mode: .note) == nil)
        #expect(PanelKeyResolver.actionOutsideEditor(for: Self.commitKey, commitKey: .commandShiftReturn, commitAndSendKey: .commandReturn, mode: .insert) == .commit)
        #expect(PanelKeyResolver.actionOutsideEditor(for: Self.commitAndSendKey, commitKey: .commandShiftReturn, commitAndSendKey: .commandReturn) == .commitAndSend)
    }

    @Test("AC-14: ノートの書きかけでは、一覧・検索欄で確定キーを押しても確定せず、パネルも本文もそのまま")
    func noteDoesNotCommitOutsideEditor() async throws {
        try await withFixture(mode: .note) { fixture in
            fixture.controller.open()
            fixture.model.text = "hello"

            #expect(fixture.controller.handleKeyOutsideEditor(Self.commitKey) == false)
            #expect(fixture.controller.handleKeyOutsideEditor(Self.commitAndSendKey) == false)

            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "hello")
        }
    }

    @Test("AC-14: ノートの書きかけでは、帯の「挿入」「送信」の処理を呼んでも確定せず、パネルも本文もそのまま", arguments: [false, true])
    func noteDoesNotCommitFromButton(shouldSend: Bool) async throws {
        try await withFixture(mode: .note) { fixture in
            fixture.controller.open()
            fixture.model.text = "hello"

            fixture.controller.commitFromButton(shouldSendAfterInsert: shouldSend)

            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "hello")
        }
    }

    // MARK: - 「ノート」のボタン

    @Test("AC-29: タイトルバーの「ノート」の処理は、ノートの書きかけをインサートにし、本文・挿入先は変えず、パネルは開いたまま")
    func switchToInsertFromButtonLeavesNote() async throws {
        try await withFixture(mode: .note) { fixture in
            fixture.controller.open()
            fixture.model.text = "hello"
            let target = fixture.model.target
            #expect(fixture.session.mode == .note)

            fixture.controller.switchToInsertFromButton()

            #expect(fixture.session.mode == .insert)
            #expect(fixture.model.text == "hello")
            #expect(fixture.model.target == target)
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-29: インサートの書きかけで「ノート」の処理を呼んでも、インサートのまま。ノートにはならない")
    func switchToInsertFromButtonKeepsInsert() async throws {
        try await withFixture(mode: .insert) { fixture in
            fixture.controller.open()
            fixture.model.text = "hello"
            let target = fixture.model.target

            fixture.controller.switchToInsertFromButton()

            #expect(fixture.session.mode == .insert)
            #expect(fixture.model.text == "hello")
            #expect(fixture.model.target == target)
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-28: ⌘E で切り替えても挿入先は変わらない(他のアプリが前面のままかは手動で確かめる)")
    func toggleKeepsInsertionTarget() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            let target = fixture.model.target
            #expect(target == own)

            #expect(fixture.controller.handleKey(Self.toggleKey))
            #expect(fixture.model.target == target)

            #expect(fixture.controller.handleKey(Self.toggleKey))
            #expect(fixture.model.target == target)
        }
    }
}
