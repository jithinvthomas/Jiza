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

        app.buttons["Choose folder"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 60))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["homeVideo"].tap()
        app.buttons["Open video"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 60))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Open network stream"].waitForExistence(timeout: 3))
    }

    func testHomeChoicesAndTradingValidation() {
        let app = XCUIApplication()
        app.launchArguments = ["-jizaTradingAddress", ""]
        app.launch()
        XCTAssertTrue(app.buttons["homePlayer"].waitForExistence(timeout: 10))
        capture(app, name: "Jiza White Wordmark Home")
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

extension MusicPlayerUITests {
    func testBrowserPullRefreshAndLinkActions() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["homeBrowser"].tap()
        let address = app.textFields["webAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap()
        if app.buttons["clearWebAddress"].exists { app.buttons["clearWebAddress"].tap() }
        address.typeText("remove-this.example")
        app.buttons["clearWebAddress"].tap()
        XCTAssertFalse(app.buttons["clearWebAddress"].exists)
        address.typeText("http://127.0.0.1:8765/interactions")
        app.buttons["Open website"].tap()
        let pageLoad = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Page load ")).firstMatch
        XCTAssertTrue(pageLoad.waitForExistence(timeout: 30))
        let previousLoad = pageLoad.label
        let surface = app.webViews.firstMatch
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.1, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        let reloaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            pageLoad.exists && pageLoad.label != previousLoad
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reloaded], timeout: 30), .completed)
        let link = app.webViews.links["Example page"]
        link.press(forDuration: 1)
        for title in ["Open in new tab", "Open in private tab", "Download link", "Save bookmark", "Copy link", "Share link"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5), title)
        }
        capture(app, name: "Jiza Link Actions")
        app.buttons["Save bookmark"].tap()
        link.press(forDuration: 1)
        app.buttons["Open in new tab"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Browser fixture"].waitForExistence(timeout: 30))
        app.buttons["Tabs"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "Close tab").count >= 2)
    }

    func testBrowserTabsAndDownloadSettings() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["homeBrowser"].tap()
        XCTAssertTrue(app.textFields["webAddress"].waitForExistence(timeout: 5))
        app.buttons["Tabs"].tap()
        app.buttons["New private tab"].tap()
        XCTAssertTrue(app.staticTexts["Browse privately"].waitForExistence(timeout: 5))
        app.buttons["Tabs"].tap()
        capture(app, name: "Jiza Browser Tabs")
        app.buttons["New tab"].tap()
        app.buttons["Downloads"].tap()
        XCTAssertTrue(app.buttons["Choose download folder"].waitForExistence(timeout: 5))
        capture(app, name: "Jiza Browser Downloads")
        app.buttons["Choose download folder"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 30))
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        capture(app, name: "Jiza Browser Start")
    }
}

extension MusicPlayerUITests {
    func testBrowserProtectionAndLockSettingsAreAvailable() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Privacy and locks"].tap()
        XCTAssertTrue(app.switches["Face ID / iPhone passcode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["newBrowserPIN"].exists)
        XCTAssertTrue(app.secureTextFields["confirmBrowserPIN"].exists)
        capture(app, name: "Jiza Privacy and Locks")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["homeBrowser"].tap()
        let browserMenu = app.buttons["Browser menu"]
        XCTAssertTrue(browserMenu.waitForExistence(timeout: 5))
        capture(app, name: "Jiza Browser Before Protection")
        browserMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Ad blocker & pop-ups"].tap()
        XCTAssertTrue(app.switches["Ad blocker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Block pop-up windows"].exists)
        capture(app, name: "Jiza Browser Protection")
    }
}
