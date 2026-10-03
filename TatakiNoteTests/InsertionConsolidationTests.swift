import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct InsertionConsolidationTests {
    private static let ownPid: pid_t = 4242
    private let own = InsertionTarget(processIdentifier: InsertionConsolidationTests.ownPid, bundleIdentifier: "com.example.TatakiNote")
    private let other = InsertionTarget(processIdentifier: pid_t.max - 1, bundleIdentifier: "com.example.Other")

    private func makeTutorialModel(_ temp: TemporaryDefaults) -> TutorialModel {
        TutorialModel(ownProcessIdentifier: Self.ownPid, settings: temp.makeSettings(), hotkey: { nil })
    }

    @Test("AC-6: 送信のキーは Return(36)・修飾キーなしの、押すと離すの1組になる")
    func submitKeyEventsAreReturnWithoutModifiers() throws {
        let events = try #require(CGEventSubmitKeyPoster.makeEvents())

        #expect(events.keyDown.getIntegerValueField(.keyboardEventKeycode) == 36)
        #expect(events.keyUp.getIntegerValueField(.keyboardEventKeycode) == 36)
        #expect(events.keyDown.type == .keyDown)
        #expect(events.keyUp.type == .keyUp)
        #expect(events.keyDown.flags.intersection(.maskCommand).isEmpty)
        #expect(events.keyUp.flags.intersection(.maskCommand).isEmpty)
    }

    @Test("AC-6: 貼り付けのキーは V(9)・⌘ の、押すと離すの1組になる")
    func pasteShortcutEventsAreVWithCommand() throws {
        let pair = try #require(KeyEventPair(keyCode: 9, flags: .maskCommand))

        #expect(pair.keyDown.getIntegerValueField(.keyboardEventKeycode) == 9)
        #expect(pair.keyUp.getIntegerValueField(.keyboardEventKeycode) == 9)
        #expect(pair.keyDown.type == .keyDown)
        #expect(pair.keyUp.type == .keyUp)
        #expect(pair.keyDown.flags.contains(.maskCommand))
        #expect(pair.keyUp.flags.contains(.maskCommand))
    }

    @Test("AC-6: 修飾キーなしで作ったイベントには ⌘ が付かない")
    func eventsWithoutFlagsCarryNoCommand() throws {
        let pair = try #require(KeyEventPair(keyCode: 36, flags: []))

        #expect(!pair.keyDown.flags.contains(.maskCommand))
        #expect(!pair.keyUp.flags.contains(.maskCommand))
    }

    @Test("AC-7: isOwnApp は同じプロセスのときだけ真になる")
    func isOwnAppComparesProcessIdentifiers() {
        #expect(own.isOwnApp(Self.ownPid))
        #expect(!other.isOwnApp(Self.ownPid))
        #expect(other.isOwnApp(other.processIdentifier))
    }

    @Test("AC-7: 挿入先は、前面が自分なら最後に前面になった他のアプリ、どちらも自分なら nil")
    func chooseTargetSkipsOwnApp() {
        let previous = InsertionTarget(processIdentifier: 777)

        #expect(FrontmostAppTracker.chooseTarget(frontmost: other, lastActivated: previous, ownProcessIdentifier: Self.ownPid) == other)
        #expect(FrontmostAppTracker.chooseTarget(frontmost: own, lastActivated: previous, ownProcessIdentifier: Self.ownPid) == previous)
        #expect(FrontmostAppTracker.chooseTarget(frontmost: own, lastActivated: own, ownProcessIdentifier: Self.ownPid) == nil)
        #expect(FrontmostAppTracker.chooseTarget(frontmost: nil, lastActivated: nil, ownProcessIdentifier: Self.ownPid) == nil)
    }

    @Test("AC-7: アクセシビリティの問い合わせは、自分以外の挿入先のときだけする")
    func queriesAccessibilityOnlyForOtherTargets() {
        #expect(PanelController.shouldQueryAccessibility(of: other, ownProcessIdentifier: Self.ownPid))
        #expect(!PanelController.shouldQueryAccessibility(of: own, ownProcessIdentifier: Self.ownPid))
        #expect(!PanelController.shouldQueryAccessibility(of: nil, ownProcessIdentifier: Self.ownPid))
    }

    @Test("AC-7: 練習用の入力欄への挿入の要求は、自分のアプリのときだけ受ける")
    func tutorialAcceptsInsertionRequestOnlyFromOwnApp() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        let accepted = makeTutorialModel(temp)
        accepted.insertionRequested(text: "hello", target: own, sendsAfterInsert: true)
        accepted.sendPracticeMessage("hello")
        #expect(accepted.chat.messages.last?.kind == .reply(.commitAndSend))

        let ignored = makeTutorialModel(temp)
        ignored.insertionRequested(text: "hello", target: other, sendsAfterInsert: true)
        ignored.sendPracticeMessage("hello")
        #expect(ignored.chat.messages.last?.kind == .reply(.direct))
    }

    @Test("AC-7: チュートリアルの手順は、パネルの挿入先が自分のアプリのときだけ進む")
    func tutorialAdvancesOnlyForOwnTarget() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        let model = makeTutorialModel(temp)
        model.panelDidChange(isPresented: true, target: other, text: "")
        #expect(model.currentStep == .openPanel)
        #expect(model.isShowingOtherTargetWarning)

        model.panelDidChange(isPresented: true, target: own, text: "")
        #expect(model.currentStep == .writeWithNewline)
        #expect(!model.isShowingOtherTargetWarning)
    }

    @Test("AC-8: 前面のアプリが変わった知らせを受けると、そのアプリが知らされる")
    func observerReportsActivatedApp() async {
        let center = NotificationCenter()
        let current = NSRunningApplication.current
        var received: [NSRunningApplication?] = []
        let observer = FrontmostAppObserver(notificationCenter: center) { received.append($0) }

        center.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: current]
        )
        await yieldUntil { !received.isEmpty }

        #expect(received.count == 1)
        #expect(received.first??.processIdentifier == current.processIdentifier)
        withExtendedLifetime(observer) {}
    }

    @Test("AC-8: アプリが付いていない知らせには nil が知らされる")
    func observerReportsNilWithoutApp() async {
        let center = NotificationCenter()
        var received: [NSRunningApplication?] = []
        let observer = FrontmostAppObserver(notificationCenter: center) { received.append($0) }

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: nil)
        await yieldUntil { !received.isEmpty }

        #expect(received.count == 1)
        #expect(received[0] == nil)
        withExtendedLifetime(observer) {}
    }

    @Test("AC-8: 見張りを破棄すると、その後の知らせは知らされない")
    func observerStopsAfterRelease() async {
        let center = NotificationCenter()
        let current = NSRunningApplication.current
        var count = 0
        var observer: FrontmostAppObserver? = FrontmostAppObserver(notificationCenter: center) { _ in count += 1 }
        let userInfo: [AnyHashable: Any] = [NSWorkspace.applicationUserInfoKey: current]

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: userInfo)
        await yieldUntil { count == 1 }
        #expect(count == 1)

        observer = nil
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil, userInfo: userInfo)
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(count == 1)
        #expect(observer == nil)
    }
}
