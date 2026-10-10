import AppKit
import Testing
@testable import TatakiNote

@MainActor
private final class RecordingOutlineWindow: InsertionTargetOutlineWindow {
    private(set) var isShown = false
    private(set) var orderedBelow: [Int] = []
    private(set) var orderedFrontCount = 0

    override var isVisible: Bool { isShown }

    override func orderFrontRegardless() {
        isShown = true
        orderedFrontCount += 1
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        isShown = true
        if place == .below {
            orderedBelow.append(otherWin)
        }
    }

    override func orderOut(_ sender: Any?) {
        isShown = false
    }
}

@MainActor
private final class VisiblePanelStub: NSPanel {
    static let number = 4242

    override var isVisible: Bool { true }
    override var windowNumber: Int { Self.number }
}

@MainActor
struct InsertionTargetOutlineControllerTests {
    private let screenHeight: CGFloat = 1000
    private let rect = CGRect(x: 100, y: 200, width: 300, height: 50)

    private struct Fixture {
        let defaults: TemporaryDefaults
        let settings: AppSettings
        let model: PanelModel
        let outline: InsertionTargetOutlineModel
        let window: RecordingOutlineWindow
        let controller: InsertionTargetOutlineController
    }

    private func makeFixture(screenHeight: CGFloat?, panel: NSWindow? = nil) throws -> Fixture {
        let defaults = try TemporaryDefaults()
        let settings = defaults.makeSettings()
        let model = PanelModel()
        let outline = InsertionTargetOutlineModel()
        let window = RecordingOutlineWindow()
        let controller = InsertionTargetOutlineController(
            outline: outline,
            settings: settings,
            panelModel: model,
            panel: panel ?? NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                styleMask: [.borderless],
                backing: .buffered,
                defer: true
            ),
            window: window,
            primaryScreenHeight: { screenHeight }
        )
        return Fixture(
            defaults: defaults,
            settings: settings,
            model: model,
            outline: outline,
            window: window,
            controller: controller
        )
    }

    private func expectedFrame(for rect: CGRect) -> CGRect {
        InsertionTargetOutlineGeometry.windowFrame(
            outlineRect: rect,
            primaryScreenHeight: screenHeight,
            outset: InsertionTargetOutlineWindow.outset
        )
    }

    private func waitUntilVisible(_ window: NSWindow) async throws -> Bool {
        try await waitUntil(attempts: 100, interval: .milliseconds(20)) { window.isVisible }
    }

    private func waitUntilHidden(_ window: NSWindow) async throws -> Bool {
        try await waitUntil(attempts: 100, interval: .milliseconds(20)) { !window.isVisible }
    }

    @Test("AC-22: 窓を出すのは、パネルが開いていて・設定がオンで・枠があるときだけ")
    func shouldShowOnlyWhenAllConditionsHold() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        for isPresented in [true, false] {
            for isEnabled in [true, false] {
                for candidate in [rect, nil] {
                    let expected = isPresented && isEnabled && candidate != nil
                    #expect(
                        InsertionTargetOutlineController.shouldShow(
                            isPanelPresented: isPresented,
                            isOutlineEnabled: isEnabled,
                            rect: candidate
                        ) == expected,
                        "presented=\(isPresented) enabled=\(isEnabled) rect=\(String(describing: candidate))"
                    )
                }
            }
        }
    }

    @Test("AC-22: パネルが開いて枠が入ると、枠を外側へ広げた位置と大きさで窓が出る")
    func showsAtOutsetFrameWhenPresentedWithRect() async throws {
        let fixture = try makeFixture(screenHeight: screenHeight)
        defer { fixture.defaults.remove() }

        fixture.model.present(target: nil)
        fixture.outline.update(rect)

        #expect(try await waitUntilVisible(fixture.window))
        #expect(fixture.window.frame == CGRect(x: 96, y: 746, width: 308, height: 58))
        #expect(fixture.window.frame == expectedFrame(for: rect))
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("AC-22: 枠が変わると、窓の位置と大きさが付いて動く")
    func followsRectChanges() async throws {
        let fixture = try makeFixture(screenHeight: screenHeight)
        defer { fixture.defaults.remove() }

        fixture.model.present(target: nil)
        fixture.outline.update(rect)
        #expect(try await waitUntilVisible(fixture.window))

        let moved = CGRect(x: 40, y: 80, width: 120, height: 30)
        fixture.outline.update(moved)
        let followed = try await waitUntil(attempts: 100, interval: .milliseconds(20)) {
            fixture.window.frame == expectedFrame(for: moved)
        }

        #expect(followed)
        #expect(fixture.window.isVisible)
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("AC-22: 窓の枠は画面の端でも補正されず、枠のとおりになる")
    func windowFrameIsNotConstrainedToScreen() {
        let window = InsertionTargetOutlineWindow()
        let offScreen = NSRect(x: -5_000, y: 20_000, width: 308, height: 58)

        #expect(window.constrainFrameRect(offScreen, to: NSScreen.main) == offScreen)
        window.setFrame(offScreen, display: false)
        #expect(window.frame == offScreen)
    }

    @Test("AC-22: パネルが開いていても、枠が無ければ窓は出ず、枠が無くなると消える")
    func hidesWhenRectDisappears() async throws {
        let fixture = try makeFixture(screenHeight: screenHeight)
        defer { fixture.defaults.remove() }

        fixture.model.present(target: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!fixture.window.isVisible)

        fixture.outline.update(rect)
        #expect(try await waitUntilVisible(fixture.window))

        fixture.outline.update(nil)
        #expect(try await waitUntilHidden(fixture.window))
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("AC-22: 設定をオフにすると消え、オンに戻すと出る")
    func hidesWhenSettingTurnedOffAndReturnsWhenOn() async throws {
        let fixture = try makeFixture(screenHeight: screenHeight)
        defer { fixture.defaults.remove() }

        fixture.model.present(target: nil)
        fixture.outline.update(rect)
        #expect(try await waitUntilVisible(fixture.window))

        fixture.settings.isInsertionTargetOutlineShown = false
        #expect(try await waitUntilHidden(fixture.window))

        fixture.settings.isInsertionTargetOutlineShown = true
        #expect(try await waitUntilVisible(fixture.window))
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("AC-22: 設定がオフのときは、パネルを開いて枠が入っても窓は出ない")
    func staysHiddenWhileSettingIsOff() async throws {
        let fixture = try makeFixture(screenHeight: screenHeight)
        defer { fixture.defaults.remove() }

        fixture.settings.isInsertionTargetOutlineShown = false
        fixture.model.present(target: nil)
        fixture.outline.update(rect)
        try await Task.sleep(for: .milliseconds(100))

        #expect(!fixture.window.isVisible)
        #expect(fixture.window.orderedFrontCount == 0)
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("AC-22: パネルを閉じると、どの閉じ方でも窓が消える")
    func hidesWhenPanelDismissed() async throws {
        let fixture = try makeFixture(screenHeight: screenHeight)
        defer { fixture.defaults.remove() }

        fixture.model.present(target: nil)
        fixture.outline.update(rect)
        #expect(try await waitUntilVisible(fixture.window))

        fixture.model.dismiss()
        #expect(try await waitUntilHidden(fixture.window))

        fixture.model.present(target: nil)
        #expect(try await waitUntilVisible(fixture.window))

        fixture.model.text = "abc"
        _ = fixture.model.prepareCommit(isAccessibilityTrusted: false)
        #expect(!fixture.model.isPresented)
        #expect(try await waitUntilHidden(fixture.window))
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("AC-22: パネルが見えているときは、窓をパネルのすぐ下に並べる")
    func ordersWindowBelowVisiblePanel() async throws {
        let panel = VisiblePanelStub(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        let fixture = try makeFixture(screenHeight: screenHeight, panel: panel)
        defer { fixture.defaults.remove() }

        fixture.model.present(target: nil)
        fixture.outline.update(rect)

        #expect(try await waitUntilVisible(fixture.window))
        #expect(fixture.window.orderedBelow == [VisiblePanelStub.number])
        #expect(fixture.window.orderedFrontCount == 0)
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("AC-22: パネルが見えていないときは、窓を最前面に出す")
    func ordersWindowFrontWhenPanelIsNotVisible() async throws {
        let fixture = try makeFixture(screenHeight: screenHeight)
        defer { fixture.defaults.remove() }

        fixture.model.present(target: nil)
        fixture.outline.update(rect)

        #expect(try await waitUntilVisible(fixture.window))
        #expect(fixture.window.orderedFrontCount == 1)
        #expect(fixture.window.orderedBelow.isEmpty)
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("AC-22: 主画面の高さが分からないときは窓を出さない")
    func staysHiddenWithoutPrimaryScreen() async throws {
        let fixture = try makeFixture(screenHeight: nil)
        defer { fixture.defaults.remove() }

        fixture.model.present(target: nil)
        fixture.outline.update(rect)
        try await Task.sleep(for: .milliseconds(100))

        #expect(!fixture.window.isVisible)
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("AC-23: 窓はクリックを受けず、キーにもメインにもならない")
    func windowIgnoresMouseAndNeverBecomesKey() {
        let window = InsertionTargetOutlineWindow()

        #expect(window.ignoresMouseEvents)
        #expect(!window.canBecomeKey)
        #expect(!window.canBecomeMain)
        #expect(!window.hidesOnDeactivate)
        #expect(!window.hasShadow)
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
    }

    @Test("AC-23: 窓はパネルと同じ階層で、すべての操作スペースに出る")
    func windowSharesPanelLevelAndJoinsAllSpaces() {
        let window = InsertionTargetOutlineWindow()
        let panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))

        #expect(window.level == panel.level)
        #expect(window.level == .floating)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.stationary))
        #expect(window.collectionBehavior.contains(.ignoresCycle))
        #expect(window.styleMask.contains(.borderless))
        #expect(window.identifier?.rawValue == "insertionTargetOutline")
    }
}
