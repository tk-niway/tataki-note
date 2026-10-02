import XCTest

enum AccessibilityOverride {
    static let key = "TATAKINOTE_ACCESSIBILITY_OVERRIDE"
    static let trusted = "trusted"
    static let untrusted = "untrusted"
}

extension XCUIApplication {
    @MainActor
    func dismissPermissionGuideIfPresent(timeout: TimeInterval = 3) {
        let closeButton = buttons["permissionGuide.close"]
        guard closeButton.waitForExistence(timeout: timeout) else { return }
        closeButton.click()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 5), "権限の案内が閉じない")
    }
}
