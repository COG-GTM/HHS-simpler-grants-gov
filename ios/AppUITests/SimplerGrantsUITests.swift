import XCTest

final class SimplerGrantsUITests: XCTestCase {
    func testSampleTabsRenderAfterSkippingOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-SGSkipOnboarding", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["shell.tab.ask"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo · sample data"].exists)
    }
}
