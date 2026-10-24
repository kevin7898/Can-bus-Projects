import XCTest
import Network

final class SmokeTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }
    override func tearDown() async throws {
        // End each test's app while its automation session is still current.
        // Launching a TCP listener before the next launch must not race cleanup
        // of the previous app on slower CI simulators.
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }

    @MainActor
    func testRegenerationComparisonIsReachableAndDoesNotCountSampleTrips() async {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Your roads"].waitForExistence(timeout:10))
        app.buttons["Vehicle"].tap(); app.buttons["DPF"].tap()
        let compare = app.buttons["regen.compare"]
        XCTAssertTrue(compare.waitForExistence(timeout:5)); compare.tap()
        XCTAssertTrue(app.staticTexts["Latest complete cycles · 0 / 10"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Interrupted / incomplete · 0"].exists)
        XCTAssertFalse(app.buttons["Export cycle comparison"].isEnabled)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Automatic regeneration comparison — no invented sample cycles"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testTabsPagesAndSampleRecording() async {
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
    @MainActor
    func testSootCardIncludesFullnessWithoutChangingCardSize() async {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Your roads"].waitForExistence(timeout:10))
        app.buttons["Live"].tap()
        let card = app.buttons["signal-card.drive.0"]
        XCTAssertTrue(card.waitForExistence(timeout:5))
        let original = card.frame
        card.tap()
        let choice = app.buttons.containing(.staticText,identifier:"DPF soot mass").firstMatch
        for _ in 0..<12 {
            if choice.exists && choice.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(choice.waitForExistence(timeout:3)); choice.tap()
        XCTAssertTrue(card.waitForExistence(timeout:5))
        XCTAssertTrue(card.label.contains("percent full"))
        XCTAssertTrue(card.label.contains("ECU regeneration trigger"))
        XCTAssertEqual(card.frame.height,original.height,accuracy:1)
        XCTAssertEqual(card.frame.width,original.width,accuracy:1)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Soot grams and fullness in existing card — unavailable sample values"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor
    func testManualVehicleOnboardingAndVehicleSwitch() async {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--show-onboarding"]; app.launch()
        let manual = app.buttons["onboarding.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout:10)); manual.tap()
        await enter("Honda",in:app.textFields["vehicle.make"],app:app)
        await enter("CB500X",in:app.textFields["vehicle.model"],app:app)
        await saveVehicle(in:app)
        await waitForOnboardingToDismiss(app)
        XCTAssertTrue(app.buttons["Choose vehicle"].waitForExistence(timeout:5))
        app.buttons["Vehicle"].tap()
        XCTAssertTrue(app.staticTexts["Honda CB500X · recorded values"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Starting odometer"].exists == false)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "New vehicle without sample telemetry"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Choose vehicle"].tap()
        let sample = app.buttons["garage.select.sample"]
        let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND hittable == true"),object:sample)
        await fulfillment(of:[ready],timeout:5)
        sample.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertTrue(app.staticTexts["Sample vehicle snapshot · recorded values"].waitForExistence(timeout:5))
    }

    @MainActor
    func testMXPlusSetupUsesPairedAccessoriesWithoutNetworkFields() async {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--show-onboarding"]; app.launch()
        XCTAssertTrue(app.buttons["onboarding.manual"].waitForExistence(timeout:10)); app.buttons["onboarding.manual"].tap()
        await enter("Test",in:app.textFields["vehicle.make"],app:app)
        await enter("Synthetic MX+",in:app.textFields["vehicle.model"],app:app)
        await saveVehicle(in:app); await waitForOnboardingToDismiss(app)
        app.buttons["Connect"].tap()
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","CAN recorder")).firstMatch.tap()
        let picker = app.buttons["scanner.transport"]
        XCTAssertTrue(picker.waitForExistence(timeout:5)); picker.tap()
        app.buttons["OBDLink MX+ · Bluetooth"].tap()
        XCTAssertTrue(app.buttons["scanner.refresh"].waitForExistence(timeout:5))
        XCTAssertFalse(app.textFields["connection.host"].exists)
        XCTAssertFalse(app.textFields["connection.port"].exists)
        app.buttons["Connect selected vehicle"].tap()
        XCTAssertTrue(app.staticTexts["Pair and choose your OBDLink MX+, then connect."].waitForExistence(timeout:5))
    }

    @MainActor
    func testWiFiScannerRecordsActualTCPFixtureReadings() async throws {
        let fixture = try LoopbackScannerFixture()
        try await fixture.start()
        defer { fixture.stop() }
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--show-onboarding"]; app.launch()
        XCTAssertTrue(app.buttons["onboarding.manual"].waitForExistence(timeout:10)); app.buttons["onboarding.manual"].tap()
        await enter("Test",in:app.textFields["vehicle.make"],app:app)
        await enter("Synthetic ECU",in:app.textFields["vehicle.model"],app:app)
        await saveVehicle(in:app)
        await waitForOnboardingToDismiss(app)
        XCTAssertTrue(app.buttons["Connect"].waitForExistence(timeout:5)); app.buttons["Connect"].tap()
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","CAN recorder")).firstMatch.tap()
        let host = app.textFields["connection.host"]; XCTAssertTrue(host.waitForExistence(timeout:3)); host.tap(); host.typeText("127.0.0.1")
        let port = app.textFields["connection.port"]; port.tap()
        port.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:5)+String(fixture.port))
        app.scrollViews.firstMatch.swipeUp()
        app.buttons["Connect selected vehicle"].tap()
        XCTAssertTrue(app.staticTexts["WI-FI OBD · VEHICLE SPEED"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["60"].waitForExistence(timeout:5))
        // A validated scanner response starts recording without an extra tap.
        XCTAssertTrue(app.buttons["Finish & save recording"].waitForExistence(timeout:3))
        app.buttons["Engine"].tap()
        XCTAssertTrue(app.staticTexts["1726"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Locked design — synthetic TCP scanner readings"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Finish & save recording"].tap(); app.buttons["Trips"].tap()
        XCTAssertTrue(app.staticTexts["Scanner drive"].waitForExistence(timeout:5))
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Scanner drive")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Measured OBD responses"].waitForExistence(timeout:5))
    }

    @MainActor
    private func enter(_ text: String, in field: XCUIElement, app: XCUIApplication) async {
        XCTAssertTrue(field.waitForExistence(timeout:5)); field.tap()
        field.typeText(text)
        let entered = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",text),object:field)
        await fulfillment(of:[entered],timeout:5)
    }
    @MainActor
    private func saveVehicle(in app: XCUIApplication) async {
        // Return dismisses native and third-party keyboards before reaching Save.
        app.textFields["vehicle.model"].typeText("\n")
        let save = app.buttons["onboarding.save"]
        XCTAssertTrue(save.waitForExistence(timeout:5))
        let form = app.scrollViews["onboarding.form"]
        for _ in 0..<6 {
            // Some device keyboards report offscreen buttons as hittable.
            let visible = form.frame.intersection(app.frame.insetBy(dx:0,dy:20))
            if save.isHittable && visible.contains(CGPoint(x:save.frame.midX,y:save.frame.midY)) { break }
            form.swipeUp()
        }
        XCTAssertTrue(app.frame.insetBy(dx:0,dy:20).contains(CGPoint(x:save.frame.midX,y:save.frame.midY)))
        save.tap()
    }
    @MainActor
    private func waitForOnboardingToDismiss(_ app: XCUIApplication) async {
        let dismissed = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            !app.buttons["onboarding.save"].exists && app.keyboards.count == 0 && app.buttons["Vehicle"].isHittable
        },object:nil)
        await fulfillment(of:[dismissed],timeout:10)
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
