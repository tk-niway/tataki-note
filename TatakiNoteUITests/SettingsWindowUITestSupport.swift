import XCTest

extension XCUIApplication {
    @MainActor
    func revealInSettings(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "設定画面の部品が無い: \(element)")
        let scrollView = descendants(matching: .any)["settings.detailScrollView"].firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: timeout), "設定画面の右側(settings.detailScrollView)が無い")

        let step: CGFloat = 50
        let maxScrolls = 40
        for _ in 0..<maxScrolls {
            let visible = scrollView.frame
            let target = element.frame
            if target.minY >= visible.minY && target.maxY <= visible.maxY {
                return
            }
            let deltaY: CGFloat = target.maxY > visible.maxY ? -step : step
            scrollView.scroll(byDeltaX: 0, deltaY: deltaY)
        }
        XCTFail("設定画面の右側を、部品が見える位置までスクロールできない: \(element)")
    }
}
