import XCTest

/// @note p0-1304
enum AccessibilityOverride {
    static let key = "TATAKINOTE_ACCESSIBILITY_OVERRIDE"
    /// @note p0-1305
    static let trusted = "trusted"
    /// @note p0-1306
    static let untrusted = "untrusted"
}

extension XCUIApplication {
    /// @note p0-1307
    @MainActor
    func dismissPermissionGuideIfPresent(timeout: TimeInterval = 3) {
        let closeButton = buttons["permissionGuide.close"]
        guard closeButton.waitForExistence(timeout: timeout) else { return }
        closeButton.click()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 5), "権限の案内が閉じない")
    }
}
