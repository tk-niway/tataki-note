import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class FailureRecorder {
    private(set) var messages: [String] = []
    private(set) var windows: [NSWindow?] = []
    private var completions: [() -> Void] = []

    func present(message: String, window: NSWindow?, completion: @escaping () -> Void) {
        messages.append(message)
        windows.append(window)
        completions.append(completion)
    }

    func dismissLast() {
        guard let completion = completions.popLast() else { return }
        completion()
    }
}

@MainActor
private final class ExportFixture {
    private static let ownPid: pid_t = 4242
    private static let externalPid: pid_t = 777

    let temp: TemporaryDefaults
    let settings: AppSettings
    let root: URL
    let chooser = ExportChooserSpy()
    let failures = FailureRecorder()
    let shaker = PanelShakerSpy()
    let beepSpy = BeepSpy()
    let library = DraftLibrary(store: .inMemory)
    let animator = FakePanelFrameAnimator()
    let sleeper = HeldSleeper()
    let saveAnimation: SaveAnimationModel
    let controller: PanelController

    var model: PanelModel { controller.model }
    var session: DraftSession { controller.session }

    init(isAnimationEnabled: Bool = false) throws {
        temp = try TemporaryDefaults()
        settings = temp.makeSettings()
        settings.panelScreen = .main
        settings.animationMode = isAnimationEnabled ? .on : .off
        settings.isSidebarOpen = false
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sleeper = sleeper
        saveAnimation = SaveAnimationModel(sleep: { await sleeper.sleep($0) }, announce: { _ in })
        let probe = FocusedElementProbeStub()
        let failures = failures
        controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: InserterStub(result: .inserted),
            permission: PermissionStub(isTrusted: true),
            fieldProbe: probe,
            exposeWebContent: { _ in },
            ownProcessIdentifier: Self.ownPid,
            library: library,
            saveAnimation: saveAnimation,
            animator: animator,
            shaker: shaker,
            beep: beepSpy.beep,
            makeTargetMonitor: InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: Self.ownPid),
            exportChooser: chooser,
            presentExportFailure: { message, window, completion in
                failures.present(message: message, window: window, completion: completion)
            }
        )
        controller.targetOverride = {
            InsertionTarget(processIdentifier: Self.externalPid, bundleIdentifier: "com.example.Editor", localizedName: "Editor")
        }
        controller.open()
        for index in animator.calls.indices {
            animator.finish(index)
        }
    }

    func cleanup() {
        sleeper.releaseAll()
        controller.panel.orderOut(nil)
        temp.remove()
        try? FileManager.default.removeItem(at: root)
    }

    func pressExport(hasMarkedText: Bool = false) -> Bool {
        controller.handleKey(PanelKeyInput(
            keyCode: 1,
            modifiers: [.command, .shift],
            hasMarkedText: hasMarkedText,
            characters: "s"
        ))
    }

    func waitForToast() async throws {
        try await waitUntil(attempts: 100, interval: .milliseconds(20)) { saveAnimation.toastMessage != nil }
    }

    func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    struct Snapshot: Equatable {
        var text: String
        var document: PanelDocument
        var mode: DraftMode
        var targetProcess: pid_t?
        var historyCount: Int
        var isPresented: Bool
    }

    var snapshot: Snapshot {
        Snapshot(
            text: model.text,
            document: session.document,
            mode: session.mode,
            targetProcess: model.target?.processIdentifier,
            historyCount: library.history.count,
            isPresented: model.isPresented
        )
    }
}

