import XCTest

final class LiveActivityTests: XCTestCase {
    @MainActor
    func testLockScreenPresentationAndOpenRecording() async throws {
        guard ProcessInfo.processInfo.environment["CANCONNECT_LIVE_ACTIVITY_UI"] == "1" else {
            throw XCTSkip("Opt-in physical Live Activity presentation check.")
        }
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--live-activity-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Live"].waitForExistence(timeout:10)); app.buttons["Live"].tap()
        app.buttons["Start sample recording"].tap()
        XCTAssertTrue(app.buttons["Finish & save recording"].waitForExistence(timeout:5))
        try await Task.sleep(nanoseconds:2_000_000_000)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier:"com.apple.springboard")
        // Notification Center presents the same Lock Screen activity while
        // keeping this automation independent of passcode/Face ID unlocks.
        springboard.coordinate(withNormalizedOffset:CGVector(dx:0.1,dy:0.01)).press(forDuration:0.1,
            thenDragTo:springboard.coordinate(withNormalizedOffset:CGVector(dx:0.1,dy:0.8)))
        XCTAssertTrue(springboard.staticTexts["DriveLine"].waitForExistence(timeout:5))
        XCTAssertTrue(springboard.staticTexts["Sample recording"].exists)
        let shot = XCTAttachment(screenshot:springboard.screenshot()); shot.name = "Lock Screen activity — synthetic sample recording"; shot.lifetime = .keepAlways; add(shot)
        springboard.staticTexts["DriveLine"].tap()
        XCTAssertTrue(app.buttons["Finish & save recording"].waitForExistence(timeout:5))
        app.buttons["Finish & save recording"].tap()
    }
    @MainActor
    func testRecordingActivityOnDynamicIslandAndReturnToLive() async throws {
        guard ProcessInfo.processInfo.environment["CANCONNECT_LIVE_ACTIVITY_UI"] == "1" else {
            throw XCTSkip("Opt-in SpringBoard acceptance needs a Dynamic Island device with Live Activities enabled.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--live-activity-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Live"].waitForExistence(timeout:10)); app.buttons["Live"].tap()
        app.buttons["Start sample recording"].tap()
        XCTAssertTrue(app.buttons["Finish & save recording"].waitForExistence(timeout:5))
        try await Task.sleep(nanoseconds:2_000_000_000)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier:"com.apple.springboard")
        try await Task.sleep(nanoseconds:2_000_000_000)
        springboard.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.035)).press(forDuration:1.5)
        XCTAssertTrue(springboard.staticTexts["DriveLine"].waitForExistence(timeout:5))
        XCTAssertTrue(springboard.staticTexts["Sample recording"].exists)
        let shot = XCTAttachment(screenshot:springboard.screenshot()); shot.name = "Live Activity — synthetic sample recording"; shot.lifetime = .keepAlways; add(shot)
        // The expanded island collapses while XCTest waits for quiescence.
        // Its persistent compact surface remains the system's tap target.
        try await Task.sleep(nanoseconds:3_000_000_000)
        springboard.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.035)).tap()
        XCTAssertTrue(app.buttons["Finish & save recording"].waitForExistence(timeout:5))
        app.buttons["Finish & save recording"].tap()
        XCTAssertTrue(app.buttons["Start sample recording"].waitForExistence(timeout:5))
        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds:2_000_000_000)
        let ended = XCTAttachment(screenshot:springboard.screenshot()); ended.name = "Live Activity ended after Finish"; ended.lifetime = .keepAlways; add(ended)
        app.activate()
    }
}
