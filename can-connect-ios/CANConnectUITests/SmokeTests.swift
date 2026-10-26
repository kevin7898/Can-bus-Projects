import XCTest
import Network
import CoreLocation

final class SmokeTests: XCTestCase {
    @MainActor func testStaleObservationRemainsStaleThroughNativeRedraws() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--obd-freshness-fixture"];app.launch()
        let stale=app.staticTexts.containing(NSPredicate(format:"label CONTAINS[c] %@","Stale")).firstMatch
        XCTAssertTrue(stale.waitForExistence(timeout:10))
        for _ in 0..<3 {
            app.buttons["obd.freshness.redraw"].tap()
            XCTAssertTrue(stale.exists)
            XCTAssertFalse(app.staticTexts["Live"].exists)
        }
        let attachment=XCTAttachment(screenshot:app.screenshot())
        attachment.name="Sanitized stale RPM native label";attachment.lifetime = .keepAlways;add(attachment)
    }
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }
    override func tearDownWithError() throws {
        // XCTest invokes synchronous teardown on the main thread. An async
        // teardown that hops to MainActor deadlocks when a main-actor assertion
        // interrupts a test with continueAfterFailure disabled.
        MainActor.assumeIsolated { XCUIApplication().terminate() }
        try super.tearDownWithError()
    }

    @MainActor
    func testDriveLedgerPrimaryDestinationsAndMoreRoutesAreReachable() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing"];app.launch()
        XCTAssertTrue(app.staticTexts["Sample vehicle selected"].waitForExistence(timeout:10))
        for title in ["Today","Drives","Record","Garage","More"] {
            let tab=app.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout:5),"Missing \(title) destination")
            tab.tap();XCTAssertTrue(tab.isSelected,"\(title) did not become selected")
        }
        app.buttons["Garage"].tap()
        XCTAssertTrue(app.buttons["Add a vehicle"].waitForExistence(timeout:5))
        app.buttons["More"].tap()
        XCTAssertTrue(app.buttons["more.scanner"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["more.server"].exists)
        XCTAssertTrue(app.buttons["more.fuel-logbook"].exists)
        XCTAssertTrue(app.buttons["more.signals"].exists)
        XCTAssertTrue(app.buttons["more.transfer-queue"].exists)
        app.buttons["more.transfers"].tap()
        XCTAssertTrue(app.navigationBars["Transfers & backup"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["Export all recordings"].waitForExistence(timeout:5))
        app.navigationBars["Transfers & backup"].buttons["Done"].tap()
        app.buttons["more.appearance"].tap()
        XCTAssertTrue(app.segmentedControls["appearance.picker"].waitForExistence(timeout:5))
    }

    @MainActor
    func testTodayAddFillAndMoreFuelLogbookAreProminent() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--phase5-fixture"];app.launch()
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout:10));app.buttons["Today"].tap()
        let addFill=app.buttons["today.add-fill"]
        XCTAssertTrue(addFill.waitForExistence(timeout:5));XCTAssertTrue(addFill.isHittable)
        let todayShot=XCTAttachment(screenshot:app.screenshot());todayShot.name="Today — prominent Add fill-up";todayShot.lifetime = .keepAlways;add(todayShot)
        addFill.tap()
        XCTAssertTrue(app.navigationBars["Add Fuel"].waitForExistence(timeout:5))
        app.navigationBars["Add Fuel"].buttons["Done"].tap()
        app.buttons["More"].tap()
        let logbook=app.buttons["more.fuel-logbook"]
        XCTAssertTrue(logbook.waitForExistence(timeout:5));XCTAssertTrue(logbook.isHittable)
        let moreShot=XCTAttachment(screenshot:app.screenshot());moreShot.name="More — connections, fuel, data, and preferences";moreShot.lifetime = .keepAlways;add(moreShot)
        logbook.tap()
        XCTAssertTrue(app.navigationBars["Fuel Ledger"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Purchased fuel"].exists)
    }

    @MainActor
    func testMoreAndTodayFuelActionsRenderInDarkAppearance() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--phase5-fixture","--appearance-dark"];app.launch()
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout:10));app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["today.add-fill"].waitForExistence(timeout:5))
        app.buttons["More"].tap()
        XCTAssertTrue(app.buttons["more.fuel-logbook"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["more.transfers"].exists)
        XCTAssertTrue(app.buttons["more.appearance"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="More redesign — dark";shot.lifetime = .keepAlways;add(shot)
    }

    @MainActor
    func testRegenerationComparisonIsReachableAndDoesNotCountSampleTrips() async {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.staticTexts["Sample vehicle selected"].waitForExistence(timeout:10))
        app.buttons["More"].tap(); app.buttons["more.vehicle-data"].tap(); app.buttons["DPF"].tap()
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
        XCTAssertTrue(app.staticTexts["Sample vehicle selected"].waitForExistence(timeout:10))
        app.buttons["Record"].tap()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout:5))
        app.buttons["Start recording"].tap()
        XCTAssertTrue(app.buttons["Finish & save"].waitForExistence(timeout:3))
        XCTAssertTrue(app.staticTexts["Observed telemetry"].waitForExistence(timeout:3))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Locked design — native Drive"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Finish & save"].tap()
        app.buttons["Drives"].tap()
        XCTAssertTrue(app.staticTexts["Sample drive"].waitForExistence(timeout:5))
        app.buttons["Record"].tap()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout:3))
        app.buttons["More"].tap(); app.buttons["more.vehicle-data"].tap(); app.buttons["Logbook"].tap()
        XCTAssertTrue(app.buttons["Log a fill-up"].waitForExistence(timeout:3))
        app.buttons["Done"].tap(); app.buttons["more.transfers"].tap()
        XCTAssertTrue(app.buttons["Export all recordings"].waitForExistence(timeout:3))
        app.buttons["Done"].tap(); app.buttons["more.vehicle-data"].tap()
        XCTAssertTrue(app.buttons["Logbook"].isSelected)
    }
    @MainActor
    func testPhase4JourneyStoryFuelAndSignalsAreReachable() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--phase4-fixture"];app.launch()
        XCTAssertTrue(app.staticTexts["Sanitized sample journey"].waitForExistence(timeout:10))
        let ledgerShot=XCTAttachment(screenshot:app.screenshot());ledgerShot.name="Phase 4 Journey Ledger — sanitized sample";ledgerShot.lifetime = .keepAlways;add(ledgerShot)
        app.staticTexts["Sanitized sample journey"].tap()
        XCTAssertTrue(app.navigationBars["Trip Story"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Evidence timeline"].exists)
        XCTAssertTrue(app.staticTexts["Synchronized signals"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@","normalized")).firstMatch.exists)
        let storyShot=XCTAttachment(screenshot:app.screenshot());storyShot.name="Phase 4 Trip Story — shared cursor";storyShot.lifetime = .keepAlways;add(storyShot)
        app.buttons["Done"].tap();app.buttons["Garage"].tap()
        XCTAssertTrue(app.buttons["garage.fuel-ledger"].waitForExistence(timeout:5));app.buttons["garage.fuel-ledger"].tap()
        XCTAssertTrue(app.navigationBars["Fuel Ledger"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Purchased fuel"].exists)
        XCTAssertTrue(app.staticTexts["Measured trip fuel"].exists)
        let fuelShot=XCTAttachment(screenshot:app.screenshot());fuelShot.name="Phase 4 Fuel Ledger — sample excluded from totals";fuelShot.lifetime = .keepAlways;add(fuelShot)
    }
    @MainActor
    func testPhase5FuelLedgerAddAndEditAreReachable() {
        exercisePhase5Fuel(appearance:"light")
    }
    @MainActor
    func testPhase5FuelLedgerAddAndEditRenderInDarkAppearance() {
        exercisePhase5Fuel(appearance:"dark")
    }
    @MainActor
    func testPhase6SignalsOverviewDetailAndTripStoryEntryAreReachable() {
        exercisePhase6Signals(appearance:"light")
    }
    @MainActor
    func testPhase6SignalsRenderInDarkAppearance() {
        exercisePhase6Signals(appearance:"dark",checkTripStory:false)
    }
    @MainActor
    func testPhase6GPSOnlyOBDOnlyAndMissingSignalStatesAreHonest() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--phase6-fixture","--appearance-light"];app.launch()
        XCTAssertTrue(app.buttons["more.signals"].waitForExistence(timeout:10));app.buttons["more.signals"].tap()
        XCTAssertTrue(app.navigationBars["Signals"].waitForExistence(timeout:5))

        chooseRecording(named:"Sample GPS-only recording",in:app)
        XCTAssertTrue(app.staticTexts["GPS and motion"].waitForExistence(timeout:5))
        let gps=XCTAttachment(screenshot:app.screenshot());gps.name="Phase 6 GPS-only Signals state";gps.lifetime = .keepAlways;add(gps)

        chooseRecording(named:"Sample OBD-only recording",in:app)
        XCTAssertTrue(app.staticTexts["Engine"].waitForExistence(timeout:5))
        app.buttons["signals.row.rpm"].tap()
        XCTAssertTrue(app.staticTexts["Route unavailable"].waitForExistence(timeout:5))
        let obd=XCTAttachment(screenshot:app.screenshot());obd.name="Phase 6 OBD-only Signals state";obd.lifetime = .keepAlways;add(obd)
        app.navigationBars["Signal Detail"].buttons["Done"].tap()

        chooseRecording(named:"Sample missing-signal recording",in:app)
        XCTAssertTrue(app.staticTexts["No scalar signals recorded"].waitForExistence(timeout:5))
        let missing=XCTAttachment(screenshot:app.screenshot());missing.name="Phase 6 missing-signal state";missing.lifetime = .keepAlways;add(missing)
    }
    @MainActor
    func testPhase7GarageAndVehicleDetailRenderInLightAndDark() {
        for appearance in ["light","dark"] {
            let app=XCUIApplication();app.launchArguments=["--ui-testing","--phase7-fixture","--appearance-\(appearance)"];app.launch()
            XCTAssertTrue(app.staticTexts["Fictional 2013 Jetta · SAMPLE"].waitForExistence(timeout:10))
            XCTAssertTrue(app.staticTexts["F-150 · SAMPLE"].exists)
            XCTAssertTrue(app.staticTexts["CB500X ABS · SAMPLE"].exists)
            let garage=XCTAttachment(screenshot:app.screenshot());garage.name="Phase 7 iPhone Garage — \(appearance)";garage.lifetime = .keepAlways;add(garage)
            let details=app.buttons["Details"].firstMatch
            XCTAssertTrue(details.waitForExistence(timeout:5));details.tap()
            XCTAssertTrue(app.staticTexts["Identity"].waitForExistence(timeout:5))
            XCTAssertTrue(app.staticTexts["Stable UUID"].exists)
            let detail=XCTAttachment(screenshot:app.screenshot());detail.name="Phase 7 iPhone vehicle detail — \(appearance)";detail.lifetime = .keepAlways;add(detail)
            app.buttons["Done"].tap()
            for _ in 0..<8 where !app.staticTexts["T880 · SAMPLE"].exists { app.swipeUp() }
            XCTAssertTrue(app.staticTexts["T880 · SAMPLE"].waitForExistence(timeout:5))
            let archived=XCTAttachment(screenshot:app.screenshot());archived.name="Phase 7 iPhone archived vehicle — \(appearance)";archived.lifetime = .keepAlways;add(archived)
            app.terminate()
        }
    }
    @MainActor
    func testPhase7FourStageOnboardingEvidenceAndManualFailureContinuation() {
        let variants:[(String,String,String)]=[
            ("--phase7-onboarding","Vehicle","Phase 7 iPhone Vehicle stage"),
            ("--phase7-scanner","Scanner","Phase 7 iPhone Scanner stage"),
            ("--phase7-identify-success","Identify","Phase 7 iPhone successful Identify review"),
            ("--phase7-identify-failure","Identify","Phase 7 iPhone failed Identify manual continuation"),
            ("--phase7-finish","Finish","Phase 7 iPhone Finish stage")
        ]
        for (argument,title,name) in variants {
            let app=XCUIApplication();app.launchArguments=["--ui-testing","--show-onboarding","--phase7-fixture","--phase7-onboarding",argument,"--appearance-light"];app.launch()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout:10),app.debugDescription)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","2013")).firstMatch.exists || title=="Scanner")
            if argument=="--phase7-identify-success" { XCTAssertTrue(app.buttons["onboarding.year.accept"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["onboarding.year.retain"].exists) }
            if argument=="--phase7-identify-failure" { XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","manual 2013 draft is unchanged")).firstMatch.exists) }
            let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
            app.terminate()
        }
    }
    @MainActor
    func testPhase7CompactLargestAccessibilityOnboarding() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--show-onboarding","--phase7-fixture","--phase7-onboarding","--phase7-identify-success","--appearance-light"];app.launch()
        XCTAssertTrue(app.staticTexts["Identify"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","2013")).firstMatch.exists)
        let accept=app.buttons["onboarding.year.accept"]
        for _ in 0..<6 where !accept.isHittable { app.swipeUp() }
        XCTAssertTrue(accept.exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Phase 7 compact largest accessibility onboarding";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor
    func testPhase8RecoveryStatesExposeStatusEvidenceAndTargetedActions() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--phase8-state","29,33,39,47,49,53,58","--appearance-light"];app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["phase8.evidence"].waitForExistence(timeout:10),app.debugDescription)
        for id in [29,33,39,47,49,53,58] { XCTAssertTrue(app.descendants(matching:.any)["phase8.state.\(id)"].exists,"Missing Phase 8 state \(id)") }
        XCTAssertTrue(app.staticTexts["Degraded"].exists)
        XCTAssertTrue(app.staticTexts["Processing"].exists)
        XCTAssertTrue(app.staticTexts["Complete"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Phase 8 iPhone degraded transfer recovery states";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor
    func testPhase8CompactLargestAccessibilityStateCardsRemainReachable() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--phase8-state","14,19,29,33","--appearance-dark"];app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["phase8.state.14"].waitForExistence(timeout:10))
        for _ in 0..<8 where !app.descendants(matching:.any)["phase8.state.33"].exists { app.swipeUp() }
        XCTAssertTrue(app.descendants(matching:.any)["phase8.state.33"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Phase 8 compact largest accessibility recovery";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor
    private func exercisePhase6Signals(appearance:String,checkTripStory:Bool = true) {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--phase6-fixture","--appearance-\(appearance)"];app.launch()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout:10));app.buttons["More"].tap()
        XCTAssertTrue(app.buttons["more.signals"].waitForExistence(timeout:5));app.buttons["more.signals"].tap()
        XCTAssertTrue(app.navigationBars["Signals"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Engine"].exists)
        XCTAssertTrue(app.buttons["signals.row.rpm"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS[c] %@","coverage")).firstMatch.exists)
        let overview=XCTAttachment(screenshot:app.screenshot());overview.name="Phase 6 Signals overview — \(appearance)";overview.lifetime = .keepAlways;add(overview)
        app.buttons["signals.row.rpm"].tap()
        XCTAssertTrue(app.navigationBars["Signal Detail"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Visible-range observations"].exists)
        XCTAssertTrue(app.staticTexts["Recorded gaps"].exists)
        XCTAssertTrue(app.sliders["signals.visible-start"].exists)
        XCTAssertTrue(app.sliders["signals.visible-end"].exists)
        let detail=XCTAttachment(screenshot:app.screenshot());detail.name="Phase 6 Signal detail — \(appearance)";detail.lifetime = .keepAlways;add(detail)
        app.navigationBars["Signal Detail"].buttons["Done"].tap()
        guard checkTripStory else { return }
        app.navigationBars["Signals"].buttons["Done"].tap();app.buttons["Drives"].tap()
        XCTAssertTrue(app.staticTexts["Sanitized sample journey"].waitForExistence(timeout:5));app.staticTexts["Sanitized sample journey"].tap()
        let entry=app.buttons["trip-story.signals"]
        for _ in 0..<8 where !entry.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout:5));entry.tap()
        XCTAssertTrue(app.navigationBars["Signals"].waitForExistence(timeout:5))
        let contextual=XCTAttachment(screenshot:app.screenshot());contextual.name="Phase 6 Trip Story contextual Signals entry";contextual.lifetime = .keepAlways;add(contextual)
    }
    @MainActor
    private func chooseRecording(named name:String,in app:XCUIApplication) {
        app.buttons["signals.recording"].tap()
        let option=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",name)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout:5),"Missing recording option \(name)")
        option.tap()
    }
    @MainActor
    private func exercisePhase5Fuel(appearance:String) {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--phase5-fixture","--appearance-\(appearance)"];app.launch()
        XCTAssertTrue(app.buttons["garage.fuel-ledger"].waitForExistence(timeout:10));app.buttons["garage.fuel-ledger"].tap()
        XCTAssertTrue(app.navigationBars["Fuel Ledger"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Purchased fuel"].exists)
        XCTAssertTrue(app.staticTexts["Recorded fills"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","74.0")).firstMatch.exists)
        let ledger=XCTAttachment(screenshot:app.screenshot());ledger.name="Phase 5 Fuel Ledger — \(appearance)";ledger.lifetime = .keepAlways;add(ledger)
        let scroll=app.scrollViews.firstMatch
        let addButton=app.buttons["Log a fill-up"]
        for _ in 0..<6 where !addButton.isHittable { scroll.swipeUp() }
        XCTAssertTrue(addButton.isHittable);addButton.tap()
        XCTAssertTrue(app.navigationBars["Add Fuel"].waitForExistence(timeout:5))
        XCTAssertTrue(app.textFields["fuel.currency"].exists)
        XCTAssertTrue(app.textFields["fuel.station"].exists)
        XCTAssertTrue(app.textFields["fuel.notes"].exists)
        XCTAssertTrue(app.buttons["fuel.receipt.choose"].exists)
        XCTAssertTrue(app.switches["fuel.odometer-correction"].exists)
        let addShot=XCTAttachment(screenshot:app.screenshot());addShot.name="Phase 5 Add Fuel — \(appearance)";addShot.lifetime = .keepAlways;add(addShot)
        app.navigationBars["Add Fuel"].buttons["Done"].tap()
        let edit=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","fuel.edit.")).firstMatch
        for _ in 0..<5 where !edit.isHittable { scroll.swipeDown() }
        XCTAssertTrue(edit.waitForExistence(timeout:5));edit.tap()
        XCTAssertTrue(app.navigationBars["Edit Fuel"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["fuel.currency"].value as? String,"CAD")
        let editShot=XCTAttachment(screenshot:app.screenshot());editShot.name="Phase 5 Edit Fuel — \(appearance)";editShot.lifetime = .keepAlways;add(editShot)
    }
    @MainActor
    func testSootCardExplainsRegenTriggerWithoutChangingCardSize() async {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.staticTexts["Sample vehicle selected"].waitForExistence(timeout:10))
        app.buttons["Record"].tap()
        app.buttons["Start recording"].tap()
        let scroll=app.scrollViews["record.content"]
        let explanation=app.staticTexts["Regen trigger is a normalized ECU trigger indicator, never physical DPF fullness."]
        for _ in 0..<4 where !explanation.isHittable { scroll.swipeUp() }
        XCTAssertTrue(explanation.waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["record.metric.dpfSootG"].exists)
        XCTAssertTrue(app.descendants(matching:.any)["record.metric.dpfRegenTrigger"].exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Soot grams and normalized regen trigger — unavailable sample values"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor
    func testManualVehicleOnboardingAndVehicleSwitch() async {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--show-onboarding"]; app.launch()
        let manual = app.buttons["onboarding.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout:10)); manual.tap()
        await enter("2013",in:app.textFields["vehicle.year"],app:app)
        await enter("Volkswagen",in:app.textFields["vehicle.make"],app:app)
        await enter("Jetta",in:app.textFields["vehicle.model"],app:app)
        await saveVehicle(in:app)
        await waitForOnboardingToDismiss(app)
        XCTAssertTrue(app.buttons["Choose vehicle"].waitForExistence(timeout:5))
        app.buttons["More"].tap(); app.buttons["more.vehicle-data"].tap()
        XCTAssertTrue(app.staticTexts["2013 Volkswagen Jetta · recorded values"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Starting odometer"].exists == false)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "New vehicle without sample telemetry"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Done"].tap()
        app.buttons["Garage"].tap()
        let sample = app.buttons["garage.select.sample"]
        for _ in 0..<5 where !sample.isHittable { app.swipeUp() }
        let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND hittable == true"),object:sample)
        await fulfillment(of:[ready],timeout:5)
        sample.tap()
        XCTAssertEqual(sample.value as? String, "Selected")
    }

    @MainActor
    func testMXPlusSetupUsesPairedAccessoriesWithoutNetworkFields() async {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--show-onboarding"]; app.launch()
        XCTAssertTrue(app.buttons["onboarding.manual"].waitForExistence(timeout:10)); app.buttons["onboarding.manual"].tap()
        await enter("2013",in:app.textFields["vehicle.year"],app:app)
        await enter("Volkswagen",in:app.textFields["vehicle.make"],app:app)
        await enter("Jetta",in:app.textFields["vehicle.model"],app:app)
        await saveVehicle(in:app); await waitForOnboardingToDismiss(app)
        app.buttons["More"].tap()
        let scanner=app.buttons["more.scanner"];XCTAssertTrue(scanner.waitForExistence(timeout:5));scanner.tap()
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
        addUIInterruptionMonitor(withDescription:"Location permission") { alert in
            let allow = alert.buttons["Allow While Using App"]
            if allow.exists { allow.tap(); return true }
            return false
        }
        let fixture = try LoopbackScannerFixture()
        try await fixture.start()
        defer { fixture.stop() }
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing","--show-onboarding"]; app.launch()
        XCTAssertTrue(app.buttons["onboarding.manual"].waitForExistence(timeout:10)); app.buttons["onboarding.manual"].tap()
        await enter("2013",in:app.textFields["vehicle.year"],app:app)
        await enter("Volkswagen",in:app.textFields["vehicle.make"],app:app)
        await enter("Jetta",in:app.textFields["vehicle.model"],app:app)
        await saveVehicle(in:app)
        await waitForOnboardingToDismiss(app)
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout:5)); app.buttons["More"].tap()
        let scanner=app.buttons["more.scanner"];XCTAssertTrue(scanner.waitForExistence(timeout:5));scanner.tap()
        let host = app.textFields["connection.host"]; XCTAssertTrue(host.waitForExistence(timeout:3)); host.tap(); host.typeText("127.0.0.1")
        let port = app.textFields["connection.port"]; port.tap()
        port.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:5)+String(fixture.port))
        app.scrollViews.firstMatch.swipeUp()
        app.buttons["Connect selected vehicle"].tap()
        let permission = XCUIApplication(bundleIdentifier:"com.apple.springboard").alerts.buttons["Allow While Using App"]
        if permission.waitForExistence(timeout:5) { permission.tap() }
        XCTAssertTrue(app.staticTexts["Recording"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["60"].waitForExistence(timeout:5))
        // A validated scanner response starts recording without an extra tap.
        XCTAssertTrue(app.buttons["Finish & save"].waitForExistence(timeout:3))
        XCTAssertTrue(app.staticTexts["1726"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Locked design — synthetic TCP scanner readings"; shot.lifetime = .keepAlways; add(shot)
        // Exercise Core Location itself, including delivery while backgrounded.
        // These public coordinates are synthetic fixtures, never a real trip.
        defer { XCUIDevice.shared.location = nil }
        func locate(_ latitude: Double) {
            XCUIDevice.shared.location = XCUILocation(location:CLLocation(
                coordinate:CLLocationCoordinate2D(latitude:latitude,longitude:-124),
                altitude:0,horizontalAccuracy:5,verticalAccuracy:5,timestamp:Date()))
        }
        locate(49)
        try await Task.sleep(for:.seconds(2))
        XCUIDevice.shared.press(.home)
        locate(49.0002)
        try await Task.sleep(for:.seconds(2))
        locate(49.0004)
        try await Task.sleep(for:.seconds(2))
        app.activate()
        let liveMap = app.otherElements["live.route"]
        XCTAssertTrue(liveMap.waitForExistence(timeout:5))
        let routeGrew = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            let count = (liveMap.value as? String)?.split(separator:" ").first.flatMap { Int($0) } ?? 0
            return count >= 3
        },object:nil)
        await fulfillment(of:[routeGrew],timeout:10)
        XCTAssertTrue(liveMap.otherElements["Latest recorded location"].exists || liveMap.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","Latest recorded location")).firstMatch.exists)
        let finish = app.buttons["Finish & save"]
        let finishFrame = finish.frame
        XCTAssertLessThan(liveMap.frame.maxY,finishFrame.minY)
        let liveShot = XCTAttachment(screenshot:app.screenshot()); liveShot.name = "Live route and latest GPS fix — synthetic scanner recording"; liveShot.lifetime = .keepAlways; add(liveShot)
        let content = app.scrollViews["record.content"]
        // The actual 1726 RPM fixture value is asserted above. Scroll the cards
        // for visual evidence without depending on lazy-grid container IDs,
        // which hosted simulator accessibility trees may omit off screen.
        content.swipeUp()
        XCTAssertEqual(finish.frame.minY,finishFrame.minY,accuracy:1)
        let cardsShot = XCTAttachment(screenshot:app.screenshot()); cardsShot.name = "Live cards and fixed Finish control with recording map"; cardsShot.lifetime = .keepAlways; add(cardsShot)
        XCTAssertTrue(finish.waitForExistence(timeout:5))
        XCTAssertTrue(finish.isHittable)
        // After foregrounding, the hosted simulator returned a stale hit point
        // on the Drive tab for this button. Use its current frame centre and
        // verify the saved state before navigating away.
        finish.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        guard app.buttons["Start recording"].waitForExistence(timeout:10) else {
            XCTFail("Finish did not save the scanner recording. " + app.debugDescription)
            return
        }
        app.buttons["Drives"].tap()
        XCTAssertTrue(app.staticTexts["Scanner drive"].waitForExistence(timeout:5))
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Scanner drive")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Measured OBD responses"].waitForExistence(timeout:5))
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertFalse(app.staticTexts["This recording has no GPS route."].exists)
        let routeShot = XCTAttachment(screenshot:app.screenshot()); routeShot.name = "Synthetic GPS route recorded with scanner and background delivery"; routeShot.lifetime = .keepAlways; add(routeShot)
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
        // Return dismisses native and third-party keyboards, then exercise all
        // four reviewable onboarding stages before committing the draft.
        app.textFields["vehicle.model"].typeText("\n")
        for _ in 0..<3 {
            let next=app.buttons["Continue"]
            XCTAssertTrue(next.waitForExistence(timeout:5))
            let form=app.scrollViews["onboarding.form"]
            for _ in 0..<6 where !next.isHittable { form.swipeUp() }
            next.tap()
        }
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
            !app.buttons["onboarding.save"].exists && app.keyboards.count == 0 && app.buttons["Garage"].isHittable
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
