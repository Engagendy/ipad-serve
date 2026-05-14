import XCTest

final class iPadServeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureGuideScreenshots() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft

        XCTAssertTrue(app.staticTexts["HTML Serve Guide"].waitForExistence(timeout: 12))
        addScreenshot(named: "01-projects")

        XCTAssertTrue(app.staticTexts["Files"].waitForExistence(timeout: 8))
        addScreenshot(named: "02-file-browser")

        let runButton = app.buttons["Run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 8))
        runButton.tap()

        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 12))
        sleep(2)
        addScreenshot(named: "03-running-guide")
    }

    private func addScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
