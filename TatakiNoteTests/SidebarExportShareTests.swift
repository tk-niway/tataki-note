import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class RowChooserSpy: ExportDestinationChoosing {
    private(set) var requests: [(initialName: String, directory: URL)] = []
    private(set) var bringToFrontCount = 0
    private var completions: [(URL?) -> Void] = []

    func chooseDestination(initialName: String, directory: URL, completion: @escaping (URL?) -> Void) {
        requests.append((initialName, directory))
        completions.append(completion)
    }

    func bringToFront() {
        bringToFrontCount += 1
    }

    func complete(with url: URL?) {
        guard !completions.isEmpty else { return }
        completions.removeFirst()(url)
    }
}

@MainActor
private final class RowSharerSpy: TextSharing {
    private(set) var calls: [(text: String, anchor: SharingAnchor)] = []

    func share(_ text: String, from anchor: SharingAnchor) {
        calls.append((text, anchor))
    }
}

@MainActor
private final class RowHeldSleeper {
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { waiting.append($0) }
    }

    func releaseAll() {
        let continuations = waiting
        waiting = []
        for continuation in continuations {
            continuation.resume()
        }
    }
}

@MainActor
private final class RowFixture {
    private static let ownPid: pid_t = 4242
    private static let externalPid: pid_t = 777

    let temp: TemporaryDefaults
    let settings: AppSettings
    let root: URL
    let chooser = RowChooserSpy()
    let sharer = RowSharerSpy()
    let library = DraftLibrary(store: .inMemory)
    let animator = FakePanelFrameAnimator()
    let sleeper = RowHeldSleeper()
    let saveAnimation: SaveAnimationModel
    let controller: PanelController

    var model: PanelModel { controller.model }
    var session: DraftSession { controller.session }
    var sidebar: SidebarModel { controller.sidebarModel }

    init() throws {
        temp = try TemporaryDefaults()
        settings = temp.makeSettings()
        settings.panelScreen = .main
        settings.animationMode = .off
        settings.isSidebarOpen = true
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sleeper = sleeper
        saveAnimation = SaveAnimationModel(sleep: { await sleeper.sleep($0) }, announce: { _ in })
        let probe = FocusedElementProbeStub()
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
            makeTargetMonitor: InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: Self.ownPid),
            exportChooser: chooser,
            sharer: sharer
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

    @discardableResult
    func addDraft(_ text: String) throws -> UUID {
        try #require(library.addDraft(text: text)).id
    }

    @discardableResult
    func addHistory(_ text: String) -> UUID {
        library.recordInsertion(text: text, appName: "Safari", bundleIdentifier: nil)
        return library.history[0].id
    }

    func waitForToast() async throws {
        try await waitUntil(attempts: 100, interval: .milliseconds(20)) { saveAnimation.toastMessage != nil }
    }

    struct Snapshot: Equatable {
        var text: String
        var document: PanelDocument
        var mode: DraftMode
        var selection: UUID?
        var draftCount: Int
        var historyCount: Int
        var isPresented: Bool
    }

    var snapshot: Snapshot {
        Snapshot(
            text: model.text,
            document: session.document,
            mode: session.mode,
            selection: sidebar.selection,
            draftCount: library.drafts.count,
            historyCount: library.history.count,
            isPresented: model.isPresented
        )
    }
}

@MainActor
struct SidebarExportShareTests {
    @Test("AC-19: 下書きの行の「ファイルに書き出す」は、行の文章で保存ダイアログを名前「untitled」で開くよう頼む。パネルの文章・開いている下書き・選択は変わらない")
    func exportingDraftRowOpensSavePanelWithRowText() async throws {
        let fixture = try RowFixture()
        defer { fixture.cleanup() }
        let rowID = try fixture.addDraft("行の文章\n二行目")
        fixture.model.text = "パネルの文章"
        let before = fixture.snapshot

        fixture.sidebar.requestExport(rowID)

        #expect(fixture.chooser.requests.count == 1)
        #expect(fixture.chooser.requests.first?.initialName == "untitled")
        #expect(fixture.snapshot == before)

        let destination = fixture.root.appendingPathComponent("row.txt")
        fixture.chooser.complete(with: destination)
        try await fixture.waitForToast()

        #expect(try String(contentsOf: destination, encoding: .utf8) == "行の文章\n二行目")
        #expect(fixture.saveAnimation.toastMessage == SaveAnimationModel.exportedMessage)
        #expect(fixture.snapshot == before)
    }

    @Test("AC-19: 履歴の行の「ファイルに書き出す」も、行の文章で保存ダイアログを開くよう頼み、パネルの状態を変えない")
    func exportingHistoryRowOpensSavePanelWithRowText() async throws {
        let fixture = try RowFixture()
        defer { fixture.cleanup() }
        let rowID = fixture.addHistory("履歴の文章")
        fixture.model.text = "パネルの文章"
        let before = fixture.snapshot

        fixture.sidebar.requestExport(rowID)
        #expect(fixture.chooser.requests.count == 1)

        let destination = fixture.root.appendingPathComponent("history.txt")
        fixture.chooser.complete(with: destination)
        try await fixture.waitForToast()

        #expect(try String(contentsOf: destination, encoding: .utf8) == "履歴の文章")
        #expect(fixture.snapshot == before)
    }

