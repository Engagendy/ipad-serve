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
        // from the detail toolbar even with the sidebar collapsed. When the
        // sidebar is visible the menu appears in both toolbars, so pick one.
        let importMenu = app.buttons["Import Folder"].firstMatch
        XCTAssertTrue(importMenu.waitForExistence(timeout: 12))
        importMenu.tap()

        XCTAssertTrue(app.buttons["Copy Folder into App"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Link Folder in Place"].exists)
        let shareToggle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Share on Local Network'"))
            .firstMatch
        XCTAssertTrue(shareToggle.exists)
        addScreenshot(named: "04-import-menu")
    }

    func testShareQRFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // The QR button is always visible in the detail toolbar; when
        // sharing is off it offers to turn sharing on.
        let qrButton = app.buttons["Share QR Code"]
        XCTAssertTrue(qrButton.waitForExistence(timeout: 12))
        qrButton.tap()

        // Sharing persists across launches, so a previous run may have left
        // it on; only walk through the turn-on step when it is off.
        let turnOn = app.buttons["Turn On Sharing"]
        if turnOn.waitForExistence(timeout: 4) {
            addScreenshot(named: "05-sharing-off")
            turnOn.tap()
        }

        let hint = app.staticTexts["People on the same Wi-Fi can scan this code to see the same project."]
        XCTAssertTrue(hint.waitForExistence(timeout: 8))
        addScreenshot(named: "06-share-qr")
        app.buttons["Done"].tap()

        // The QR button is also in the browser toolbar, beside Home,
        // while a page is running.
        app.buttons["Run"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 8))
        let browserQR = app.buttons["Share QR Code"]
        XCTAssertTrue(browserQR.waitForExistence(timeout: 8))
        browserQR.tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 8))
        addScreenshot(named: "07-browser-qr")
    }

    private func addScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
