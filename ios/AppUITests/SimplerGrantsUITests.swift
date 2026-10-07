import XCTest

final class SimplerGrantsUITests: XCTestCase {
    func testSampleTabsRenderAfterSkippingOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-SGSkipOnboarding", "YES"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Ask"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo · sample data"].exists)
    }
}
