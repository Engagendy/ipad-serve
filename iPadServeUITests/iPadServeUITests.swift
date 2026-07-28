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

    func testImportMenuIsReachableFromDetailView() throws {
        let app = XCUIApplication()
        app.launch()

        // The app auto-selects a project, so the menu must be reachable
        // from the detail toolbar even with the sidebar collapsed.
        let importMenu = app.buttons["Import Folder"]
        XCTAssertTrue(importMenu.waitForExistence(timeout: 12))
        importMenu.tap()

        XCTAssertTrue(app.buttons["Copy Folder into App"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Link Folder in Place"].exists)
        let shareToggle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Share on Local Network'"))
            .firstMatch
        XCTAssertTrue(shareToggle.exists)
        addScreenshot(named: "04-import-menu")

        // Enable classroom sharing; the QR toolbar button should appear.
        shareToggle.tap()
        XCTAssertTrue(app.buttons["Classroom QR Code"].waitForExistence(timeout: 8))
        addScreenshot(named: "05-classroom-sharing")

        app.buttons["Classroom QR Code"].tap()
        XCTAssertTrue(app.staticTexts["Students on the same Wi-Fi can scan this code to open the book."].waitForExistence(timeout: 8))
        addScreenshot(named: "06-classroom-qr")
    }

    private func addScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
