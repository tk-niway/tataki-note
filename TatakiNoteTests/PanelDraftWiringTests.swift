import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelDraftWiringTests {
    private static let textEdit = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
    private static let noReplacement = NSRange(location: NSNotFound, length: 0)

    @MainActor
    private final class Fixture {
        let directory: URL
        let defaultsName: String
        let settings: AppSettings
        let library: DraftLibrary
        let inserter: InserterStub
        let probe: FocusedElementProbeStub
        let controller: PanelController

        init(
            isTrusted: Bool = true,
            isSidebarOpen: Bool = false
        ) throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let defaultsName = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: defaultsName))
            let settings = AppSettings(store: SettingsStore(defaults: defaults))
            settings.isSidebarOpen = isSidebarOpen
            let library = DraftLibrary(store: DraftLibraryStore(directory: directory))
            let inserter = InserterStub(result: .inserted)
            self.directory = directory
            self.defaultsName = defaultsName
            self.settings = settings
            self.library = library
            self.inserter = inserter
            let probe = FocusedElementProbeStub()
            self.probe = probe
            self.controller = PanelController(
                settings: settings,
                targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
                inserter: inserter,
                permission: PermissionStub(isTrusted: isTrusted),
                fieldProbe: probe,
                library: library,
                makeTargetMonitor: InsertionTargetMonitor.testFactory(
                    probe: probe,
                    ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
                )
            )
        }

        var model: PanelModel { controller.model }
        var session: DraftSession { controller.session }
        var sidebarModel: SidebarModel { controller.sidebarModel }

        func cleanup() {
            controller.close()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        }

        func reloadedLibrary() -> DraftLibrary {
            DraftLibrary(store: DraftLibraryStore(directory: directory))
        }

        func addDraft(_ text: String) throws -> SavedDraft {
            try #require(library.addDraft(text: text))
        }

        func attachEditor() throws -> PromptTextView {
            let hostingView = try #require(controller.panel.contentView)
            PanelDraftWiringTests.settle(controller)
            let textView = try #require(PanelDraftWiringTests.firstSubview(of: PromptTextView.self, in: hostingView))
            controller.panel.makeFirstResponder(textView)
            return textView
        }
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

    private static func settle(_ controller: PanelController, until condition: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(1)
        var passes = 0
        repeat {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            controller.panel.contentView?.layoutSubtreeIfNeeded()
            passes += 1
        } while (condition.map { !$0() } ?? (passes < 5)) && Date() < deadline
    }

    private static func key(
        _ characters: String = "",
        keyCode: UInt16 = 0,
        modifiers: NSEvent.ModifierFlags = [],
        hasMarkedText: Bool = false
    ) -> PanelKeyInput {
        PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: hasMarkedText, characters: characters)
    }

    private static func keyEvent(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
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

    private func markText(_ text: String, in textView: PromptTextView) {
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.setMarkedText(
            text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            replacementRange: Self.noReplacement
        )
    }

    // MARK: - ボタンとキー

    @Test("⌘B を押すたびにサイドバーが開閉し、開閉は設定に残り、開くと一覧へ・閉じると本文へフォーカスを求める")
    func sidebarToggleKeyOpensAndClosesSidebar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        let onKeyEquivalent = try #require(fixture.controller.panel.onKeyEquivalent)
        #expect(!fixture.sidebarModel.isOpen)
        let before = fixture.model.focusRequest

        #expect(onKeyEquivalent(Self.key("b", keyCode: 11, modifiers: [.command])))
        #expect(fixture.sidebarModel.isOpen)
        #expect(fixture.sidebarModel.hasPendingListFocus)
        #expect(fixture.model.focusRequest == before)
        #expect(fixture.settings.isSidebarOpen)

        #expect(onKeyEquivalent(Self.key("b", keyCode: 11, modifiers: [.command])))
        #expect(!fixture.sidebarModel.isOpen)
        #expect(fixture.model.focusRequest > before)
        #expect(!fixture.settings.isSidebarOpen)
    }

    @Test("サイドバーの歯車のボタンと ⌘, は、書いた文章を残してパネルを閉じてから設定を開く処理を呼ぶ", arguments: [false, true])
    func settingsButtonAndKeyClosePanelThenOpenSettings(byKey: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.model.text = "typed"
        var wasPresentedWhenOpening: Bool?
        fixture.controller.onOpenSettings = { [model = fixture.model] in
            wasPresentedWhenOpening = model.isPresented
        }

        if byKey {
            let onKeyEquivalent = try #require(fixture.controller.panel.onKeyEquivalent)
            #expect(onKeyEquivalent(Self.key(",", keyCode: 43, modifiers: [.command])))
        } else {
            fixture.controller.openSettings()
        }

        #expect(wasPresentedWhenOpening == false)
        #expect(!fixture.model.isPresented)
        #expect(fixture.model.text == "typed")
    }

    @Test("AC-33: 開閉ボタンで閉じるときと保存のアイコンを押したときは、本文へフォーカスを戻す")
    func sidebarToggleAndSaveButtonsReturnFocusToBody() throws {
        let fixture = try Fixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.model.text = "typed"
        let beforeToggle = fixture.model.focusRequest

        fixture.controller.toggleSidebarFromButton()
        let afterToggle = fixture.model.focusRequest
        fixture.controller.saveDraftFromButton()

        #expect(afterToggle > beforeToggle)
        #expect(fixture.model.focusRequest > afterToggle)
    }

    // MARK: - 書き出し

    @Test("AC-34: パネルを閉じたとき、書き換え途中の下書きが保存先に書き出される")
    func closingFlushesPendingDraft() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let draft = try fixture.addDraft("one")
        fixture.model.present(target: nil)
        fixture.session.request(.draft(draft.id))
        fixture.model.text = "two"
        #expect(fixture.library.hasPendingWrite)
        #expect(fixture.reloadedLibrary().draft(id: draft.id)?.text == "one")

        fixture.controller.close()

        #expect(!fixture.library.hasPendingWrite)
        #expect(fixture.reloadedLibrary().draft(id: draft.id)?.text == "two")
    }

    @Test("AC-34: アプリを終了するとき(prepareForTermination)、書き換え途中の下書きが保存先に書き出される")
    func prepareForTerminationWritesPendingDraft() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let draft = try fixture.addDraft("one")
        fixture.model.present(target: nil)
        fixture.session.request(.draft(draft.id))
        fixture.model.text = "two"
        #expect(fixture.reloadedLibrary().draft(id: draft.id)?.text == "one")

        fixture.controller.prepareForTermination()

        #expect(fixture.reloadedLibrary().draft(id: draft.id)?.text == "two")
    }

    @Test("AC-34: 確定したとき、書き換え途中の下書きが保存先に書き出される")
    func committingFlushesPendingDraft() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let draft = try fixture.addDraft("one")
        fixture.settings.panelScreen = .main
        fixture.settings.isPanelAnimationEnabled = false
        fixture.probe.result = FocusedElementProbe(
            element: AXUIElementCreateApplication(pid_t.max),
            lookup: WatcherFixture.textFieldLookup,
            frame: nil
        )
        fixture.controller.targetOverride = { Self.textEdit }
        fixture.controller.open()
        #expect(fixture.model.target == Self.textEdit)
        fixture.session.request(.draft(draft.id))
        fixture.model.text = "three"
        #expect(fixture.reloadedLibrary().draft(id: draft.id)?.text == "one")

        fixture.controller.commit()

        #expect(fixture.reloadedLibrary().draft(id: draft.id)?.text == "three")
        try await waitUntil(attempts: 200, interval: .milliseconds(10)) { !fixture.library.history.isEmpty }
        #expect(fixture.library.draft(id: draft.id)?.text == "three")
        #expect(fixture.model.text.isEmpty)
    }

    @Test("AC-34: 権限が無く挿入しない確定でも、書き換え途中の下書きが保存先に書き出される")
    func committingWithoutPermissionFlushesPendingDraft() async throws {
        let fixture = try Fixture(isTrusted: false)
        defer { fixture.cleanup() }
        let draft = try fixture.addDraft("one")
        fixture.model.present(target: Self.textEdit)
        fixture.session.request(.draft(draft.id))
        fixture.model.text = "four"

        fixture.controller.commit()

        #expect(fixture.reloadedLibrary().draft(id: draft.id)?.text == "four")
        #expect(fixture.model.text == "four")
        #expect(fixture.session.document == .savedDraft(draft.id))
    }

    // MARK: - 下書きの削除

    @Test("AC-1: パネルを開いて本文にフォーカスがある状態で下書きの削除を求めると、キーを経なくてもすぐ消え、パネルは開いたまま")
    func requestDeleteDeletesImmediatelyWhilePanelIsOpen() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let draft = try fixture.addDraft("saved")
        fixture.model.present(target: nil)
        _ = try fixture.attachEditor()

        fixture.sidebarModel.requestDelete(draft.id)

        #expect(fixture.library.draft(id: draft.id) == nil)
        #expect(fixture.reloadedLibrary().draft(id: draft.id) == nil)
        #expect(fixture.model.isPresented)
    }

    // MARK: - 変換中の ⌘S ⌘N ⌘K

    @Test("AC-50: firstResponderHasMarkedText は、変換中の入力欄だけ true で、変換していない入力欄・nil・入力欄でないものは false")
    func firstResponderMarkedTextProbe() {
        let composing = NSTextView()
        composing.string = "abc"
        composing.setSelectedRange(NSRange(location: 3, length: 0))
        composing.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: Self.noReplacement)
        let idle = NSTextView()
        idle.string = "abc"

        #expect(PromptPanel.firstResponderHasMarkedText(composing))
        #expect(!PromptPanel.firstResponderHasMarkedText(idle))
        #expect(!PromptPanel.firstResponderHasMarkedText(nil))
        #expect(!PromptPanel.firstResponderHasMarkedText(NSResponder()))
    }

    @Test("AC-50: panelCommandInput は ⌘S・⌘K・⌘N だけを値にし(Caps Lock が入っていても)、⌘J や修飾キーの違うものは nil")
    func panelCommandInputRecognizesOnlyReservedKeys() throws {
        let saveEvent = try Self.keyEvent("s", keyCode: 1, modifiers: [.command])
        let searchEvent = try Self.keyEvent("k", keyCode: 40, modifiers: [.command])
        let newEvent = try Self.keyEvent("n", keyCode: 45, modifiers: [.command])
        let capsLockEvent = try Self.keyEvent("s", keyCode: 1, modifiers: [.command, .capsLock])
        let otherLetterEvent = try Self.keyEvent("j", keyCode: 38, modifiers: [.command])
        let shiftedEvent = try Self.keyEvent("s", keyCode: 1, modifiers: [.command, .shift])
        let plainEvent = try Self.keyEvent("s", keyCode: 1, modifiers: [])

        let save = try #require(PromptPanel.panelCommandInput(for: saveEvent, hasMarkedText: false))
        let search = try #require(PromptPanel.panelCommandInput(for: searchEvent, hasMarkedText: false))
        let newDraft = try #require(PromptPanel.panelCommandInput(for: newEvent, hasMarkedText: true))
        let capsLockSave = try #require(PromptPanel.panelCommandInput(for: capsLockEvent, hasMarkedText: false))

        #expect(save.characters == "s")
        #expect(save.keyCode == 1)
        #expect(!save.hasMarkedText)
        #expect(search.characters == "k")
        #expect(newDraft.characters == "n")
        #expect(newDraft.hasMarkedText)
        #expect(capsLockSave.characters == "s")
        #expect(PromptPanel.panelCommandInput(for: otherLetterEvent, hasMarkedText: false) == nil)
        #expect(PromptPanel.panelCommandInput(for: shiftedEvent, hasMarkedText: false) == nil)
        #expect(PromptPanel.panelCommandInput(for: plainEvent, hasMarkedText: false) == nil)
    }

    @Test("AC-50: 変換中の ⌘S・⌘N・⌘K は PromptPanel から handleKey に渡っても false が返り、保存・切り替え・確認・サイドバーの開閉が起きない")
    func markedTextCommandKeysDoNothing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.model.text = "typed"
        let onKeyEquivalent = try #require(fixture.controller.panel.onKeyEquivalent)
        let searchRequestBefore = fixture.sidebarModel.searchFocusRequest

        let saveHandled = onKeyEquivalent(Self.key("s", keyCode: 1, modifiers: [.command], hasMarkedText: true))
        let newHandled = onKeyEquivalent(Self.key("n", keyCode: 45, modifiers: [.command], hasMarkedText: true))
        let searchHandled = onKeyEquivalent(Self.key("k", keyCode: 40, modifiers: [.command], hasMarkedText: true))

        #expect(!saveHandled)
        #expect(!newHandled)
        #expect(!searchHandled)
        #expect(fixture.library.drafts.isEmpty)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.model.text == "typed")
        #expect(!fixture.sidebarModel.isOpen)
        #expect(fixture.sidebarModel.searchFocusRequest == searchRequestBefore)
    }

    @Test("AC-50: 変換中でなければ、PromptPanel に届いた ⌘S は保存になり、⌘K はサイドバーを開いて検索へ、⌘N は新しい書きかけになる")
    func commandKeysWorkWithoutMarkedText() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.model.text = "typed"

        let onKeyEquivalent = try #require(fixture.controller.panel.onKeyEquivalent)

        let searchHandled = onKeyEquivalent(Self.key("k", keyCode: 40, modifiers: [.command]))
        #expect(searchHandled)
        #expect(fixture.sidebarModel.isOpen)
        #expect(fixture.sidebarModel.searchFocusRequest == 1)

        let saveHandled = onKeyEquivalent(Self.key("s", keyCode: 1, modifiers: [.command]))
        #expect(saveHandled)
        #expect(fixture.library.drafts.map(\.text) == ["typed"])

        let newHandled = onKeyEquivalent(Self.key("n", keyCode: 45, modifiers: [.command]))
        #expect(newHandled)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.model.text.isEmpty)

        fixture.model.text = "second"
        let confirmingHandled = onKeyEquivalent(Self.key("n", keyCode: 45, modifiers: [.command]))
        #expect(confirmingHandled)
        #expect(fixture.model.text.isEmpty)
    }

    @Test("AC-50: PromptPanel.performKeyEquivalent は、変換中でなければ ⌘S を処理して true を返す")
    func panelPerformKeyEquivalentRoutesSave() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.model.text = "typed"

        let handled = fixture.controller.panel.performKeyEquivalent(with: try Self.keyEvent("s", keyCode: 1, modifiers: [.command]))

        #expect(handled)
        #expect(fixture.library.drafts.map(\.text) == ["typed"])
    }

    // MARK: - 変換中のクリック

    @Test("AC-51: 本文で変換中に一覧の行をクリックして呼び出すと、変換中の文字が元の下書きに入ってから切り替わり、呼び出した下書きは上書きされない")
    func activatingRowCommitsMarkedTextFirst() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let alpha = try fixture.addDraft("Alpha")
        let bravo = try fixture.addDraft("Bravo")
        fixture.model.present(target: nil)
        fixture.session.request(.draft(alpha.id))
        let textView = try fixture.attachEditor()
        Self.settle(fixture.controller) { textView.string == "Alpha" }
        #expect(textView.string == "Alpha")
        markText("にほんご", in: textView)
        #expect(textView.hasMarkedText())

        fixture.sidebarModel.show(bravo.id)

        #expect(fixture.library.draft(id: alpha.id)?.text == "Alphaにほんご")
        #expect(fixture.model.text == "Bravo")
        #expect(fixture.library.draft(id: bravo.id)?.text == "Bravo")
        #expect(fixture.session.document == .savedDraft(bravo.id))
        Self.settle(fixture.controller) { textView.string == "Bravo" }
        #expect(textView.string == "Bravo")
        #expect(fixture.model.text == "Bravo")
        #expect(fixture.library.draft(id: bravo.id)?.text == "Bravo")
    }

    @Test("AC-51: 本文で変換中に新規作成のアイコンを押すと、変換中の文字が元の下書きに入ってから空の書きかけになる")
    func newDraftButtonCommitsMarkedTextFirst() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let alpha = try fixture.addDraft("Alpha")
        fixture.model.present(target: nil)
        fixture.session.request(.draft(alpha.id))
        let textView = try fixture.attachEditor()
        Self.settle(fixture.controller) { textView.string == "Alpha" }
        markText("にほんご", in: textView)

        fixture.controller.newDraftFromButton()

        #expect(fixture.library.draft(id: alpha.id)?.text == "Alphaにほんご")
        #expect(fixture.model.text.isEmpty)
        #expect(fixture.session.document == .scratch)
        Self.settle(fixture.controller) { textView.string.isEmpty }
        #expect(textView.string.isEmpty)
        #expect(fixture.model.text.isEmpty)
        #expect(fixture.library.draft(id: alpha.id)?.text == "Alphaにほんご")
    }

    @Test("AC-51: 本文で変換中に保存のアイコンを押すと、変換中の文字が確定してから、その文章が下書きに保存される")
    func saveButtonCommitsMarkedTextFirst() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.model.text = "abc"
        let textView = try fixture.attachEditor()
        Self.settle(fixture.controller) { textView.string == "abc" }
        markText("にほんご", in: textView)

        fixture.controller.saveDraftFromButton()

        #expect(fixture.library.drafts.map(\.text) == ["abcにほんご"])
        #expect(fixture.model.text == "abcにほんご")
        #expect(!textView.hasMarkedText())
    }

    @Test("AC-3: 本文で変換中に行の右クリックのメニューの削除(requestDelete)を呼ぶと、変換中の文字が元の下書きに入ってから、別の下書きが消える")
    func requestDeleteCommitsMarkedTextFirst() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let alpha = try fixture.addDraft("Alpha")
        let bravo = try fixture.addDraft("Bravo")
        fixture.model.present(target: nil)
        fixture.session.request(.draft(alpha.id))
        let textView = try fixture.attachEditor()
        Self.settle(fixture.controller) { textView.string == "Alpha" }
        markText("にほんご", in: textView)

        fixture.sidebarModel.requestDelete(bravo.id)

        #expect(fixture.library.draft(id: alpha.id)?.text == "Alphaにほんご")
        #expect(fixture.library.draft(id: bravo.id) == nil)
        #expect(!textView.hasMarkedText())
    }

    // MARK: - 窓の枠(サイドバーの幅)

    @Test("AC-27: サイドバーを開いたパネルで幅を変えずにライブリサイズが終わっても、ドラッグで決めた大きさは変わらない")
    func liveResizeWithoutChangeKeepsHeldSize() throws {
        let fixture = try Fixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.controller.panel.setFrame(NSRect(x: 100, y: 100, width: 740, height: 340), display: false)
        let notification = Notification(name: NSWindow.willStartLiveResizeNotification, object: fixture.controller.panel)

        fixture.controller.windowWillStartLiveResize(notification)
        fixture.controller.windowDidEndLiveResize(notification)

        #expect(fixture.controller.heldPanelSize == nil)
    }

    @Test("AC-27: サイドバーを開いたパネルで幅をドラッグすると、サイドバーの幅を除いた本文の大きさを覚える")
    func liveResizeKeepsBodySize() throws {
        let fixture = try Fixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.controller.panel.setFrame(NSRect(x: 100, y: 100, width: 740, height: 340), display: false)
        let notification = Notification(name: NSWindow.willStartLiveResizeNotification, object: fixture.controller.panel)

        fixture.controller.windowWillStartLiveResize(notification)
        fixture.controller.panel.setFrame(NSRect(x: 100, y: 100, width: 840, height: 340), display: false)
        fixture.controller.windowDidEndLiveResize(notification)

        #expect(fixture.controller.heldPanelSize == CGSize(width: 840 - SidebarLayout.width, height: 340))
    }

    @Test("AC-27: サイドバーを閉じているパネルのドラッグは今まで通り窓の大きさを覚える")
    func liveResizeWithClosedSidebarKeepsWindowSize() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.controller.panel.setFrame(NSRect(x: 100, y: 100, width: 520, height: 340), display: false)
        let notification = Notification(name: NSWindow.willStartLiveResizeNotification, object: fixture.controller.panel)

        fixture.controller.windowWillStartLiveResize(notification)
        fixture.controller.panel.setFrame(NSRect(x: 100, y: 100, width: 600, height: 340), display: false)
        fixture.controller.windowDidEndLiveResize(notification)

        #expect(fixture.controller.heldPanelSize == CGSize(width: 600, height: 340))
    }

    @Test("AC-27: 開閉で窓の枠を変えている間(isAdjustingFrameForSidebar)のライブリサイズの通知では、大きさを覚えない")
    func liveResizeIsIgnoredWhileAdjustingForSidebar() throws {
        let fixture = try Fixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.controller.panel.setFrame(NSRect(x: 100, y: 100, width: 740, height: 340), display: false)
        let notification = Notification(name: NSWindow.willStartLiveResizeNotification, object: fixture.controller.panel)

        fixture.controller.isAdjustingFrameForSidebar = true
        fixture.controller.windowWillStartLiveResize(notification)
        fixture.controller.panel.setFrame(NSRect(x: 100, y: 100, width: 900, height: 340), display: false)
        fixture.controller.windowDidEndLiveResize(notification)
        fixture.controller.isAdjustingFrameForSidebar = false

        #expect(fixture.controller.heldPanelSize == nil)
    }

    @Test("AC-27: サイドバーを開くと窓が左へ広がって右端は動かず、閉じると元の枠に戻り、ドラッグで決めた大きさは変わらない")
    func togglingSidebarChangesWindowFrame() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        let bodyFrame = NSRect(x: 500, y: 200, width: 520, height: 340)
        fixture.controller.panel.setFrame(bodyFrame, display: false)

        fixture.controller.setSidebarOpen(true)

        let expanded = fixture.controller.panel.frame
        #expect(fixture.sidebarModel.isOpen)
        #expect(fixture.settings.isSidebarOpen)
        #expect(expanded.width == bodyFrame.width + SidebarLayout.width)
        #expect(expanded.maxX == bodyFrame.maxX)
        #expect(expanded.minY == bodyFrame.minY)
        #expect(expanded.height == bodyFrame.height)
        #expect(fixture.controller.panel.contentMinSize == SidebarLayout.minimumWindowSize(isSidebarOpen: true))

        fixture.controller.setSidebarOpen(false)

        #expect(fixture.controller.panel.frame == bodyFrame)
        #expect(!fixture.settings.isSidebarOpen)
        #expect(fixture.controller.panel.contentMinSize == PanelSizing.minimumSize)
        #expect(fixture.controller.heldPanelSize == nil)
    }

    @Test("AC-27: パネルが閉じている間のサイドバーの開閉は設定だけを変え、窓の枠は変えない")
    func togglingSidebarWhileClosedKeepsFrame() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let frame = NSRect(x: 500, y: 200, width: 520, height: 340)
        fixture.controller.panel.setFrame(frame, display: false)

        fixture.controller.setSidebarOpen(true)

        #expect(fixture.settings.isSidebarOpen)
        #expect(fixture.controller.panel.frame == frame)
    }

    @Test("AC-27: 窓の最小の大きさは、サイドバーを開いている間だけサイドバーの幅だけ大きい")
    func windowMinimumSizeFollowsSidebar() throws {
        let closed = try Fixture()
        defer { closed.cleanup() }
        let open = try Fixture(isSidebarOpen: true)
        defer { open.cleanup() }
        let tiny = NSSize(width: 100, height: 50)

        let closedSize = closed.controller.windowWillResize(closed.controller.panel, to: tiny)
        let openSize = open.controller.windowWillResize(open.controller.panel, to: tiny)

        #expect(closedSize == PanelSizing.minimumSize)
        #expect(openSize.width == PanelSizing.minimumSize.width + SidebarLayout.width)
        #expect(openSize.height == PanelSizing.minimumSize.height)
    }
}