    @Test("AC-19: 行から書き出しを頼んでも、パネルに出している下書きと一覧の選択は変わらない")
    func exportingRowKeepsOpenDraftAndSelection() throws {
        let fixture = try RowFixture()
        defer { fixture.cleanup() }
        let shownID = try fixture.addDraft("開いている下書き")
        let otherID = try fixture.addDraft("別の下書き")
        fixture.session.request(.draft(shownID))
        let documentBefore = fixture.session.document
        let selectionBefore = fixture.sidebar.selection
        let textBefore = fixture.model.text

        fixture.sidebar.requestExport(otherID)

        #expect(fixture.chooser.requests.count == 1)
        #expect(fixture.session.document == documentBefore)
        #expect(fixture.session.document == .savedDraft(shownID))
        #expect(fixture.sidebar.selection == selectionBefore)
        #expect(fixture.sidebar.selection == shownID)
        #expect(fixture.model.text == textBefore)
    }

    @Test("AC-20: 行の「共有」は、行の文章でシェアのメニューをマウスの位置に出すよう頼む。パネルの文章・開いている下書き・選択は変わらない")
    func sharingRowSharesRowTextAtPointer() throws {
        let fixture = try RowFixture()
        defer { fixture.cleanup() }
        let draftID = try fixture.addDraft("下書きの文章")
        let historyID = fixture.addHistory("履歴の文章")
        fixture.model.text = "パネルの文章"
        let before = fixture.snapshot

        fixture.sidebar.requestShare(draftID)
        fixture.sidebar.requestShare(historyID)

        #expect(fixture.sharer.calls.count == 2)
        #expect(fixture.sharer.calls[0].text == "下書きの文章")
        #expect(fixture.sharer.calls[0].anchor == .pointer)
        #expect(fixture.sharer.calls[1].text == "履歴の文章")
        #expect(fixture.sharer.calls[1].anchor == .pointer)
        #expect(fixture.snapshot == before)
        #expect(fixture.chooser.requests.isEmpty)
    }

    @Test("AC-21: 文章が空白だけの下書きの行は、書き出し・共有が選べず、頼まれても何もしない")
    func blankDraftRowCannotBeExportedOrShared() throws {
        let fixture = try RowFixture()
        defer { fixture.cleanup() }
        let blankID = try fixture.addDraft(" \n\t ")
        let before = fixture.snapshot

        #expect(!fixture.sidebar.canExport(blankID))
        fixture.sidebar.requestExport(blankID)
        fixture.sidebar.requestShare(blankID)

        #expect(fixture.chooser.requests.isEmpty)
        #expect(fixture.sharer.calls.isEmpty)
        #expect(fixture.snapshot == before)
    }

    @Test("AC-21: 文章のある行は書き出し・共有を選べる。前後に空白があっても選べる")
    func rowsWithTextCanBeExportedAndShared() throws {
        let fixture = try RowFixture()
        defer { fixture.cleanup() }
        let draftID = try fixture.addDraft("abc")
        let paddedID = try fixture.addDraft("  a  ")
        let historyID = fixture.addHistory("履歴")

        #expect(fixture.sidebar.canExport(draftID))
        #expect(fixture.sidebar.canExport(paddedID))
        #expect(fixture.sidebar.canExport(historyID))
        #expect(!fixture.sidebar.canExport(UUID()))
    }

    @Test("AC-21: 行が無い id で頼まれても何もしない")
    func unknownRowDoesNothing() throws {
        let fixture = try RowFixture()
        defer { fixture.cleanup() }

        fixture.sidebar.requestExport(UUID())
        fixture.sidebar.requestShare(UUID())

        #expect(fixture.chooser.requests.isEmpty)
        #expect(fixture.sharer.calls.isEmpty)
    }

    @Test("AC-11: パネルの ⇧⌘S で保存ダイアログが開いている間に行から書き出しを頼んでも、ダイアログは増えず、開いているものを前に出す")
    func rowExportWhileSavePanelIsOpenBringsItToFront() throws {
        let fixture = try RowFixture()
        defer { fixture.cleanup() }
        let rowID = try fixture.addDraft("行の文章")
        fixture.model.text = "パネルの文章"

        #expect(fixture.controller.handleKey(PanelKeyInput(
            keyCode: 1,
            modifiers: [.command, .shift],
            hasMarkedText: false,
            characters: "s"
        )))
        #expect(fixture.chooser.requests.count == 1)
        #expect(fixture.chooser.bringToFrontCount == 0)

        fixture.sidebar.requestExport(rowID)

        #expect(fixture.chooser.requests.count == 1)
        #expect(fixture.chooser.bringToFrontCount == 1)
    }
}
