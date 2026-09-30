import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct InsertionTargetTests {
    private let ownPID: pid_t = 1000
    private let own = InsertionTarget(processIdentifier: 1000, bundleIdentifier: "jp.co.woube.TatakiNote", localizedName: "TatakiNote")
    private let textEdit = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
    private let safari = InsertionTarget(processIdentifier: 202, bundleIdentifier: "com.apple.Safari", localizedName: "Safari")

    @Test("AC-10: 最前面が他のアプリならそれ、自分か不明なら最後に前面だった他のアプリを挿入先にする")
    func chooseTargetCombinations() {
        let cases: [(InsertionTarget?, InsertionTarget?, InsertionTarget?, String)] = [
            (textEdit, safari, textEdit, "最前面=他のアプリ, last=有"),
            (textEdit, nil, textEdit, "最前面=他のアプリ, last=無"),
            (textEdit, own, textEdit, "最前面=他のアプリ, last=自分"),
            (own, safari, safari, "最前面=自分, last=有"),
            (own, nil, nil, "最前面=自分, last=無"),
            (own, own, nil, "最前面=自分, last=自分"),
            (nil, safari, safari, "最前面=nil, last=有"),
            (nil, nil, nil, "最前面=nil, last=無"),
            (nil, own, nil, "最前面=nil, last=自分"),
        ]

        for (frontmost, lastActivated, expected, label) in cases {
            let chosen = FrontmostAppTracker.chooseTarget(
                frontmost: frontmost,
                lastActivated: lastActivated,
                ownProcessIdentifier: ownPID
            )
            #expect(chosen == expected, "\(label)")
        }
    }

    @Test("AC-10: NSWorkspace の通知センターで、前面になった他のアプリを覚え、自分は覚えない")
    func trackerRecordsActivatedAppsFromWorkspaceNotifications() async {
        let current = NSRunningApplication.current
        let userInfo: [AnyHashable: Any] = [NSWorkspace.applicationUserInfoKey: current]

        // @note p0-879
        let tracker = FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: userInfo
        )
        for _ in 0..<10 where tracker.lastActivated?.processIdentifier != current.processIdentifier {
            await Task.yield()
        }
        #expect(tracker.lastActivated == InsertionTarget(current))

        // @note p0-880
        let selfTracker = FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: current.processIdentifier)
        let before = selfTracker.lastActivated
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: userInfo
        )
        #expect(selfTracker.lastActivated == before)
        // @note p0-881
        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(selfTracker.lastActivated?.processIdentifier != current.processIdentifier)
    }
}
