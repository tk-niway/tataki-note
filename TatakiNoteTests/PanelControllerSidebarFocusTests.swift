import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelControllerSidebarFocusTests {
    private static let textEdit = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")

    private struct InsertionRequest: Equatable {
        let text: String
        let shouldSend: Bool
    }

    @MainActor
    private final class Fixture {
        let directory: URL
        let defaultsName: String
        let settings: AppSettings
        let library: DraftLibrary
        let probe: FocusedElementProbeStub
        let controller: PanelController
        var insertionRequests: [InsertionRequest] = []

        init(isSidebarOpen: Bool = false) throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let defaultsName = UUID().uuidString
            let defaults = try #require(InMemoryDefaults(suiteName: defaultsName))
            let settings = AppSettings(store: SettingsStore(defaults: defaults))
            settings.isSidebarOpen = isSidebarOpen
            settings.panelScreen = .main
            settings.animationMode = .off
            let library = DraftLibrary(store: DraftLibraryStore(directory: directory))
            let probe = FocusedElementProbeStub()
            self.directory = directory
            self.defaultsName = defaultsName
            self.settings = settings
            self.library = library
            self.probe = probe
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
            controller.onInsertionRequested = { [unowned self] text, _, shouldSend in
                self.insertionRequests.append(InsertionRequest(text: text, shouldSend: shouldSend))
            }
        }

        var model: PanelModel { controller.model }
        var sidebarModel: SidebarModel { controller.sidebarModel }

        func openWithTarget() {
            probe.result = FocusedElementProbe(
                element: AXUIElementCreateApplication(pid_t.max),
                lookup: WatcherFixture.textFieldLookup,
                frame: nil
            )
            controller.targetOverride = { PanelControllerSidebarFocusTests.textEdit }
            controller.open()
        }

        func cleanup() {
            controller.close()
            try? FileManager.default.removeItem(at: directory)
            InMemoryDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        }
    }

    private static func key(
        _ characters: String = "",
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        hasMarkedText: Bool = false
    ) -> PanelKeyInput {
        PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: hasMarkedText, characters: characters)
    }

    private static let commandB = key("b", keyCode: 11, modifiers: [.command])
    private static let commandK = key("k", keyCode: 40, modifiers: [.command])
    private static let commitKey = key(keyCode: KeyCode.returnKey, modifiers: [.command, .shift])
    private static let commitAndSendKey = key(keyCode: KeyCode.returnKey, modifiers: [.command])

    private static func keyDownEvent(keyCode: UInt16) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
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

    // MARK: - 開閉とフォーカス

    @Test("AC-22: ⌘B でサイドバーを開くと一覧へのフォーカスを求め(本文へは求めない)、閉じると本文へフォーカスを戻す")
    func commandBMovesFocusToListOnOpenAndBodyOnClose() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        let bodyBefore = fixture.model.focusRequest

        #expect(fixture.controller.handleKey(Self.commandB))
        #expect(fixture.sidebarModel.isOpen)
        #expect(fixture.sidebarModel.hasPendingListFocus)
        #expect(fixture.model.focusRequest == bodyBefore)

        #expect(fixture.controller.handleKey(Self.commandB))
        #expect(!fixture.sidebarModel.isOpen)
        #expect(fixture.model.focusRequest > bodyBefore)
    }

    @Test("AC-22: 開閉ボタンでサイドバーを開くと一覧へのフォーカスを求め、閉じると本文へフォーカスを戻す")
    func toggleButtonMovesFocusToListOnOpenAndBodyOnClose() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        let bodyBefore = fixture.model.focusRequest

        fixture.controller.toggleSidebarFromButton()
        #expect(fixture.sidebarModel.isOpen)
        #expect(fixture.sidebarModel.hasPendingListFocus)
        #expect(fixture.model.focusRequest == bodyBefore)

        fixture.controller.toggleSidebarFromButton()
        #expect(!fixture.sidebarModel.isOpen)
        #expect(fixture.model.focusRequest > bodyBefore)
    }

    @Test("AC-22: ⌘K は今どおりサイドバーを開いて検索欄へフォーカスを求め、一覧へは求めない")
    func commandKStillFocusesSearchField() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)

        #expect(fixture.controller.handleKey(Self.commandK))

        #expect(fixture.sidebarModel.isOpen)
        #expect(fixture.sidebarModel.hasPendingSearchFocus)
        #expect(!fixture.sidebarModel.hasPendingListFocus)
    }

    @Test("AC-23: 一覧・検索欄へのフォーカスの要求が残ったままパネルを閉じて開き直すと、要求は捨てられ本文にフォーカスを求める")
    func reopeningDiscardsPendingListAndSearchFocus() throws {
        let fixture = try Fixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.controller.isTargetLookupDisabled = true
        fixture.controller.open()
        fixture.sidebarModel.focusList()
        fixture.sidebarModel.openForSearch()
        #expect(fixture.sidebarModel.hasPendingListFocus)
        #expect(fixture.sidebarModel.hasPendingSearchFocus)

        fixture.controller.close()
        let bodyBefore = fixture.model.focusRequest
        fixture.controller.open()

        #expect(fixture.sidebarModel.isOpen)
        #expect(!fixture.sidebarModel.hasPendingListFocus)
        #expect(!fixture.sidebarModel.hasPendingSearchFocus)
        #expect(fixture.model.focusRequest > bodyBefore)
    }

    // MARK: - 一覧の esc

    @Test("AC-21: 一覧の esc でパネルが閉じ、書いた文章は残る。検索欄の esc は閉じずに本文へ戻る")
    func listEscapeClosesPanelButSearchFieldEscapeDoesNot() throws {
        let fixture = try Fixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.model.text = "typed"
        let bodyFocusBefore = fixture.sidebarModel.bodyFocusRequest

        let searchHandled = fixture.sidebarModel.handleKey(
            .escape, source: .searchField, modifiers: [], hasMarkedText: false
        )
        #expect(searchHandled)
        #expect(fixture.model.isPresented)
        #expect(fixture.sidebarModel.bodyFocusRequest == bodyFocusBefore + 1)

        let listHandled = fixture.sidebarModel.handleKey(
            .escape, source: .list, modifiers: [], hasMarkedText: false
        )
        #expect(listHandled)
        #expect(!fixture.model.isPresented)
        #expect(fixture.model.text == "typed")
    }

    // MARK: - 一覧・検索欄での確定キー

    @Test("AC-26: 入力欄の外で確定キー・確定+送信キーを押すと、パネルの文章を確定する(送信するかも確定+送信キーに従う)", arguments: [false, true])
    func commitKeysOutsideEditorCommit(shouldSend: Bool) throws {
        let fixture = try Fixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.openWithTarget()
        #expect(fixture.model.target == Self.textEdit)
        fixture.model.text = "hello"

        let handled = fixture.controller.handleKeyOutsideEditor(
            shouldSend ? Self.commitAndSendKey : Self.commitKey
        )

        #expect(handled)
        #expect(fixture.insertionRequests == [InsertionRequest(text: "hello", shouldSend: shouldSend)])
        #expect(!fixture.model.isPresented)
    }

    @Test("AC-14: ノートの書きかけでは入力欄の外の確定キーも確定せず、変換中も確定しない")
    func noteModeAndMarkedTextDoNotCommit() throws {
        let fixture = try Fixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.openWithTarget()
        fixture.model.text = "hello"

        let markedText = fixture.controller.handleKeyOutsideEditor(
            Self.key(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: true)
        )
        #expect(!markedText)

        fixture.controller.session.toggleMode()
        #expect(fixture.controller.session.mode == .note)
        #expect(!fixture.controller.handleKeyOutsideEditor(Self.commitKey))
        #expect(!fixture.controller.handleKeyOutsideEditor(Self.commitAndSendKey))

        #expect(fixture.insertionRequests.isEmpty)
        #expect(fixture.model.isPresented)
        #expect(fixture.model.text == "hello")
    }

    @Test("AC-26: 確定キー以外のキー(esc・↩・↑ ↓・Tab・⌘K など)は入力欄の外では処理せず、一覧・検索欄に任せる")
    func otherKeysAreNotHandledOutsideEditor() throws {
        let fixture = try Fixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.openWithTarget()
        fixture.model.text = "hello"

        let others = [
            Self.key(keyCode: KeyCode.escape),
            Self.key(keyCode: KeyCode.returnKey),
            Self.key(keyCode: 125),
            Self.key(keyCode: 126),
            Self.key(keyCode: KeyCode.tab),
            Self.key(keyCode: KeyCode.tab, modifiers: [.shift]),
            Self.commandK,
            Self.commandB,
        ]
        for input in others {
            #expect(!fixture.controller.handleKeyOutsideEditor(input))
        }

        #expect(fixture.insertionRequests.isEmpty)
        #expect(fixture.model.isPresented)
    }

    @Test("AC-26: 確定キーを一覧の操作と同じ ⇧Tab にしていると、入力欄の外では ⇧Tab が確定になる")
    func commitKeyOverlappingListKeyCommits() throws {
        let fixture = try Fixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        #expect(fixture.settings.selectCommitKey(PanelShortcut(keyCode: KeyCode.tab, modifiers: [.shift])))
        fixture.openWithTarget()
        fixture.model.text = "hello"

        let handled = fixture.controller.handleKeyOutsideEditor(Self.key(keyCode: KeyCode.tab, modifiers: [.shift]))

        #expect(handled)
        #expect(fixture.insertionRequests == [InsertionRequest(text: "hello", shouldSend: false)])
    }

    @Test("AC-26: actionOutsideEditor は確定・確定+送信だけを返し、変換中・登録の無いキー・他のキーは nil")
    func actionOutsideEditorTable() {
        let commit = PanelShortcut.commandShiftReturn
        let send = PanelShortcut.commandReturn

        #expect(PanelKeyResolver.actionOutsideEditor(for: Self.commitKey, commitKey: commit, commitAndSendKey: send) == .commit)
        #expect(PanelKeyResolver.actionOutsideEditor(for: Self.commitAndSendKey, commitKey: commit, commitAndSendKey: send) == .commitAndSend)
        #expect(PanelKeyResolver.actionOutsideEditor(
            for: Self.key(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: true),
            commitKey: commit,
            commitAndSendKey: send
        ) == nil)
        #expect(PanelKeyResolver.actionOutsideEditor(for: Self.commitKey, commitKey: nil, commitAndSendKey: nil) == nil)
        #expect(PanelKeyResolver.actionOutsideEditor(for: Self.commitAndSendKey, commitKey: commit, commitAndSendKey: nil) == nil)
        #expect(PanelKeyResolver.actionOutsideEditor(for: Self.key(keyCode: KeyCode.escape), commitKey: commit, commitAndSendKey: send) == nil)
        #expect(PanelKeyResolver.actionOutsideEditor(for: Self.commandK, commitKey: commit, commitAndSendKey: send) == nil)
        #expect(PanelKeyResolver.actionOutsideEditor(for: Self.key(keyCode: KeyCode.returnKey), commitKey: commit, commitAndSendKey: send) == nil)
    }

    @Test("AC-26: パネルは入力欄の外のキー押下だけを onKeyDownOutsideEditor に渡し、入力欄にフォーカスがあるときは渡さない")
    func panelRoutesKeyDownsOutsideEditorOnly() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        let panel = fixture.controller.panel
        var received: [PanelKeyInput] = []
        panel.onKeyDownOutsideEditor = { input in
            received.append(input)
            return true
        }
        let event = try Self.keyDownEvent(keyCode: 105)

        panel.sendEvent(event)
        #expect(received.map(\.keyCode) == [105])
        #expect(!received[0].hasMarkedText)

        let hostingView = try #require(panel.contentView)
        let deadline = Date().addingTimeInterval(1)
        var textView: PromptTextView?
        repeat {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            hostingView.layoutSubtreeIfNeeded()
            textView = Self.firstSubview(of: PromptTextView.self, in: hostingView)
        } while textView == nil && Date() < deadline
        let editor = try #require(textView)
        panel.makeFirstResponder(editor)

        panel.sendEvent(event)
        #expect(received.count == 1)
    }
}
