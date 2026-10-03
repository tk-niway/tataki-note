import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class ExposeRequestRecorder {
    var result: AXError = .success
    private(set) var targets: [InsertionTarget] = []

    func record(_ target: InsertionTarget) -> AXError {
        targets.append(target)
        return result
    }

    func count(of target: InsertionTarget) -> Int {
        targets.filter { $0 == target }.count
    }
}

@MainActor
struct WebContentExposerTests {
    private static let ownPid: pid_t = 4242
    private let editor = WatcherFixture.editor
    private let other = WatcherFixture.otherApp
    private let own = InsertionTarget(processIdentifier: WebContentExposerTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let testProcess = InsertionTarget(
        processIdentifier: ProcessInfo.processInfo.processIdentifier,
        bundleIdentifier: "com.example.TestHost",
        localizedName: "TestHost"
    )

    private func makeExposer(
        _ recorder: ExposeRequestRecorder,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> WebContentExposer {
        WebContentExposer(notificationCenter: notificationCenter, request: { recorder.record($0) })
    }

    private func postTermination(of app: NSRunningApplication, to center: NotificationCenter) {
        center.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: app]
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !condition() && ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    private func withController(
        isTrusted: Bool,
        target: InsertionTarget,
        exposeWebContent: @escaping (InsertionTarget) -> Void,
        _ body: (PanelController, AppSettings) async throws -> Void
    ) async throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = .main
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: InserterStub(result: .inserted),
            permission: PermissionStub(isTrusted: isTrusted),
            notifier: NotifierStub(),
            fieldProbe: FocusedElementProbeStub(),
            exposeWebContent: exposeWebContent,
            ownProcessIdentifier: Self.ownPid
        )
        controller.targetOverride = { target }
        defer { controller.close() }
        try await body(controller, settings)
    }

    // MARK: - AC-5

    @Test("AC-5: 同じアプリには1回だけ頼み、別のアプリにはそれぞれ1回頼む")
    func requestsOncePerApp() {
        let recorder = ExposeRequestRecorder()
        let exposer = makeExposer(recorder)

        exposer.expose(editor)
        exposer.expose(editor)
        exposer.expose(editor)
        #expect(recorder.targets == [editor])

        exposer.expose(other)
        exposer.expose(other)
        exposer.expose(editor)
        #expect(recorder.targets == [editor, other])
    }

    // MARK: - AC-6

    @Test("AC-6: 頼んだアプリが終了したら忘れ、同じプロセス番号をまた頼まれたらもう一度頼む")
    func forgetsTerminatedApp() async {
        let recorder = ExposeRequestRecorder()
        let center = NotificationCenter()
        let exposer = makeExposer(recorder, notificationCenter: center)

        exposer.expose(testProcess)
        exposer.expose(testProcess)
        #expect(recorder.count(of: testProcess) == 1)

        postTermination(of: NSRunningApplication.current, to: center)
        await waitUntil {
            exposer.expose(testProcess)
            return recorder.count(of: testProcess) == 2
        }

        #expect(recorder.count(of: testProcess) == 2)
        exposer.expose(testProcess)
        #expect(recorder.count(of: testProcess) == 2)
    }

    @Test("AC-6: 終了したのが別のアプリなら、頼み済みのアプリは忘れない")
    func keepsAppsWhenAnotherTerminates() async {
        let recorder = ExposeRequestRecorder()
        let center = NotificationCenter()
        let exposer = makeExposer(recorder, notificationCenter: center)

        exposer.expose(editor)
        exposer.expose(testProcess)
        postTermination(of: NSRunningApplication.current, to: center)
        await waitUntil {
            exposer.expose(testProcess)
            return recorder.count(of: testProcess) == 2
        }
        #expect(recorder.count(of: testProcess) == 2)

        exposer.expose(editor)
        #expect(recorder.count(of: editor) == 1)
    }

    @Test("AC-6: forget したアプリはまた頼み、他のアプリは忘れない")
    func forgetRemovesOnlyThatApp() {
        let recorder = ExposeRequestRecorder()
        let exposer = makeExposer(recorder)
        exposer.expose(editor)
        exposer.expose(other)

        exposer.forget(processIdentifier: editor.processIdentifier)
        exposer.expose(editor)
        exposer.expose(other)

        #expect(recorder.count(of: editor) == 2)
        #expect(recorder.count(of: other) == 1)
    }

    // MARK: - AC-7

    @Test(
        "AC-7: 成功・属性が無いときだけ頼み済みとして覚える",
        arguments: [
            (AXError.success, true),
            (AXError.attributeUnsupported, true),
            (AXError.cannotComplete, false),
            (AXError.apiDisabled, false),
            (AXError.failure, false),
            (AXError.illegalArgument, false),
            (AXError.invalidUIElement, false),
        ]
    )
    func shouldRememberTable(result: AXError, expected: Bool) {
        #expect(WebContentExposer.shouldRemember(result) == expected, "\(result.rawValue)")
    }

