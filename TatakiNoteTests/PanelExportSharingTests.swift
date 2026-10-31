import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelExportSharingTests {
    private struct WriteFailure: LocalizedError {
        var errorDescription: String? { "書き込めません" }
    }

    @MainActor
    private final class Fixture {
        enum Event: Equatable {
            case emptyInput
            case toast(String, PanelToastStyle)
            case returnInput
        }

        struct FailureRequest {
            let message: String
            let window: NSWindow?
            let completion: () -> Void
        }

        let temp: TemporaryDefaults
        let directory: URL
        let model = PanelModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        let chooser = ExportChooserSpy()
        let sharer = SharerSpy()
        let exportSharing: PanelExportSharing
        private(set) var events: [Event] = []
        private let failureBox = FailureBox()

        init(isPresented: Bool = true, write: @escaping (String, URL) throws -> Void = TextFileWriter.write) throws {
            temp = try TemporaryDefaults()
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let exporter = TextExporter(
                settings: temp.makeSettings(),
                chooser: chooser,
                write: write,
                documentsDirectory: directory
            )
            let box = failureBox
            exportSharing = PanelExportSharing(
                model: model,
                panel: window,
                exporter: exporter,
                sharer: sharer,
                presentFailure: { message, window, completion in
                    box.requests.append(FailureRequest(message: message, window: window, completion: completion))
                }
            )
            if isPresented {
                model.present(target: nil)
            }
            exportSharing.onEmptyInput = { [weak self] in self?.events.append(.emptyInput) }
            exportSharing.onToast = { [weak self] message, style in self?.events.append(.toast(message, style)) }
            exportSharing.onReturnInput = { [weak self] in self?.events.append(.returnInput) }
        }

        var failureRequests: [FailureRequest] { failureBox.requests }

        func cleanup() {
            temp.remove()
            try? FileManager.default.removeItem(at: directory)
        }

        var destination: URL { directory.appendingPathComponent("out.txt") }
    }

    @MainActor
    private final class FailureBox {
        var requests: [Fixture.FailureRequest] = []
    }

    // MARK: - 共有

    @Test("AC-7: 空・空白と改行だけの文章の共有は、共有せずに空の知らせ・「共有する文章がありません」のトースト・入力欄へのフォーカスの順で知らせる", arguments: ["", " \n\t ", "\u{3000}"])
    func shareEmptyTextSignalsInsteadOfSharing(text: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.text = text
        let focusBefore = fixture.model.focusRequest

        fixture.exportSharing.shareCurrentText()

        #expect(fixture.sharer.calls.isEmpty)
        #expect(fixture.events == [.emptyInput, .toast(SaveAnimationModel.nothingToShareMessage, .notice)])
        #expect(fixture.model.focusRequest > focusBefore)
        #expect(fixture.model.text == text)
    }

    @Test("AC-7: 文章があれば、パネルの文章をタイトルバーの共有ボタンを起点に共有し、知らせは出さない")
    func shareCurrentTextSharesFromTitleBarButton() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.text = "  あいう\nabc  "

        fixture.exportSharing.shareCurrentText()

        #expect(fixture.sharer.calls.count == 1)
        #expect(fixture.sharer.calls.first?.text == "  あいう\nabc  ")
        #expect(fixture.sharer.calls.first?.anchor == .titleBarButton)
        #expect(fixture.events.isEmpty)
    }

    @Test("AC-7: 渡した文章は、渡した起点で共有する")
    func shareGivenTextUsesGivenAnchor() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        fixture.exportSharing.share("一覧の文章", from: .pointer)

        #expect(fixture.sharer.calls.count == 1)
        #expect(fixture.sharer.calls.first?.text == "一覧の文章")
        #expect(fixture.sharer.calls.first?.anchor == .pointer)
    }

    // MARK: - 書き出し

    @Test("AC-7: 空の文章の書き出しは、保存ダイアログを出さずに空の知らせと「書き出す文章がありません」のトーストを出す")
    func exportEmptyTextSignalsEmpty() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.text = " \n "

        fixture.exportSharing.exportCurrentText()

        #expect(fixture.chooser.requestCount == 0)
        #expect(fixture.events == [.emptyInput, .toast(SaveAnimationModel.nothingToExportMessage, .notice)])
    }

    @Test("AC-7: 書き出しに成功すると、「書き出しました」のトーストを出して入力をパネルへ戻す")
    func exportSuccessShowsToastAndReturnsInput() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"

        fixture.exportSharing.exportCurrentText()
        fixture.chooser.complete(with: fixture.destination)

        #expect(fixture.events == [.toast(SaveAnimationModel.exportedMessage, .done), .returnInput])
        #expect(try String(contentsOf: fixture.destination, encoding: .utf8) == "abc")
    }

    @Test("AC-7: 渡した文章の書き出しは、パネルの文章ではなく渡した文章を書く")
    func exportGivenTextWritesGivenText() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.text = "パネルの文章"

        fixture.exportSharing.exportText("一覧の文章")
        fixture.chooser.complete(with: fixture.destination)

        #expect(try String(contentsOf: fixture.destination, encoding: .utf8) == "一覧の文章")
    }

    @Test("AC-7: 保存ダイアログをキャンセルすると、知らせは出さずに入力をパネルへ戻す")
    func exportCancelReturnsInputOnly() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"

        fixture.exportSharing.exportCurrentText()
        fixture.chooser.complete(with: nil)

        #expect(fixture.events == [.returnInput])
        #expect(fixture.failureRequests.isEmpty)
    }

    @Test("AC-7: 書き出しに失敗すると、パネルが開いていればパネルに付けて失敗の知らせを出し、それを閉じた後に入力をパネルへ戻す")
    func exportFailurePresentsAlertAttachedToPanelThenReturnsInput() throws {
        let fixture = try Fixture(write: { _, _ in throw WriteFailure() })
        defer { fixture.cleanup() }
        fixture.model.text = "abc"

        fixture.exportSharing.exportCurrentText()
        fixture.chooser.complete(with: fixture.destination)

        #expect(fixture.failureRequests.count == 1)
        #expect(fixture.failureRequests.first?.message == "書き込めません")
        #expect(fixture.failureRequests.first?.window === fixture.window)
        #expect(fixture.events.isEmpty)

        fixture.failureRequests.first?.completion()

        #expect(fixture.events == [.returnInput])
    }

    @Test("AC-7: パネルが閉じているときの書き出しの失敗は、パネルに付けずに失敗の知らせを出し、閉じた後も入力を戻さない")
    func exportFailureWhileHiddenIsNotAttachedAndDoesNotReturnInput() throws {
        let fixture = try Fixture(isPresented: false, write: { _, _ in throw WriteFailure() })
        defer { fixture.cleanup() }

        fixture.exportSharing.exportText("abc")
        fixture.chooser.complete(with: fixture.destination)

        #expect(fixture.failureRequests.count == 1)
        #expect(fixture.failureRequests.first?.window == nil)

        fixture.failureRequests.first?.completion()

        #expect(fixture.events.isEmpty)
    }
}
