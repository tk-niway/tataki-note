import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class ClickEnvironment {
    var frontmost: InsertionTarget?
    var mouse = CGPoint.zero
    var monitor: InsertionTargetMonitor?
    var exposed: [InsertionTarget] = []
}

@MainActor
struct PanelOpenWithoutTargetTests {
    private static let ownPid: pid_t = 4242

    private let editor = MonitorFixture.editor
    private let fieldFrame = MonitorFixture.frameA

    private func withController(
        environment: ClickEnvironment? = nil,
        _ body: (PanelController, PerAppProbeStub, AppSettings, ClickEnvironment) throws -> Void
    ) throws {
        let environment = environment ?? ClickEnvironment()
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.panelScreen = .mouse
        settings.animationMode = .off
        let probe = PerAppProbeStub()
        probe.results[editor.processIdentifier] = FocusedElementProbe(
            element: MonitorFixture.fieldA,
            lookup: MonitorFixture.textField,
            frame: fieldFrame
        )
        probe.elementFrames[7001] = fieldFrame
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: InserterStub(result: .inserted),
            permission: PermissionStub(isTrusted: true),
            fieldProbe: probe,
            exposeWebContent: { environment.exposed.append($0) },
            ownProcessIdentifier: Self.ownPid,
            library: DraftLibrary(store: .inMemory),
            animator: FakePanelFrameAnimator(),
            makeTargetMonitor: { model in
                let monitor = InsertionTargetMonitor(
                    panelModel: model,
                    probe: probe,
                    ownProcessIdentifier: Self.ownPid,
                    exposeWebContent: { environment.exposed.append($0) },
                    isOutlineEnabled: { true },
                    frontmostApplication: { environment.frontmost },
                    isRunning: { _ in true },
                    onScreenWindows: { [] },
                    mouseLocation: { environment.mouse },
                    primaryScreenFrame: { MonitorFixture.screen },
                    sleep: { _ in },
                    pollsAutomatically: false,
                    addClickMonitor: { _ in nil },
                    removeClickMonitor: { _ in }
                )
                environment.monitor = monitor
                return monitor
            }
        )
        controller.targetOverride = { editor }
        defer { controller.close() }
        try body(controller, probe, settings, environment)
    }

    @Test("AC-10: 前面のアプリや挿入先の差し替えがあっても、挿入先なしで開き、問い合わせも Web の中身を出す頼みもしない")
    func opensWithoutTargetAndWithoutQueries() throws {
        let environment = ClickEnvironment()
        try withController(environment: environment) { controller, probe, _, _ in
            controller.openWithoutTarget()

            #expect(controller.model.isPresented == true)
            #expect(controller.model.target == nil)
            #expect(probe.targets.isEmpty)
            #expect(probe.frameRequests.isEmpty)
            #expect(environment.exposed.isEmpty)
        }
    }

    @Test("AC-10: 同じ状況でふつうに開くと、差し替えた挿入先で開き、問い合わせもする")
    func plainOpenStillLooksUpTarget() throws {
        try withController { controller, probe, _, _ in
            controller.open()

            #expect(controller.model.target == editor)
            #expect(probe.targets == [editor])
        }
    }

    @Test("AC-10: すでに開いているときは、挿入先・本文・問い合わせの回数を変えない")
    func openPanelIsLeftAlone() throws {
        let environment = ClickEnvironment()
        try withController(environment: environment) { controller, probe, _, _ in
            controller.open()
            controller.model.text = "書きかけ"
            let probesBefore = probe.targets.count
            let exposedBefore = environment.exposed.count

            controller.openWithoutTarget()

            #expect(controller.model.isPresented == true)
            #expect(controller.model.target == editor)
            #expect(controller.model.text == "書きかけ")
            #expect(probe.targets.count == probesBefore)
            #expect(environment.exposed.count == exposedBefore)
        }
    }

    @Test("AC-10: 開いても書きかけのモードは変わらない(ノートの書きかけはノートのまま)", arguments: DraftMode.allCases)
    func openingKeepsDraftMode(setting: DraftMode) throws {
        try withController { controller, _, settings, _ in
            settings.newDraftMode = setting
            controller.session.request(.newScratch)
            controller.session.toggleMode()
            let modeBefore = controller.session.mode
            #expect(modeBefore == setting.toggled)

            controller.openWithoutTarget()

            #expect(controller.session.mode == modeBefore)
        }
    }

    @Test("AC-11: 挿入先なしで開いたあと、他のアプリの入力欄をクリックすると、そこが挿入先になる")
    func clickingFieldAfterOpeningBecomesTarget() throws {
        let environment = ClickEnvironment()
        try withController(environment: environment) { controller, _, _, environment in
            controller.openWithoutTarget()
            #expect(controller.model.target == nil)

            environment.frontmost = editor
            environment.mouse = CGPoint(x: fieldFrame.midX, y: MonitorFixture.screen.maxY - fieldFrame.midY)
            environment.monitor?.handleClick()

            #expect(controller.model.target == editor)
        }
    }

    @Test("AC-11: 入力欄の外をクリックしても、挿入先なしのまま")
    func clickingOutsideFieldKeepsNoTarget() throws {
        let environment = ClickEnvironment()
        try withController(environment: environment) { controller, _, _, environment in
            controller.openWithoutTarget()

            environment.frontmost = editor
            environment.mouse = CGPoint(x: 900, y: 700)
            environment.monitor?.handleClick()

            #expect(controller.model.target == nil)
        }
    }
}
