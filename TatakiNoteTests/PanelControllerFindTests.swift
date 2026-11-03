import AppKit
import Testing
@testable import TatakiNote

@MainActor
private final class FakeFindField: NSTextField, FindFieldIdentifying {
    let findField: FindField

    init(_ field: FindField) {
        findField = field
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
    }

    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
struct PanelControllerFindTests {
    @MainActor
    private struct Fixture {
        let controller: PanelController
        let settings: AppSettings
        let textView: PromptTextView
        let animator: FakePanelFrameAnimator
        fileprivate let findField: FakeFindField
        fileprivate let replaceField: FakeFindField

        var panel: PromptPanel { controller.panel }
        var findModel: FindModel { controller.findModel }
        var model: PanelModel { controller.model }

        var snapshot: Snapshot {
            Snapshot(
                isBarVisible: findModel.isBarVisible,
                isReplaceShown: findModel.isReplaceShown,
                text: textView.string,
                selection: textView.selectedRange(),
                options: findModel.options,
                focusCount: findModel.focusRequest.count
            )
        }

        func focus(_ responder: NSResponder) {
            panel.makeFirstResponder(responder)
        }

        func openBar(revealsReplace: Bool = false, query: String = "foo", replacement: String = "X") {
            controller.findController.perform(FindKeyAction.open(revealsReplace: revealsReplace))
            findModel.query = query
            findModel.replacement = replacement
        }
    }

    @MainActor
    private struct Snapshot: Equatable {
        let isBarVisible: Bool
        let isReplaceShown: Bool
        let text: String
        let selection: NSRange
        let options: FindOptions
        let focusCount: Int
    }

    private func withFixture(
        marked: String = "|foo bar foo baz foo",
        isTrusted: Bool = true,
        animated: Bool = false,
        _ body: (Fixture) throws -> Void
    ) throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.animationMode = animated ? .on : .off
        settings.panelScreen = .main
        settings.commitKey = .commandShiftReturn
        settings.commitAndSendKey = .commandReturn
        let animator = FakePanelFrameAnimator()
        let controller = PanelControllerFactory.make(
            settings: settings,
            permission: PermissionStub(isTrusted: isTrusted),
            animator: animator
        )
        controller.isTargetLookupDisabled = true
        defer {
            if animated {
                controller.closeImmediately()
            } else {
                controller.close()
            }
        }
        controller.open()

        let (text, selection) = MarkedText.parse(marked)
        let textView = PromptTextView()
        textView.isRichText = false
        textView.string = text
        let findField = FakeFindField(.find)
        let replaceField = FakeFindField(.replace)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        container.addSubview(textView)
        container.addSubview(findField)
        container.addSubview(replaceField)
        controller.panel.contentView = container
        controller.findEditorRegistry.editor = textView
        let findModel = controller.findModel
        textView.onStringChange = { findModel.textDidChange() }
        textView.onSelectionChange = { findModel.selectionDidChange() }
        controller.panel.makeFirstResponder(textView)
        textView.setSelectedRange(selection)
        controller.model.text = "draft"

        try body(
            Fixture(
                controller: controller,
                settings: settings,
                textView: textView,
                animator: animator,
                findField: findField,
                replaceField: replaceField
            )
        )
    }

