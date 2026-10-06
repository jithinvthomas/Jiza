import XCTest

final class MusicPlayerUITests: XCTestCase {
    func testLandscapeAndReturnToPortrait() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        app.buttons["homePlayer"].tap()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let menu = app.buttons["Music menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height && app.frame.contains(menu.frame) && menu.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
        capture(app, name: "Jiza Landscape")
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.height > app.frame.width && app.frame.contains(menu.frame) && menu.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 10), .completed)
    }

    func testMenuAndPlayerFitOnScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-jizaAppearance", "light"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        app.buttons["homePlayer"].tap()
        let menu = app.buttons["Music menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCTAssertTrue(app.frame.contains(menu.frame))
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(app.frame.contains(play.frame))
        capture(app, name: "Jiza Cobalt Light")
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Choose folder"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open audio file"].exists)
        XCTAssertTrue(app.buttons["Open video file"].exists)
        app.buttons["Choose folder"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 60))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.tap()
        app.buttons["Open video file"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 60))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
    }

    func testHomeChoicesAndTradingValidation() {
        let app = XCUIApplication()
        app.launchArguments = ["-jizaTradingAddress", ""]
        app.launch()
        XCTAssertTrue(app.buttons["homePlayer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["homeBrowser"].exists)
        XCTAssertTrue(app.buttons["homeTrading"].exists)
        app.buttons["homeTrading"].tap()
        let address = app.textFields["webAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Open Trading"].isEnabled)
        address.tap()
        address.typeText("https://localhost:8000")
        app.buttons["Open Trading"].tap()
        XCTAssertTrue(app.staticTexts["addressError"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["homeBrowser"].tap()
        XCTAssertTrue(app.textFields["webAddress"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open website"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["homePlayer"].tap()
        XCTAssertTrue(app.buttons["Music menu"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["homeTrading"].waitForExistence(timeout: 3))
    }
    private func capture(_ app: XCUIApplication, name: String) {
        // Capture the display: app-only cropping can use stale portrait bounds
        // after rotation even when the app's accessibility frame is landscape.
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
