import Testing
@testable import TatakiNote

@MainActor
struct AutoShowLaunchContextTests {
    @Test("AC-14: 単体テストのホストとして起動したときは、フォーカスの見張りを始めない")
    func unitTestHostDoesNotWatchFocusedElement() {
        let unitTestHosts: [[String: String]] = [
            ["XCTestConfigurationFilePath": "/tmp/config.xctestconfiguration"],
            ["XCTestBundlePath": "/tmp/TatakiNoteTests.xctest"],
            ["XCTestConfigurationFilePath": "/tmp/a", "XCTestBundlePath": "/tmp/b", "HOME": "/Users/test"],
            ["XCTestBundlePath": "/tmp/b", "TATAKINOTE_ACCESSIBILITY_OVERRIDE": "trusted"],
        ]
        for environment in unitTestHosts {
            #expect(AppLaunchContext.shouldWatchFocusedElement(environment: environment) == false, "\(environment)")
        }
    }

    @Test("AC-14: テストの環境変数が無い起動(通常・UI テスト)では、フォーカスの見張りを始める")
    func otherLaunchesWatchFocusedElement() {
        let otherLaunches: [[String: String]] = [
            [:],
            ["HOME": "/Users/test", "PATH": "/usr/bin"],
            ["TATAKINOTE_ACCESSIBILITY_OVERRIDE": "trusted"],
            // @note p0-789
            ["XCTestSessionIdentifier": "abc", "XCTestManagerVariant": "DDI"],
        ]
        for environment in otherLaunches {
            #expect(AppLaunchContext.shouldWatchFocusedElement(environment: environment) == true, "\(environment)")
        }
    }
}
