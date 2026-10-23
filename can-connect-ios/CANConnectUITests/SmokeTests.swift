import XCTest

final class SmokeTests: XCTestCase {
    func testTabsPagesAndSampleRecording() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Your roads"].waitForExistence(timeout:10))
        app.buttons["Live"].tap()
        XCTAssertTrue(app.buttons["Start sample recording"].waitForExistence(timeout:5))
        app.buttons["Engine"].tap()
        XCTAssertTrue(app.staticTexts["Engine signals"].waitForExistence(timeout:3))
        app.buttons["Economy"].tap()
        XCTAssertTrue(app.buttons["Start sample recording"].exists)
        app.buttons["Start sample recording"].tap()
        XCTAssertTrue(app.buttons["Finish & save recording"].waitForExistence(timeout:3))
        app.buttons["Drive"].tap()
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Locked design — native Drive"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Finish & save recording"].tap()
        app.buttons["Trips"].tap()
        XCTAssertTrue(app.staticTexts["Sample drive"].waitForExistence(timeout:5))
        app.buttons["Live"].tap()
        XCTAssertTrue(app.buttons["Drive"].isSelected)
        app.buttons["Vehicle"].tap(); app.buttons["Logbook"].tap()
        XCTAssertTrue(app.buttons["Log a fill-up"].waitForExistence(timeout:3))
        app.buttons["Connect"].tap(); app.buttons["Transfers"].tap()
        XCTAssertTrue(app.buttons["Export all recordings"].waitForExistence(timeout:3))
        app.buttons["Vehicle"].tap()
        XCTAssertTrue(app.buttons["Logbook"].isSelected)
    }
}
