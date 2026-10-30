import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct FrontmostAppObserverTests {
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