@MainActor
struct PanelExportWiringTests {
    private static func shortcutEvent(modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "s",
                charactersIgnoringModifiers: "s",
                isARepeat: false,
                keyCode: 1
            )
        )
    }

    // MARK: - キー

    @Test("AC-1: ⇧⌘S で保存ダイアログを名前「untitled」で開くよう頼む。インサート・ノートのどちらでも")
    func shiftCommandSOpensSavePanelInBothModes() throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"

        #expect(fixture.pressExport())
        #expect(fixture.chooser.requests.count == 1)
        #expect(fixture.chooser.requests.first?.initialName == "untitled")
        fixture.chooser.complete(with: nil)

        fixture.session.toggleMode()
        #expect(fixture.pressExport())
        #expect(fixture.chooser.requests.count == 2)
    }

    @Test("AC-1: 一覧・検索欄の経路(PromptPanel の onKeyEquivalent)の ⇧⌘S でも保存ダイアログを開くよう頼み、⇧⌘K では開かない")
    func shiftCommandSThroughPanelKeyEquivalent() throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"
        let onKeyEquivalent = try #require(fixture.controller.panel.onKeyEquivalent)

        let exportEvent = try Self.shortcutEvent(modifiers: [.command, .shift])
        let input = try #require(PromptPanel.panelCommandInput(for: exportEvent, hasMarkedText: false))
        #expect(onKeyEquivalent(input))
        #expect(fixture.chooser.requests.count == 1)

        let optionEvent = try Self.shortcutEvent(modifiers: [.command, .option])
        #expect(PromptPanel.panelCommandInput(for: optionEvent, hasMarkedText: false) == nil)
        #expect(fixture.chooser.requests.count == 1)
    }

    @Test("AC-2: 変換中の ⇧⌘S は入力メソッドに渡し、保存ダイアログを開かない")
    func shiftCommandSWhileComposingDoesNothing() throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"

        #expect(!fixture.pressExport(hasMarkedText: true))
        #expect(fixture.chooser.requests.isEmpty)

        let onKeyEquivalent = try #require(fixture.controller.panel.onKeyEquivalent)
        let event = try Self.shortcutEvent(modifiers: [.command, .shift])
        let input = try #require(PromptPanel.panelCommandInput(for: event, hasMarkedText: true))
        #expect(!onKeyEquivalent(input))
        #expect(fixture.chooser.requests.isEmpty)
    }

    // MARK: - 結果の知らせ

    @Test("AC-7: 書き出せたら「書き出しました」のトーストが出て、ファイルに文章が書かれる")
    func exportedShowsToast() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "あいう\nabc"
        let destination = fixture.root.appendingPathComponent("memo.txt")

        #expect(fixture.pressExport())
        fixture.chooser.complete(with: destination)
        try await fixture.waitForToast()

        #expect(fixture.saveAnimation.toastMessage == SaveAnimationModel.exportedMessage)
        #expect(fixture.saveAnimation.toastStyle == .done)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "あいう\nabc")
    }

    @Test("AC-7: 結果が来たときにパネルが閉じていれば、トーストを出さない")
    func exportedWhileClosedShowsNoToast() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"
        let destination = fixture.root.appendingPathComponent("memo.txt")

        #expect(fixture.pressExport())
        fixture.controller.close()
        fixture.chooser.complete(with: destination)
        try await fixture.settle()

        #expect(fixture.saveAnimation.toastMessage == nil)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("AC-8: 書けなかったら、理由の文を添えた失敗の知らせをパネルに付けて出し、成功のトーストは出さず、文章は残る")
    func failedShowsAlertAttachedToPanel() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"
        let missing = fixture.root.appendingPathComponent("missing", isDirectory: true).appendingPathComponent("untitled.txt")

        #expect(fixture.pressExport())
        fixture.chooser.complete(with: missing)
        try await fixture.settle()

        #expect(fixture.failures.messages.count == 1)
        #expect(fixture.failures.messages.first?.isEmpty == false)
        #expect(fixture.failures.windows.first.flatMap { $0 } === fixture.controller.panel)
        #expect(fixture.saveAnimation.toastMessage == nil)
        #expect(fixture.model.text == "abc")
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test("AC-8: 結果が来たときにパネルが閉じていても、失敗の知らせを窓に付けずに出す")
    func failedWhileClosedShowsStandaloneAlert() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"
        let missing = fixture.root.appendingPathComponent("missing", isDirectory: true).appendingPathComponent("untitled.txt")

        #expect(fixture.pressExport())
        fixture.controller.close()
        fixture.chooser.complete(with: missing)
        try await fixture.settle()

        #expect(fixture.failures.messages.count == 1)
        #expect(fixture.failures.messages.first?.isEmpty == false)
        #expect(fixture.failures.windows.count == 1)
        #expect(fixture.failures.windows.first.flatMap { $0 } == nil)
        #expect(fixture.saveAnimation.toastMessage == nil)
        #expect(!fixture.model.isPresented)
    }

    @Test("AC-10: 書き出せた後は、パネルは開いたまま、文章・下書き・モード・挿入先・履歴は変わらず、入力が本文に戻る")
    func stateIsKeptAfterExport() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"
        let before = fixture.snapshot
        let focusBefore = fixture.model.focusRequest

        #expect(fixture.pressExport())
        fixture.chooser.complete(with: fixture.root.appendingPathComponent("memo.txt"))
        try await fixture.waitForToast()

        #expect(fixture.snapshot == before)
        #expect(fixture.model.isPresented)
        #expect(fixture.model.focusRequest > focusBefore)
    }

    @Test("AC-10: キャンセルの後は、トーストも失敗の知らせも出ず、状態は変わらず、入力が本文に戻る")
    func stateIsKeptAfterCancel() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"
        let before = fixture.snapshot
        let focusBefore = fixture.model.focusRequest

        #expect(fixture.pressExport())
        fixture.chooser.complete(with: nil)
        try await fixture.settle()

        #expect(fixture.snapshot == before)
        #expect(fixture.saveAnimation.toastMessage == nil)
        #expect(fixture.failures.messages.isEmpty)
        #expect(fixture.model.focusRequest > focusBefore)
    }

    @Test("AC-10: 失敗の知らせを閉じた後は、状態は変わらず、入力が本文に戻る")
    func stateIsKeptAfterFailureAlert() async throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"
        let before = fixture.snapshot
        let missing = fixture.root.appendingPathComponent("missing", isDirectory: true).appendingPathComponent("untitled.txt")

        #expect(fixture.pressExport())
        fixture.chooser.complete(with: missing)
        try await fixture.settle()
        let focusBeforeDismiss = fixture.model.focusRequest
        fixture.failures.dismissLast()

        #expect(fixture.snapshot == before)
        #expect(fixture.model.focusRequest > focusBeforeDismiss)
    }

    // MARK: - 空の文章

    @Test("AC-12: 空・空白と改行だけの文章の ⇧⌘S は、保存ダイアログを出さず、アニメーションがオフなら警告音と「書き出す文章がありません」のトースト", arguments: ["", " \n\t ", "\u{3000}"])
    func emptyTextBeepsWhenAnimationIsOff(text: String) async throws {
        let fixture = try ExportFixture(isAnimationEnabled: false)
        defer { fixture.cleanup() }
        fixture.model.text = text

        #expect(fixture.pressExport())
        try await fixture.waitForToast()

        #expect(fixture.chooser.requests.isEmpty)
        #expect(fixture.beepSpy.count == 1)
        #expect(fixture.shaker.shakeCount == 0)
        #expect(fixture.saveAnimation.toastMessage == SaveAnimationModel.nothingToExportMessage)
        #expect(fixture.saveAnimation.toastStyle == .notice)
        #expect(fixture.model.text == text)
    }

    @Test("AC-12: 空の文章の ⇧⌘S は、アニメーションがオンならパネルが揺れて警告音は鳴らない")
    func emptyTextShakesWhenAnimationIsOn() async throws {
        let fixture = try ExportFixture(isAnimationEnabled: true)
        defer { fixture.cleanup() }
        fixture.model.text = ""

        #expect(fixture.pressExport())
        try await fixture.waitForToast()

        #expect(fixture.chooser.requests.isEmpty)
        #expect(fixture.shaker.shakeCount == 1)
        #expect(fixture.beepSpy.count == 0)
        #expect(fixture.saveAnimation.toastMessage == SaveAnimationModel.nothingToExportMessage)
    }

    @Test("AC-12: 前後に空白のある文章は空ではないので、保存ダイアログを開く")
    func paddedTextOpensSavePanel() throws {
        let fixture = try ExportFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "  a  "

        #expect(fixture.pressExport())
        #expect(fixture.chooser.requests.count == 1)
        #expect(fixture.beepSpy.count == 0)
    }
}
