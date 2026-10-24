import XCTest
import Network

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
    func testManualVehicleOnboardingAndVehicleSwitch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--show-onboarding"]; app.launch()
        let manual = app.buttons["onboarding.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout:10)); manual.tap()
        let make = app.textFields["vehicle.make"]; make.tap(); make.typeText("Honda")
        let model = app.textFields["vehicle.model"]; model.tap(); model.typeText("CB500X")
        let save = app.buttons["onboarding.save"]
        for _ in 0..<6 {
            if save.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(save.waitForExistence(timeout:5)); save.tap()
        XCTAssertTrue(app.buttons["Choose vehicle"].waitForExistence(timeout:5))
        app.buttons["Vehicle"].tap()
        XCTAssertTrue(app.staticTexts["Honda CB500X · recorded values"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Starting odometer"].exists == false)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "New vehicle without sample telemetry"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Choose vehicle"].tap(); app.buttons["Sample Jetta"].tap()
        XCTAssertTrue(app.staticTexts["Sample vehicle snapshot · recorded values"].waitForExistence(timeout:5))
    }

    @MainActor
    func testWiFiScannerRecordsActualTCPFixtureReadings() async throws {
        let fixture = try LoopbackScannerFixture()
        try await fixture.start()
        defer { fixture.stop() }
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--show-onboarding"]; app.launch()
        XCTAssertTrue(app.buttons["onboarding.manual"].waitForExistence(timeout:10)); app.buttons["onboarding.manual"].tap()
        app.textFields["vehicle.make"].tap(); app.textFields["vehicle.make"].typeText("Test")
        app.textFields["vehicle.model"].tap(); app.textFields["vehicle.model"].typeText("Synthetic ECU")
        let save = app.buttons["onboarding.save"]
        for _ in 0..<6 { if save.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        save.tap()
        XCTAssertTrue(app.buttons["Connect"].waitForExistence(timeout:5)); app.buttons["Connect"].tap()
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","CAN recorder")).firstMatch.tap()
        let host = app.textFields["connection.host"]; XCTAssertTrue(host.waitForExistence(timeout:3)); host.tap(); host.typeText("127.0.0.1")
        let port = app.textFields["connection.port"]; port.tap()
        port.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:5)+String(fixture.port))
        app.scrollViews.firstMatch.swipeUp()
        app.buttons["Connect selected vehicle"].tap()
        XCTAssertTrue(app.staticTexts["WI-FI OBD · VEHICLE SPEED"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["60"].waitForExistence(timeout:5))
        app.buttons["Start scanner recording"].tap()
        XCTAssertTrue(app.buttons["Finish & save recording"].waitForExistence(timeout:3))
        app.buttons["Engine"].tap()
        XCTAssertTrue(app.staticTexts["1726"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Locked design — synthetic TCP scanner readings"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Finish & save recording"].tap(); app.buttons["Trips"].tap()
        XCTAssertTrue(app.staticTexts["Scanner drive"].waitForExistence(timeout:5))
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Scanner drive")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Measured OBD responses"].waitForExistence(timeout:5))
    }

}


private final class LoopbackScannerFixture {
    private let queue = DispatchQueue(label:"canconnect.ui.scanner.fixture")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    var port: UInt16 { listener.port!.rawValue }
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
        listener = try NWListener(using:parameters)
    }
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: continuation.resume()
                case .failed(let error): continuation.resume(throwing:error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connections.append(connection); connection.start(queue:self.queue)
                self.receive(connection,buffer:"")
            }
            listener.start(queue:queue)
        }
    }
    private func receive(_ connection: NWConnection, buffer: String) {
        connection.receive(minimumIncompleteLength:1,maximumLength:4096) { [weak self] data,_,complete,error in
                var next = buffer + (data.map { String(decoding:$0,as:UTF8.self) } ?? "")
                while let end = next.firstIndex(of:"\r") {
                    let command = String(next[..<end]); next = String(next[next.index(after:end)...])
                    let response: String
                    switch command {
                    case "ATI": response = "ELM327 SYNTHETIC FIXTURE"
                    case "ATDP": response = "ISO 15765-4 CAN"
                    case "0902": response = "NO DATA"
                    case "0100": response = "41 00 08 18 00 00"
                    case "010C": response = "41 0C 1A F8"
                    case "010D": response = "41 0D 3C"
                    case "0105": response = "41 05 80"
                    default: response = "OK"
                    }
                    connection.send(content:Data((response+"\r>").utf8),completion:.contentProcessed {_ in})
                }
                if !complete && error == nil { self?.receive(connection,buffer:next) }
        }
    }
    func stop() { queue.sync { listener.stateUpdateHandler = nil; listener.cancel(); connections.forEach {$0.cancel()} } }
}