    @Test("AC-7: 成功・属性が無いと返ったアプリにはもう頼まず、それ以外の結果のときは次の機会にまた頼む")
    func exposeRemembersOnlyAcceptedResults() {
        let remembered: [AXError] = [.success, .attributeUnsupported]
        for result in remembered {
            let recorder = ExposeRequestRecorder()
            recorder.result = result
            let exposer = makeExposer(recorder)
            exposer.expose(editor)
            exposer.expose(editor)
            #expect(recorder.count(of: editor) == 1, "\(result.rawValue)")
        }

        let notRemembered: [AXError] = [.failure, .cannotComplete, .apiDisabled, .illegalArgument, .invalidUIElement]
        for result in notRemembered {
            let recorder = ExposeRequestRecorder()
            recorder.result = result
            let exposer = makeExposer(recorder)
            exposer.expose(editor)
            exposer.expose(editor)
            #expect(recorder.count(of: editor) == 2, "\(result.rawValue)")
        }
    }

    @Test("AC-7: 失敗の後に成功すると、そこで覚えてそれ以降は頼まない")
    func rememberedAfterEventualSuccess() {
        let recorder = ExposeRequestRecorder()
        recorder.result = .failure
        let exposer = makeExposer(recorder)

        exposer.expose(editor)
        recorder.result = .success
        exposer.expose(editor)
        exposer.expose(editor)

        #expect(recorder.count(of: editor) == 2)
    }

    // MARK: - AC-8

    @Test("AC-8: 挿入先が無い・自分自身・許可が無いときは頼まず、他のアプリで許可があるときだけ頼む")
    func shouldExposeWebContentTable() {
        let cases: [(target: InsertionTarget?, isTrusted: Bool, expected: Bool)] = [
            (nil, true, false),
            (nil, false, false),
            (own, true, false),
            (own, false, false),
            (editor, false, false),
            (editor, true, true),
        ]
        for (target, isTrusted, expected) in cases {
            let result = PanelController.shouldExposeWebContent(
                target: target,
                ownProcessIdentifier: Self.ownPid,
                isTrusted: isTrusted
            )
            #expect(result == expected, "\(String(describing: target)) trusted=\(isTrusted)")
        }
    }

    @Test("AC-8: パネルを開くとき、挿入先が他のアプリで許可があれば頼む")
    func openExposesForOtherAppWhenTrusted() async throws {
        var requested: [InsertionTarget] = []
        try await withController(isTrusted: true, target: editor, exposeWebContent: { requested.append($0) }) { controller, _ in
            controller.open()
        }
        #expect(requested == [editor])
    }

    @Test("AC-8: パネルを開くとき、許可が無ければ頼まない")
    func openDoesNotExposeWithoutPermission() async throws {
        var requested: [InsertionTarget] = []
        try await withController(isTrusted: false, target: editor, exposeWebContent: { requested.append($0) }) { controller, _ in
            controller.open()
        }
        #expect(requested.isEmpty)
    }

    @Test("AC-8: パネルを開くとき、挿入先が自分自身なら頼まない")
    func openDoesNotExposeForOwnApp() async throws {
        var requested: [InsertionTarget] = []
        try await withController(isTrusted: true, target: own, exposeWebContent: { requested.append($0) }) { controller, _ in
            controller.open()
        }
        #expect(requested.isEmpty)
    }

    @Test("AC-8: 見張りが頼んだアプリには、パネルを開いても頼まない")
    func panelSkipsAppExposedByWatcher() async throws {
        let recorder = ExposeRequestRecorder()
        let exposer = makeExposer(recorder)
        let fixture = try WatcherFixture(exposeWebContent: { exposer.expose($0) })
        defer { fixture.removeSuite() }

        fixture.activate(editor)
        #expect(recorder.count(of: editor) == 1)

        try await withController(isTrusted: true, target: editor, exposeWebContent: { exposer.expose($0) }) { controller, _ in
            controller.open()
        }
        #expect(recorder.count(of: editor) == 1)
    }

    @Test("AC-8: パネルを開いて頼んだアプリには、見張りも頼まない")
    func watcherSkipsAppExposedByPanel() async throws {
        let recorder = ExposeRequestRecorder()
        let exposer = makeExposer(recorder)
        let fixture = try WatcherFixture(exposeWebContent: { exposer.expose($0) })
        defer { fixture.removeSuite() }

        try await withController(isTrusted: true, target: editor, exposeWebContent: { exposer.expose($0) }) { controller, _ in
            controller.open()
        }
        #expect(recorder.count(of: editor) == 1)

        fixture.activate(editor)
        #expect(recorder.count(of: editor) == 1)
    }
}