    private func input(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags, _ characters: String = "") -> PanelKeyInput {
        PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: false, characters: characters)
    }

    private var commandF: PanelKeyInput { input(3, [.command], "f") }
    private var optionCommandF: PanelKeyInput { input(3, [.command, .option], "f") }
    private var commandG: PanelKeyInput { input(5, [.command], "g") }
    private var shiftCommandG: PanelKeyInput { input(5, [.command, .shift], "g") }
    private var shiftCommandOne: PanelKeyInput { input(18, [.command, .shift], "!") }
    private var optionCommandReturn: PanelKeyInput { input(KeyCode.returnKey, [.command, .option]) }
    private var escape: PanelKeyInput { input(KeyCode.escape, []) }

    private let optionKeys: [(option: FindOption, key: PanelKeyInput)] = [
        (.caseSensitive, PanelKeyInput(keyCode: 8, modifiers: [.command, .option], hasMarkedText: false, characters: "c")),
        (.wholeWord, PanelKeyInput(keyCode: 13, modifiers: [.command, .option], hasMarkedText: false, characters: "w")),
        (.regex, PanelKeyInput(keyCode: 15, modifiers: [.command, .option], hasMarkedText: false, characters: "r")),
        (.preserveCase, PanelKeyInput(keyCode: 35, modifiers: [.command, .option], hasMarkedText: false, characters: "p")),
    ]

    // MARK: - AC-14

    @Test("AC-14: 検索欄・置換欄で ⌘↩・⇧⌘↩ を押しても確定にならず、パネルは開いたまま")
    func commitKeysInFieldsDoNotCommit() throws {
        try withFixture(isTrusted: false) { fixture in
            fixture.openBar(revealsReplace: true)
            for field in [fixture.findField, fixture.replaceField] {
                fixture.focus(field)
                #expect(PanelFindController.focus(of: fixture.panel.firstResponder) != .other)

                #expect(fixture.controller.handleKeyOutsideEditor(input(KeyCode.returnKey, [.command])))
                #expect(fixture.controller.handleKeyOutsideEditor(input(KeyCode.returnKey, [.command, .shift])))

                #expect(fixture.model.isPresented)
            }
            #expect(fixture.model.text == "draft")
        }
    }

    @Test("AC-14: 置換欄の ⌘↩ はすべて置換になり、検索欄の ⌘↩ は文章を変えない")
    func commandReturnInReplaceFieldReplacesAll() throws {
        try withFixture(isTrusted: false) { fixture in
            fixture.openBar(revealsReplace: true)

            fixture.focus(fixture.findField)
            #expect(fixture.controller.handleKeyOutsideEditor(input(KeyCode.returnKey, [.command])))
            #expect(fixture.textView.string == "foo bar foo baz foo")

            fixture.focus(fixture.replaceField)
            #expect(fixture.controller.handleKeyOutsideEditor(input(KeyCode.returnKey, [.command, .shift])))
            #expect(fixture.textView.string == "foo bar foo baz foo")

            #expect(fixture.controller.handleKeyOutsideEditor(input(KeyCode.returnKey, [.command])))
            #expect(fixture.textView.string == "X bar X baz X")
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-14: 検索に使わないキーを確定キーにしていれば、検索欄・置換欄の中でもそのキーで確定する")
    func nonFindCommitKeyStillCommitsInFields() throws {
        for field in [FindField.find, FindField.replace] {
            try withFixture(isTrusted: false) { fixture in
                fixture.settings.commitKey = PanelShortcut(keyCode: 38, modifiers: [.command])
                fixture.openBar(revealsReplace: true)
                fixture.focus(field == .find ? fixture.findField : fixture.replaceField)

                #expect(fixture.controller.handleKeyOutsideEditor(input(38, [.command], "j")))

                #expect(!fixture.model.isPresented)
            }
        }
    }

    @Test("AC-14: 検索バーが出ていないとき、⇧⌘1・⌥⌘↩ は確定にならず、文章も変わらない")
    func replaceKeysWithoutBarAreSwallowed() throws {
        try withFixture(isTrusted: false) { fixture in
            #expect(!fixture.findModel.isBarVisible)
            fixture.findModel.replacement = "X"

            #expect(fixture.controller.handleKey(shiftCommandOne))
            #expect(fixture.controller.handleKey(optionCommandReturn))

            #expect(fixture.textView.string == "foo bar foo baz foo")
            #expect(fixture.model.text == "draft")
            #expect(fixture.model.isPresented)
            #expect(!fixture.findModel.isBarVisible)
        }
    }

    // MARK: - AC-29

    @Test("AC-29: ⌘F で検索バーが出て、検索欄へのフォーカスが求められ、入力欄の1行の選択が検索語になる")
    func commandFOpensBarAndSeedsQuery() throws {
        try withFixture(marked: "[foo] bar foo") { fixture in
            let before = fixture.findModel.focusRequest.count

            #expect(fixture.controller.handleKey(commandF))

            #expect(fixture.findModel.isBarVisible)
            #expect(!fixture.findModel.isReplaceShown)
            #expect(fixture.findModel.query == "foo")
            #expect(fixture.findModel.focusRequest.count == before + 1)
            #expect(fixture.findModel.hasPendingFocus(for: .find))
        }
    }

    @Test("AC-29: 選択が無ければ ⌘F は検索語を変えずに検索欄へのフォーカスを求める")
    func commandFWithoutSelectionKeepsQuery() throws {
        try withFixture { fixture in
            fixture.findModel.query = "bar"

            #expect(fixture.controller.handleKey(commandF))

            #expect(fixture.findModel.query == "bar")
            #expect(fixture.findModel.hasPendingFocus(for: .find))
        }
    }

    @Test("AC-29: ⌥⌘F は置換の欄まで出し、種を入れたときは置換欄へ、入れないときは検索欄へのフォーカスを求める")
    func optionCommandFRevealsReplace() throws {
        try withFixture(marked: "[foo] bar foo") { fixture in
            #expect(fixture.controller.handleKey(optionCommandF))

            #expect(fixture.findModel.isBarVisible)
            #expect(fixture.findModel.isReplaceShown)
            #expect(fixture.findModel.query == "foo")
            #expect(fixture.findModel.hasPendingFocus(for: .replace))
        }
        try withFixture { fixture in
            #expect(fixture.controller.handleKey(optionCommandF))

            #expect(fixture.findModel.isReplaceShown)
            #expect(fixture.findModel.hasPendingFocus(for: .find))
        }
    }

    @Test("AC-29: ⌘F は開いている置換の欄を閉じない")
    func commandFKeepsReplaceShown() throws {
        try withFixture { fixture in
            #expect(fixture.controller.handleKey(optionCommandF))
            #expect(fixture.findModel.isReplaceShown)

            #expect(fixture.controller.handleKey(commandF))

            #expect(fixture.findModel.isBarVisible)
            #expect(fixture.findModel.isReplaceShown)
        }
    }

    @Test("AC-29: パネルの検索のキーの入口(performKeyEquivalent の先)でも ⌘F で検索バーが出る")
    func panelFindKeyEquivalentOpensBar() throws {
        try withFixture { fixture in
            let handler = try #require(fixture.panel.onFindKeyEquivalent)

            #expect(handler(commandF))

            #expect(fixture.findModel.isBarVisible)
        }
    }

    @Test("AC-29: 検索バーが出ていないとき、⌥⌘C・⌥⌘W・⌥⌘R・⌥⌘P はオプションだけを切り替え、検索バーは出さない")
    func optionKeysToggleWithoutBar() throws {
        for (option, key) in optionKeys {
            try withFixture { fixture in
                #expect(!fixture.findModel.options.isOn(option))

                #expect(fixture.controller.handleKey(key))

                #expect(fixture.findModel.options.isOn(option))
                for other in FindOption.allCases where other != option {
                    #expect(!fixture.findModel.options.isOn(other))
                }
                #expect(!fixture.findModel.isBarVisible)

                #expect(fixture.controller.handleKey(key))
                #expect(!fixture.findModel.options.isOn(option))
            }
        }
    }

    // MARK: - AC-37

    @Test("AC-37: タイトルバーの虫眼鏡(openFind)を押すと、検索バーが出て検索欄へのフォーカスが求められる")
    func openFindButtonOpensBarAndRequestsFocus() throws {
        try withFixture(marked: "[foo] bar foo") { fixture in
            let before = fixture.findModel.focusRequest.count
            #expect(!fixture.findModel.isBarVisible)

            #expect(fixture.controller.perform(.openFind, from: .button))

            #expect(fixture.findModel.isBarVisible)
            #expect(!fixture.findModel.isReplaceShown)
            #expect(fixture.findModel.focusRequest.count == before + 1)
            #expect(fixture.findModel.hasPendingFocus(for: .find))
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-37: 虫眼鏡は開いている置換の欄を閉じず、押すたびに検索欄へのフォーカスを求め直す")
    func openFindButtonKeepsReplaceShownAndRequestsFocusAgain() throws {
        try withFixture { fixture in
            #expect(fixture.controller.handleKey(optionCommandF))
            fixture.findModel.didApplyFocus()
            #expect(!fixture.findModel.hasPendingFocus(for: .find))
            let before = fixture.findModel.focusRequest.count

            #expect(fixture.controller.perform(.openFind, from: .button))

            #expect(fixture.findModel.isReplaceShown)
            #expect(fixture.findModel.focusRequest.count == before + 1)
            #expect(fixture.findModel.hasPendingFocus(for: .find))
        }
    }

    // MARK: - AC-30

    @Test("AC-30: 入力欄の esc は検索バーを閉じて入力欄にフォーカスを戻し、パネルは閉じない")
    func escapeInEditorClosesBar() throws {
        try withFixture { fixture in
            fixture.openBar()
            let selection = fixture.textView.selectedRange()

            #expect(fixture.controller.handleKey(escape))

            #expect(!fixture.findModel.isBarVisible)
            #expect(fixture.model.isPresented)
            #expect(fixture.panel.firstResponder === fixture.textView)
            #expect(fixture.textView.selectedRange() == selection)
            #expect(fixture.findModel.query == "foo")
        }
    }

    @Test("AC-30: 検索欄・置換欄の esc は検索バーを閉じて入力欄にフォーカスを戻し、パネルは閉じない")
    func escapeInFieldsClosesBar() throws {
        for isReplaceField in [false, true] {
            try withFixture { fixture in
                fixture.openBar(revealsReplace: true)
                fixture.focus(isReplaceField ? fixture.replaceField : fixture.findField)
                #expect(fixture.panel.firstResponder !== fixture.textView)

                #expect(fixture.controller.handleKeyOutsideEditor(escape))

                #expect(!fixture.findModel.isBarVisible)
                #expect(fixture.model.isPresented)
                #expect(fixture.panel.firstResponder === fixture.textView)
            }
        }
    }

    @Test("AC-30: 検索バーが出ていないときの入力欄の esc は、今までどおりパネルを閉じる")
    func escapeWithoutBarClosesPanel() throws {
        try withFixture { fixture in
            #expect(!fixture.findModel.isBarVisible)

            #expect(fixture.controller.handleKey(escape))

            #expect(!fixture.model.isPresented)
        }
    }

    // MARK: - AC-31

    @Test("AC-31: 検索バーが出ていないときの ⌘G・⇧⌘G は、フォーカスを求めずに検索バーを出して次・前の一致へ移る")
    func nextAndPreviousOpenBarWithoutFocus() throws {
        try withFixture { fixture in
            fixture.openBar()
            fixture.controller.findController.perform(FindKeyAction.close)
            #expect(!fixture.findModel.isBarVisible)
            let before = fixture.findModel.focusRequest.count

            #expect(fixture.controller.handleKey(commandG))

            #expect(fixture.findModel.isBarVisible)
            #expect(fixture.findModel.focusRequest.count == before)
            #expect(!fixture.findModel.hasPendingFocus(for: .find))
            #expect(fixture.textView.selectedRange() == NSRange(location: 8, length: 3))
        }
        try withFixture { fixture in
            fixture.openBar()
            fixture.controller.findController.perform(FindKeyAction.close)
            let before = fixture.findModel.focusRequest.count

            #expect(fixture.controller.handleKey(shiftCommandG))

            #expect(fixture.findModel.isBarVisible)
            #expect(fixture.findModel.focusRequest.count == before)
            #expect(fixture.textView.selectedRange() == NSRange(location: 16, length: 3))
        }
    }

    @Test("AC-31: 検索語が空で選択があるとき、検索バーが出ていない ⌘G は選択を検索語にして移る")
    func nextSeedsEmptyQuery() throws {
        try withFixture(marked: "[foo] bar foo") { fixture in
            #expect(fixture.findModel.query.isEmpty)

            #expect(fixture.controller.handleKey(commandG))

            #expect(fixture.findModel.query == "foo")
            #expect(fixture.textView.selectedRange() == NSRange(location: 8, length: 3))
            #expect(!fixture.findModel.hasPendingFocus(for: .find))
        }
    }

    @Test("AC-31: 検索バーのボタンは、対応するキーの操作と同じ結果になる")
    func barButtonsMatchKeys() throws {
        let cases: [(name: String, action: FindBarAction, key: PanelKeyInput)] = [
            ("次へ", .next, commandG),
            ("前へ", .previous, shiftCommandG),
            ("閉じる", .close, escape),
            ("次を置換", .replaceOne, shiftCommandOne),
            ("すべて置換", .replaceAll, optionCommandReturn),
            ("大文字と小文字", .toggle(.caseSensitive), optionKeys[0].key),
            ("単語単位", .toggle(.wholeWord), optionKeys[1].key),
            ("正規表現", .toggle(.regex), optionKeys[2].key),
            ("大文字と小文字を保持", .toggle(.preserveCase), optionKeys[3].key),
        ]
        for testCase in cases {
            var initial: Snapshot?
            var keyResult: Snapshot?
            var buttonResult: Snapshot?
            try withFixture { fixture in
                fixture.openBar()
                initial = fixture.snapshot
                #expect(fixture.controller.handleKey(testCase.key), "\(testCase.name)のキー")
                keyResult = fixture.snapshot
            }
            try withFixture { fixture in
                fixture.openBar()
                fixture.controller.findController.perform(testCase.action)
                buttonResult = fixture.snapshot
            }
            #expect(buttonResult == keyResult, "\(testCase.name)のボタンはキーと同じ結果")
            #expect(buttonResult != initial, "\(testCase.name)のボタンは何かを変える")
        }
    }

    @Test("AC-31: 次・前・閉じる・置換のボタンの結果")
    func barButtonResults() throws {
        try withFixture { fixture in
            fixture.openBar()
            fixture.controller.findController.perform(FindBarAction.next)
            #expect(fixture.textView.selectedRange() == NSRange(location: 8, length: 3))
            fixture.controller.findController.perform(FindBarAction.previous)
            #expect(fixture.textView.selectedRange() == NSRange(location: 0, length: 3))
            fixture.controller.findController.perform(FindBarAction.replaceOne)
            #expect(fixture.textView.string == "X bar foo baz foo")
            fixture.controller.findController.perform(FindBarAction.replaceAll)
            #expect(fixture.textView.string == "X bar X baz X")
            fixture.controller.findController.perform(FindBarAction.close)
            #expect(!fixture.findModel.isBarVisible)
            #expect(fixture.panel.firstResponder === fixture.textView)
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-31: 置換の欄の開閉のボタンで、置換の欄が出入りし、検索語・置換語は残る")
    func toggleReplaceButton() throws {
        try withFixture { fixture in
            fixture.openBar()
            #expect(!fixture.findModel.isReplaceShown)

            fixture.controller.findController.perform(FindBarAction.toggleReplace)
            #expect(fixture.findModel.isReplaceShown)

            fixture.controller.findController.perform(FindBarAction.toggleReplace)
            #expect(!fixture.findModel.isReplaceShown)
            #expect(fixture.findModel.isBarVisible)
            #expect(fixture.findModel.query == "foo")
            #expect(fixture.findModel.replacement == "X")
        }
    }

    @Test("AC-31: 4つのオプションのボタンは、1回目でオン、2回目でオフになる")
    func optionButtonsToggle() throws {
        try withFixture { fixture in
            fixture.openBar()
            for option in FindOption.allCases {
                fixture.controller.findController.perform(FindBarAction.toggle(option))
                #expect(fixture.findModel.options.isOn(option))
            }
            for option in FindOption.allCases {
                fixture.controller.findController.perform(FindBarAction.toggle(option))
                #expect(!fixture.findModel.options.isOn(option))
            }
        }
    }

    // MARK: - AC-32

    private var findBarHeight: CGFloat { FindBarMetrics.height(isVisible: true, isReplaceShown: false) }
    private var replaceBarHeight: CGFloat { FindBarMetrics.height(isVisible: true, isReplaceShown: true) }

    @Test("AC-32: ⌘F で窓が検索バーの高さだけ伸び、esc で閉じると戻り、ドラッグで決めた大きさにはならない")
    func barStretchesAndRestoresPanel() throws {
        try withFixture { fixture in
            let base = fixture.panel.frame.height

            #expect(fixture.controller.handleKey(commandF))

            #expect(fixture.panel.frame.height == base + findBarHeight)
            #expect(fixture.controller.sizeController.findBarHeight == findBarHeight)
            #expect(fixture.controller.heldPanelSize == nil)

            #expect(fixture.controller.handleKey(escape))

            #expect(fixture.panel.frame.height == base)
            #expect(fixture.controller.sizeController.findBarHeight == 0)
            #expect(fixture.controller.heldPanelSize == nil)
        }
    }

    @Test("AC-32: 置換の欄の開閉で窓が伸び縮みし、閉じるボタンで元の高さに戻る")
    func replaceRowStretchesPanel() throws {
        try withFixture { fixture in
            let base = fixture.panel.frame.height

            #expect(fixture.controller.handleKey(optionCommandF))
            #expect(fixture.panel.frame.height == base + replaceBarHeight)

            fixture.controller.findController.perform(FindBarAction.toggleReplace)
            #expect(fixture.panel.frame.height == base + findBarHeight)

            fixture.controller.findController.perform(FindBarAction.toggleReplace)
            #expect(fixture.panel.frame.height == base + replaceBarHeight)

            fixture.controller.findController.perform(FindBarAction.close)
            #expect(fixture.panel.frame.height == base)
            #expect(fixture.controller.heldPanelSize == nil)
        }
    }

    @Test("AC-32: 検索バーが出ている間に窓をドラッグすると、検索バーの分を除いた大きさを覚える")
    func dragWhileBarShownRemembersBodySize() throws {
        try withFixture { fixture in
            let base = fixture.panel.frame.height
            #expect(fixture.controller.handleKey(commandF))
            let size = CGSize(width: fixture.panel.frame.width, height: base + findBarHeight + 40)

            fixture.controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification))
            fixture.panel.setFrame(NSRect(origin: fixture.panel.frame.origin, size: size), display: false)
            fixture.controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))

            #expect(fixture.controller.heldPanelSize?.height == base + 40)
        }
    }

    // MARK: - AC-33

    @Test("AC-33: 検索バーを出したまま閉じて開き直すと、状態と窓の高さが残り、開いた時点の文章で数え直す")
    func reopenKeepsBarStateAndHeight() throws {
        try withFixture { fixture in
            fixture.openBar(revealsReplace: true, query: "foo", replacement: "X")
            fixture.findModel.toggle(.caseSensitive)
            let heightWithBar = fixture.panel.frame.height
            #expect(fixture.findModel.matches.count == 3)

            fixture.controller.close()
            #expect(!fixture.model.isPresented)
            fixture.textView.onStringChange = nil
            fixture.textView.string = "foo foo"
            fixture.controller.open()

            #expect(fixture.findModel.isBarVisible)
            #expect(fixture.findModel.isReplaceShown)
            #expect(fixture.findModel.query == "foo")
            #expect(fixture.findModel.replacement == "X")
            #expect(fixture.findModel.options.isOn(.caseSensitive))
            #expect(fixture.panel.frame.height == heightWithBar)
            #expect(fixture.controller.sizeController.findBarHeight == replaceBarHeight)
            #expect(fixture.controller.heldPanelSize == nil)
            #expect(fixture.findModel.matches.count == 2)
        }
    }

    @Test("AC-33: 検索バーが閉じているときの開き直しは、検索バーの分を足さない")
    func reopenWithoutBarKeepsHeight() throws {
        try withFixture { fixture in
            let base = fixture.panel.frame.height
            fixture.openBar()
            fixture.controller.findController.perform(FindKeyAction.close)

            fixture.controller.close()
            fixture.controller.open()

            #expect(fixture.panel.frame.height == base)
            #expect(fixture.controller.sizeController.findBarHeight == 0)
        }
    }

    @Test("AC-33: 検索バーを出したまま別の下書きを開いても、検索バーの状態は残る")
    func newDraftKeepsBarState() throws {
        try withFixture { fixture in
            fixture.openBar(revealsReplace: true, query: "foo", replacement: "X")

            fixture.controller.perform(.newDraft, from: .key)

            #expect(fixture.findModel.isBarVisible)
            #expect(fixture.findModel.isReplaceShown)
            #expect(fixture.findModel.query == "foo")
            #expect(fixture.findModel.replacement == "X")
        }
    }

    // MARK: - AC-35

    @Test("AC-35: 開く動きの途中で検索バーを出しても、動きが終わるまで窓は変わらず、終わると検索バーの分に合う")
    func barOpenedDuringOpeningMotionAppliesAfterMotion() throws {
        try withFixture(animated: true) { fixture in
            let call = try #require(fixture.animator.calls.first)
            let restFrame = call.frame
            let lineFrame = fixture.panel.frame

            #expect(fixture.controller.handleKey(commandF))

            #expect(fixture.findModel.isBarVisible)
            #expect(fixture.panel.frame == lineFrame)
            #expect(fixture.controller.sizeController.findBarHeight == 0)

            fixture.animator.finish(0)

            #expect(fixture.panel.frame.height == restFrame.height + findBarHeight)
            #expect(fixture.controller.sizeController.findBarHeight == findBarHeight)
            #expect(fixture.controller.heldPanelSize == nil)
        }
    }

    @Test("AC-35: 開く動きの途中で検索バーを出し、すぐパネルを閉じても、閉じる途中・隠れた後の窓の枠は変わらない")
    func barOpenedDuringOpeningThenClosedKeepsFrame() throws {
        try withFixture(animated: true) { fixture in
            let restFrame = try #require(fixture.animator.calls.first?.frame)
            #expect(fixture.controller.handleKey(commandF))

            fixture.controller.close()

            #expect(fixture.panel.frame == restFrame)
            #expect(fixture.controller.sizeController.findBarHeight == 0)

            fixture.animator.finish(1)

            #expect(!fixture.panel.isVisible)
            #expect(fixture.panel.frame == restFrame)
            #expect(fixture.controller.sizeController.findBarHeight == 0)
            #expect(fixture.findModel.isBarVisible)
        }
    }

    @Test("AC-35: 開く動きの途中で検索バーを出して閉じたとき、動きが終わっても窓の高さは変わらない")
    func barToggledDuringOpeningMotionLeavesHeight() throws {
        try withFixture(animated: true) { fixture in
            let restFrame = try #require(fixture.animator.calls.first?.frame)
            #expect(fixture.controller.handleKey(commandF))
            #expect(fixture.controller.handleKey(escape))

            fixture.animator.finish(0)

            #expect(fixture.panel.frame.height == restFrame.height)
            #expect(fixture.controller.sizeController.findBarHeight == 0)
        }
    }

    @Test("AC-35: サイドバーの開閉の動きの途中で検索バーを出すと、動きを先に終えてから高さを変える")
    func barOpenedDuringSidebarSlideFinishesSlideFirst() throws {
        try withFixture(animated: true) { fixture in
            fixture.animator.finish(0)
            fixture.controller.setSidebarOpen(true)
            #expect(fixture.controller.sizeController.isSidebarSliding)
            let slideTarget = try #require(fixture.animator.calls.last?.frame)

            #expect(fixture.controller.handleKey(commandF))

            #expect(!fixture.controller.sizeController.isSidebarSliding)
            #expect(fixture.animator.jumps.last == slideTarget)
            #expect(fixture.panel.frame.width == slideTarget.width)
            #expect(fixture.panel.frame.height == slideTarget.height + findBarHeight)
            #expect(fixture.controller.heldPanelSize == nil)
        }
    }

    // MARK: - AC-34

    @Test("AC-34: 新しいパネルでは、検索バーは閉じていて、検索語・置換語は空、オプションはすべてオフ")
    func freshPanelStartsClean() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        let controller = PanelControllerFactory.make(settings: settings)

        #expect(!controller.findModel.isBarVisible)
        #expect(!controller.findModel.isReplaceShown)
        #expect(controller.findModel.query.isEmpty)
        #expect(controller.findModel.replacement.isEmpty)
        #expect(controller.findModel.options == FindOptions())
        for option in FindOption.allCases {
            #expect(!controller.findModel.options.isOn(option))
        }
    }
}
