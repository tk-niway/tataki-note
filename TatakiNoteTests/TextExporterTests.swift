import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class FakeDestinationChooser: ExportDestinationChoosing {
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
private final class OutcomeLog {
    var outcomes: [TextExportOutcome] = []
}

@MainActor
private struct ExporterFixture {
    let temp: TemporaryDefaults
    let settings: AppSettings
    let chooser = FakeDestinationChooser()
    let log = OutcomeLog()
    let root: URL
    let documents: URL
    let exporter: TextExporter
    private let writeCount: WriteCounter

    @MainActor
    final class WriteCounter {
        var count = 0
    }

    init() throws {
        temp = try TemporaryDefaults()
        settings = temp.makeSettings()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        documents = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let counter = WriteCounter()
        writeCount = counter
        exporter = TextExporter(
            settings: settings,
            chooser: chooser,
            write: { text, url in
                counter.count += 1
                try TextFileWriter.write(text, to: url)
            },
            documentsDirectory: documents
        )
    }

    var writes: Int { writeCount.count }

    func export(_ text: String) {
        let log = log
        exporter.export(text) { log.outcomes.append($0) }
    }

    func makeDirectory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func cleanup() {
        temp.remove()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
struct TextExporterTests {
    // MARK: - 最初のフォルダ

    @Test("AC-3: 保存ダイアログは名前「untitled」と「書類」で開く(前回のフォルダが無いとき)")
    func opensWithUntitledInDocuments() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }

        fixture.export("memo")

        #expect(fixture.chooser.requests.count == 1)
        #expect(fixture.chooser.requests.first?.initialName == "untitled")
        #expect(fixture.chooser.requests.first?.directory == fixture.documents)
    }

    @Test("AC-3: 覚えているフォルダが今もあれば、そこで開く")
    func opensInRememberedDirectory() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }
        let remembered = try fixture.makeDirectory("last")
        fixture.settings.lastExportDirectoryPath = remembered.path

        fixture.export("memo")

        #expect(fixture.chooser.requests.first?.directory.path == remembered.path)
    }

    @Test("AC-3: 覚えているフォルダが消えている・ファイルになっているときは、「書類」で開く")
    func fallsBackToDocumentsWhenRememberedIsGone() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }
        let removed = try fixture.makeDirectory("removed")
        try FileManager.default.removeItem(at: removed)
        fixture.settings.lastExportDirectoryPath = removed.path

        #expect(fixture.exporter.initialDirectory == fixture.documents)

        let file = fixture.root.appendingPathComponent("plain.txt")
        try Data("x".utf8).write(to: file)
        fixture.settings.lastExportDirectoryPath = file.path

        #expect(fixture.exporter.initialDirectory == fixture.documents)

        fixture.export("memo")
        #expect(fixture.chooser.requests.first?.directory == fixture.documents)
    }

    // MARK: - 拡張子

    @Test("AC-4: 拡張子が無ければ .txt を付け、あればそのまま、末尾の「.」は取って .txt を付ける")
    func resolvedURLAddsTextExtension() {
        let base = URL(fileURLWithPath: "/tmp/export-test", isDirectory: true)
        func resolved(_ name: String) -> String {
            ExportFileName.resolvedURL(for: base.appendingPathComponent(name)).lastPathComponent
        }

        #expect(resolved("untitled") == "untitled.txt")
        #expect(resolved("memo.md") == "memo.md")
        #expect(resolved("a.b.c") == "a.b.c")
        #expect(resolved("name.") == "name.txt")
        #expect(resolved(".hidden") == ".hidden.txt")
        #expect(resolved("メモ") == "メモ.txt")
        #expect(ExportFileName.resolvedURL(for: base.appendingPathComponent("untitled")).deletingLastPathComponent().path == base.path)
    }

    @Test("AC-4: 拡張子の無い場所が選ばれたら .txt を付けたファイルに書く")
    func writesWithTextExtensionWhenMissing() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }

        fixture.export("memo")
        fixture.chooser.complete(with: fixture.documents.appendingPathComponent("untitled"))

        let expected = fixture.documents.appendingPathComponent("untitled.txt")
        #expect(fixture.log.outcomes == [.exported(expected)])
        #expect(FileManager.default.fileExists(atPath: expected.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.documents.appendingPathComponent("untitled").path))
    }

    @Test("AC-4: 拡張子がある名前はその名前のままのファイルに書く")
    func writesWithChosenExtension() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }

        fixture.export("memo")
        fixture.chooser.complete(with: fixture.documents.appendingPathComponent("memo.md"))

        let expected = fixture.documents.appendingPathComponent("memo.md")
        #expect(fixture.log.outcomes == [.exported(expected)])
        #expect(FileManager.default.fileExists(atPath: expected.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.documents.appendingPathComponent("memo.md.txt").path))
    }

    // MARK: - 中身

    @Test("AC-5: 書いたファイルの中身は文章そのまま(日本語・絵文字・改行・前後の空白、BOM なしの UTF-8)")
    func writtenBytesMatchText() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }
        let text = "  こんにちは 😀\n2行目\r\n\n末尾の空白  \n"

        fixture.export(text)
        let target = fixture.documents.appendingPathComponent("body.txt")
        fixture.chooser.complete(with: target)

        let data = try Data(contentsOf: target)
        #expect(data == Data(text.utf8))
        #expect(!data.starts(with: [0xEF, 0xBB, 0xBF]))
    }

    // MARK: - 前回のフォルダ

    @Test("AC-6: 書き出せたらフォルダを覚え、同じ保存先から設定を作り直しても最初のフォルダになる")
    func rememberedDirectorySurvivesRecreation() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }
        let destination = try fixture.makeDirectory("dest")

        fixture.export("memo")
        fixture.chooser.complete(with: destination.appendingPathComponent("a.txt"))

        #expect(fixture.settings.lastExportDirectoryPath == destination.path)
        let recreated = fixture.temp.makeSettings()
        #expect(recreated.lastExportDirectoryPath == destination.path)
        let next = FakeDestinationChooser()
        let exporter = TextExporter(settings: recreated, chooser: next, documentsDirectory: fixture.documents)
        exporter.export("memo") { _ in }
        #expect(next.requests.first?.directory.path == destination.path)
    }

    @Test("AC-6: 書けなかったときは覚えているフォルダを変えない")
    func failedWriteKeepsRememberedDirectory() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }
        let remembered = try fixture.makeDirectory("last")
        fixture.settings.lastExportDirectoryPath = remembered.path

        fixture.export("memo")
        fixture.chooser.complete(with: fixture.root.appendingPathComponent("missing/untitled.txt"))

        guard case .failed(let reason) = fixture.log.outcomes.first else {
            Issue.record("失敗が返っていない: \(fixture.log.outcomes)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(fixture.settings.lastExportDirectoryPath == remembered.path)
        #expect(fixture.temp.makeSettings().lastExportDirectoryPath == remembered.path)
        #expect(!fixture.exporter.isChoosing)
    }

    @Test("AC-6: 覚えている値が文字列でない・空文字のときは「書類」で開く")
    func brokenRememberedValueFallsBackToDocuments() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }
        let store = SettingsStore(defaults: fixture.temp.defaults)

        fixture.temp.defaults.set(42, forKey: SettingsStore.Key.lastExportDirectory)
        #expect(store.loadLastExportDirectoryPath() == nil)
        let numeric = TextExporter(settings: fixture.temp.makeSettings(), chooser: fixture.chooser, documentsDirectory: fixture.documents)
        #expect(numeric.initialDirectory == fixture.documents)

        fixture.temp.defaults.set("", forKey: SettingsStore.Key.lastExportDirectory)
        #expect(store.loadLastExportDirectoryPath() == nil)
        let empty = TextExporter(settings: fixture.temp.makeSettings(), chooser: fixture.chooser, documentsDirectory: fixture.documents)
        #expect(empty.initialDirectory == fixture.documents)
    }

    // MARK: - キャンセル

    @Test("AC-9: キャンセルしたらファイルを書かず、覚えているフォルダも変えない")
    func cancelWritesNothing() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }
        let remembered = try fixture.makeDirectory("last")
        fixture.settings.lastExportDirectoryPath = remembered.path

        fixture.export("memo")
        fixture.chooser.complete(with: nil)

        #expect(fixture.log.outcomes == [.cancelled])
        #expect(fixture.writes == 0)
        #expect(fixture.settings.lastExportDirectoryPath == remembered.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.documents.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: remembered.path).isEmpty)
    }

    // MARK: - 二重の依頼

    @Test("AC-11: ダイアログが開いている間の2回目の依頼は、ダイアログを前に出すだけで、閉じた後はまた開ける")
    func secondRequestBringsDialogToFront() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }

        fixture.export("first")
        #expect(fixture.exporter.isChoosing)
        fixture.export("second")

        #expect(fixture.chooser.requests.count == 1)
        #expect(fixture.chooser.bringToFrontCount == 1)
        #expect(fixture.log.outcomes == [.alreadyChoosing])

        fixture.chooser.complete(with: nil)
        #expect(!fixture.exporter.isChoosing)
        fixture.export("third")

        #expect(fixture.chooser.requests.count == 2)
        #expect(fixture.chooser.bringToFrontCount == 1)
    }

    @Test("AC-11: ダイアログが開いている間に空の文章で頼むと、前に出さずに空の結果になる")
    func emptyRequestWhileChoosingDoesNotBringToFront() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }

        fixture.export("first")
        fixture.export(" \n\t")

        #expect(fixture.log.outcomes == [.empty])
        #expect(fixture.chooser.bringToFrontCount == 0)
        #expect(fixture.chooser.requests.count == 1)
        #expect(fixture.exporter.isChoosing)
    }

    @Test("ダイアログが開いている間に2回目の依頼が来ても、先の文章がそのまま書かれる")
    func firstTextIsWrittenAfterSecondRequest() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }

        fixture.export("first")
        fixture.export("second")
        let target = fixture.documents.appendingPathComponent("out.txt")
        fixture.chooser.complete(with: target)

        #expect(try String(contentsOf: target, encoding: .utf8) == "first")
        #expect(fixture.writes == 1)
    }

    // MARK: - 空の文章

    @Test("空・空白だけの文章はダイアログを開かず、空の結果になる")
    func emptyTextOpensNoDialog() throws {
        let fixture = try ExporterFixture()
        defer { fixture.cleanup() }

        for text in ["", " \n\t", "\u{3000}"] {
            fixture.export(text)
        }

        #expect(fixture.log.outcomes == [.empty, .empty, .empty])
        #expect(fixture.chooser.requests.isEmpty)
        #expect(!fixture.exporter.isChoosing)
        #expect(ExportableText.isEmpty(""))
        #expect(ExportableText.isEmpty(" \n\t"))
        #expect(ExportableText.isEmpty("\u{3000}"))
        #expect(!ExportableText.isEmpty(" a "))
    }

    // MARK: - 結果ごとの知らせ

    @Test("書き出しの結果ごとの知らせ(パネルが開いているとき)")
    func feedbackWhilePresented() {
        let url = URL(fileURLWithPath: "/tmp/a.txt")

        #expect(ExportFeedback.feedback(for: .empty, isPanelPresented: true) == ExportFeedback(
            signalsEmpty: true,
            toastMessage: "書き出す文章がありません",
            toastStyle: .notice
        ))
        #expect(ExportFeedback.feedback(for: .exported(url), isPanelPresented: true) == ExportFeedback(
            toastMessage: "書き出しました",
            toastStyle: .done,
            returnsInput: true
        ))
        #expect(ExportFeedback.feedback(for: .cancelled, isPanelPresented: true) == ExportFeedback(returnsInput: true))
        #expect(ExportFeedback.feedback(for: .failed("理由"), isPanelPresented: true) == ExportFeedback(
            failureMessage: "理由",
            returnsInput: true
        ))
        #expect(ExportFeedback.feedback(for: .alreadyChoosing, isPanelPresented: true) == ExportFeedback())
    }

    @Test("書き出しの結果ごとの知らせ(パネルが閉じているとき。失敗の知らせだけ出す)")
    func feedbackWhileClosed() {
        let url = URL(fileURLWithPath: "/tmp/a.txt")

        #expect(ExportFeedback.feedback(for: .empty, isPanelPresented: false) == ExportFeedback())
        #expect(ExportFeedback.feedback(for: .exported(url), isPanelPresented: false) == ExportFeedback())
        #expect(ExportFeedback.feedback(for: .cancelled, isPanelPresented: false) == ExportFeedback())
        #expect(ExportFeedback.feedback(for: .failed("理由"), isPanelPresented: false) == ExportFeedback(failureMessage: "理由"))
        #expect(ExportFeedback.feedback(for: .alreadyChoosing, isPanelPresented: false) == ExportFeedback())
    }

    // MARK: - 保存ダイアログの編集のキー

    @Test("AC-32: ⌘X・⌘C・⌘V・⌘A・⌘Z・⇧⌘Z は編集の操作になり、それ以外のキーはならない")
    func savePanelEditKeys() {
        #expect(SavePanelEditKey.action(modifiers: [.command], character: "x") == .cut)
        #expect(SavePanelEditKey.action(modifiers: [.command], character: "c") == .copy)
        #expect(SavePanelEditKey.action(modifiers: [.command], character: "v") == .paste)
        #expect(SavePanelEditKey.action(modifiers: [.command], character: "a") == .selectAll)
        #expect(SavePanelEditKey.action(modifiers: [.command], character: "z") == .undo)
        #expect(SavePanelEditKey.action(modifiers: [.command, .shift], character: "z") == .redo)
        #expect(SavePanelEditKey.action(modifiers: [.command, .capsLock], character: "v") == .paste)

        #expect(SavePanelEditKey.action(modifiers: [.command], character: "l") == nil)
        #expect(SavePanelEditKey.action(modifiers: [.command], character: "d") == nil)
        #expect(SavePanelEditKey.action(modifiers: [.command], character: "s") == nil)
        #expect(SavePanelEditKey.action(modifiers: [.command, .shift], character: "s") == nil)
        #expect(SavePanelEditKey.action(modifiers: [.command], character: "w") == nil)
        #expect(SavePanelEditKey.action(modifiers: [.command], character: "q") == nil)
        #expect(SavePanelEditKey.action(modifiers: [.command, .option], character: "v") == nil)
        #expect(SavePanelEditKey.action(modifiers: [], character: "v") == nil)
    }
}
