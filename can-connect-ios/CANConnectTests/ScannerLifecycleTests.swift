import XCTest
import UIKit
@testable import CANConnect

@MainActor
private final class LifecycleTransport: ScannerTransport {
    var available = true
    var noData = false
    var rpmReply = "410C0D00"
    var opens = 0
    var disconnects = 0
    var vin: String?
    func open(host: String, port: UInt16) async throws -> ScannerIdentity {
        opens += 1
        guard available else { throw AppFailure("Synthetic ignition off") }
        return ScannerIdentity(vin:vin,adapter:"SYNTHETIC LIFECYCLE",vehicleProtocol:"CAN",supportedPIDs:[12])
    }
    func command(_ text: String) async throws -> String {
        guard available else { throw AppFailure("Synthetic connection loss") }
        return noData ? "NO DATA" : rpmReply
    }
    func disconnect() { disconnects += 1 }
}

@MainActor
private final class ActivitySpy: RecordingActivityManaging {
    var snapshot: RecordingActivitySnapshot?
    var updates = 0
    func sync(_ snapshot: RecordingActivitySnapshot?, foreground: Bool) { self.snapshot = snapshot; updates += 1 }
}

final class ScannerLifecycleTests: XCTestCase {
    @MainActor func testTodayStartConnectsSavedScannerAndRecordsWithoutNavigation() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"));_ = try savedVehicle(disk)
        let transport=LifecycleTransport(),scanner=ScannerRecorder(engine:.legacy,makeSession:{transport})
        let store=AppStore(disk:disk,scanner:scanner,gps:GPSFixture(),scannerAvailable:{_ in false})
        XCTAssertEqual(store.source,.phoneGPS)
        store.startRecordingFromToday()
        await until("Today starts actual scanner recording") { store.recording }
        XCTAssertEqual(store.state.draft?.source,.scanner);XCTAssertEqual(store.selectedTab,.today)
        let id=store.state.draft?.id;store.startRecordingFromToday()
        XCTAssertEqual(store.state.draft?.id,id)
        store.finishRecording();await store.waitForFinish();store.disconnectScanner()
    }
    @MainActor func testTodayStartsGPSImmediatelyWithoutScannerAndWithoutNavigation() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"))
        let vehicle=VehicleProfile();var state=StoredState();state.vehicles=[vehicle];state.selectedVehicleID=vehicle.id
        try disk.save(state)
        let store=AppStore(disk:disk,gps:GPSFixture(),scannerAvailable:{_ in false})
        store.startRecordingFromToday()
        XCTAssertTrue(store.recording);XCTAssertEqual(store.state.draft?.source,.phoneGPS)
        XCTAssertEqual(store.selectedTab,.today)
    }

    @MainActor func testExplicitRetryAtSixtyAndNinetySecondsDoesNotAdvanceLossDeadline() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"));_ = try savedVehicle(disk)
        let transport=LifecycleTransport(),scanner=ScannerRecorder(makeSession:{transport})
        let store=AppStore(disk:disk,scanner:scanner,gps:GPSFixture(),scannerAvailable:{_ in true})
        await until("recording") { store.recording }
        transport.available=false
        await until("lost scanner") { !scanner.connected }
        let draft=try XCTUnwrap(store.state.draft),deadline=try XCTUnwrap(draft.scannerReconnectDeadline)
        for remaining in [60.0,30.0] {
            for _ in 0..<3 { store.retryScannerNow(at:deadline.addingTimeInterval(-remaining)) }
            XCTAssertEqual(store.state.draft?.id,draft.id)
            XCTAssertEqual(store.state.draft?.scannerReconnectDeadline,deadline)
            await until("failed retry") { !scanner.connecting }
        }
        store.retryScannerNow(at:deadline)
        await store.waitForFinish()
        XCTAssertNil(store.state.draft)
        XCTAssertEqual(store.state.trips.filter{$0.id == draft.id}.count,1)
        store.disconnectScanner()
    }
    @MainActor
    private func until(_ description: String, _ condition: @escaping () -> Bool) async {
        let wait = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in condition() },object:nil)
        await fulfillment(of:[wait],timeout:5)
    }
    @MainActor
    private func savedVehicle(_ disk: LocalStore, settings: ScannerSettings = ScannerSettings(transport:.obdLinkMXPlus,accessorySerial:"FIXTURE")) throws -> VehicleProfile {
        var vehicle = VehicleProfile(); vehicle.make = "Test"; vehicle.model = "Synthetic lifecycle"
        vehicle.scannerConnection = settings
        var state = StoredState(); state.vehicles = [vehicle]; state.selectedVehicleID = vehicle.id; state.onboardingCompleted = true
        try disk.save(state); return vehicle
    }
    @MainActor
    func testLaunchAutoConnectFirstSampleAutoRecordsAndBackgroundKeepsSameDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk = LocalStore(url:root.appendingPathComponent("state.json"))
        let vehicle = try savedVehicle(disk)
        let transport = LifecycleTransport(), activity = ActivitySpy(), gps = GPSFixture()
        let scanner = ScannerRecorder(makeSession:{transport})
        let store = AppStore(disk:disk,scanner:scanner,activity:activity,gps:gps,scannerAvailable:{ _ in true })
        defer { store.disconnectScanner() }
        await until("automatic recording") { store.recording }
        let first = try XCTUnwrap(store.state.draft)
        XCTAssertEqual(first.vehicleID,vehicle.id); XCTAssertEqual(first.scannerTransport,.obdLinkMXPlus)
        XCTAssertEqual(first.samples?.first?.signals["rpm"],832)
        XCTAssertEqual(activity.snapshot?.id,first.id)
        XCTAssertEqual(gps.starts,1,"Automatic scanner recording also starts GPS")
        let point = RoutePoint(latitude:49,longitude:-124,timestamp:Date(),accuracy:5,speed:nil)
        gps.onPoint?(point)
        let disconnects = transport.disconnects
        NotificationCenter.default.post(name:UIApplication.didEnterBackgroundNotification,object:nil)
        XCTAssertEqual(try disk.load()?.draft?.id,first.id)
        XCTAssertEqual(try disk.load()?.draft?.route,[point])
        await until("fresh response after app switching") { (store.state.draft?.samples?.count ?? 0) > (first.samples?.count ?? 0) }
        XCTAssertEqual(store.state.draft?.id,first.id); XCTAssertTrue(scanner.connected)
        XCTAssertEqual(transport.disconnects,disconnects)
        store.tick(Date().addingTimeInterval(6))
        XCTAssertEqual(try disk.load()?.draft?.samples,store.state.draft?.samples)
        #if !targetEnvironment(simulator)
        let protection = try FileManager.default.attributesOfItem(atPath:disk.url.path)[.protectionKey] as? FileProtectionType
        XCTAssertEqual(protection,.completeUntilFirstUserAuthentication)
        #endif
        gps.onFailure?("Synthetic location permission revoked")
        XCTAssertTrue(store.recording); XCTAssertNil(store.error)
        XCTAssertEqual(store.state.draft?.id,first.id)
        store.finishRecording()
        await store.waitForFinish()
        XCTAssertEqual(gps.stops,1)
        XCTAssertEqual(try disk.load()?.trips.first?.route,[point])
        XCTAssertNil(activity.snapshot)
        let count = store.state.trips.count
        try await Task.sleep(nanoseconds:650_000_000)
        XCTAssertFalse(store.recording,"Finish must not immediately auto-start another draft")
        XCTAssertEqual(store.state.trips.count,count)
        store.startRecording(); XCTAssertTrue(store.recording,"Manual Start remains available")
        XCTAssertEqual(gps.starts,2,"Manual scanner recording also starts GPS")
        store.finishRecording()
        await store.waitForFinish()
    }
    @MainActor
    func testLossKeepsGPSAndBackoffReconnectResumesSameTripAndManualCancelStaysCancelled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk = LocalStore(url:root.appendingPathComponent("state.json")); _ = try savedVehicle(disk)
        let transport = LifecycleTransport(); var accessory = true
        let scanner = ScannerRecorder(makeSession:{transport})
        let gps = GPSFixture()
        let store = AppStore(disk:disk,scanner:scanner,activity:ActivitySpy(),gps:gps,scannerAvailable:{ _ in accessory })
        defer { store.disconnectScanner() }
        await until("first recording") { store.recording }
        let firstID = store.state.draft?.id
        transport.available = false
        await until("scanner disconnected") { !scanner.connected }
        XCTAssertTrue(store.recording); XCTAssertTrue(store.state.trips.isEmpty)
        XCTAssertEqual(gps.stops,0)
        let sampleCount = store.state.draft?.samples?.count ?? 0
        let point = RoutePoint(latitude:49,longitude:-124,timestamp:Date(),accuracy:5,speed:10)
        gps.onPoint?(point)
        XCTAssertEqual(store.state.draft?.route,[point])
        XCTAssertNil(store.error,"Ignition loss must save quietly without a popup")
        let attempts = transport.opens
        store.reconcileScannerConnection(at:Date())
        XCTAssertEqual(transport.opens,attempts,"Do not spin on failed connections")
        transport.available = true
        store.reconcileScannerConnection(at:Date().addingTimeInterval(61))
        await until("automatic reconnect") { scanner.connected && (store.state.draft?.samples?.count ?? 0) > sampleCount }
        XCTAssertEqual(store.state.draft?.id,firstID)
        XCTAssertEqual(gps.starts,1); XCTAssertEqual(gps.stops,0)
        XCTAssertEqual(store.state.draft?.route,[point])
        store.finishRecording(); store.disconnectScanner()
        await store.waitForFinish()
        let afterCancel = transport.opens
        for _ in 0..<5 { store.reconcileScannerConnection(at:Date().addingTimeInterval(300)) }
        try await Task.sleep(nanoseconds:100_000_000)
        XCTAssertEqual(transport.opens,afterCancel)
        accessory = false; store.reconcileScannerConnection(at:Date())
        accessory = true; store.reconcileScannerConnection(at:Date())
        await until("next accessory connection rearms automation") { store.recording }
        store.finishRecording()
        await store.waitForFinish()
    }
    @MainActor
    func testWrongVINAndNoDataDoNotCreateAutomaticTrips() async throws {
        for mismatch in [true,false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:root) }
            let disk = LocalStore(url:root.appendingPathComponent("state.json")); var vehicle = try savedVehicle(disk)
            vehicle.vin = "1D4GP00R55B123456"
            var state = try XCTUnwrap(disk.load()); state.vehicles = [vehicle]; try disk.save(state)
            let transport = LifecycleTransport(); transport.vin = mismatch ? "1D4GP00R55B123457" : vehicle.vin
            transport.noData = !mismatch
            let scanner = ScannerRecorder(makeSession:{transport})
            let store = AppStore(disk:disk,scanner:scanner,activity:ActivitySpy(),gps:GPSFixture(),scannerAvailable:{ _ in true })
            defer { store.disconnectScanner() }
            await until("failed identification or no ECU data") { !scanner.status.isEmpty && !scanner.connecting && transport.opens > 0 && !scanner.connected }
            if mismatch { XCTAssertTrue(store.error?.contains("VIN differs") == true) }
            else { XCTAssertNil(store.error,"No data with ignition off is a quiet connection status") }
            XCTAssertFalse(store.recording); XCTAssertTrue(store.state.trips.isEmpty)
        }
    }
    @MainActor
    func testAutomaticAndExplicitStartupTimeoutsRemainInStatusWithoutAlerts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk = LocalStore(url:root.appendingPathComponent("state.json"))
        let vehicle = try savedVehicle(disk)
        let transport = LifecycleTransport(); transport.available = false
        let scanner = ScannerRecorder(makeSession:{transport})
        let store = AppStore(disk:disk,scanner:scanner,activity:ActivitySpy(),gps:GPSFixture(),scannerAvailable:{ _ in true })
        defer { store.disconnectScanner() }
        await until("automatic startup fails") { transport.opens == 1 && !scanner.connecting }
        XCTAssertNil(store.error)
        XCTAssertEqual(scanner.status,"Synthetic ignition off")
        store.reconcileScannerConnection(at:Date().addingTimeInterval(61))
        await until("automatic retry fails quietly") { transport.opens == 2 && !scanner.connecting }
        XCTAssertNil(store.error); XCTAssertTrue(store.state.trips.isEmpty)
        try store.connectScanner(settings:try XCTUnwrap(vehicle.scannerConnection))
        await until("explicit startup fails quietly") { transport.opens == 3 && !scanner.connecting }
        XCTAssertNil(store.error)
        XCTAssertEqual(scanner.status,"Synthetic ignition off")
    }
    @MainActor
    func testSavedWiFiAndOtherActiveSourcesAreNotAutomaticallyReplaced() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk = LocalStore(url:root.appendingPathComponent("state.json"))
        _ = try savedVehicle(disk,settings:ScannerSettings(host:"127.0.0.1",port:35000))
        let transport = LifecycleTransport(), scanner = ScannerRecorder(makeSession:{transport})
        let store = AppStore(disk:disk,scanner:scanner,activity:ActivitySpy(),gps:GPSFixture(),scannerAvailable:{ _ in true })
        store.reconcileScannerConnection(at:Date()); XCTAssertEqual(transport.opens,0)
        store.state.vehicles[0].scannerConnection = ScannerSettings(transport:.obdLinkMXPlus)
        store.pendingGPS = true; store.reconcileScannerConnection(at:Date())
        XCTAssertEqual(transport.opens,0)
        store.pendingGPS = false
        store.state.draft = RecordingDraft(source:.phoneGPS,startedAt:Date(),updatedAt:Date())
        store.reconcileScannerConnection(at:Date()); XCTAssertEqual(transport.opens,0)
        store.finishRecording(); store.disconnectScanner()
        await store.waitForFinish()
    }
    @MainActor
    func testStorageFailurePreservesDraftAndBlocksAutomaticReconnect() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk = LocalStore(url:root.appendingPathComponent("state.json")); _ = try savedVehicle(disk)
        let transport = LifecycleTransport(), scanner = ScannerRecorder(makeSession:{transport})
        let store = AppStore(disk:disk,scanner:scanner,activity:ActivitySpy(),gps:GPSFixture(),scannerAvailable:{ _ in true })
        defer { store.disconnectScanner() }
        await until("recording before storage failure") { store.recording }
        let id = store.state.draft?.id
        // A regular file obstructing the directory deterministically models a
        // write failure without changing actual device storage or permissions.
        try FileManager.default.removeItem(at:root)
        try Data("SYNTHETIC write failure".utf8).write(to:root)
        transport.available = false
        await until("scanner disconnect") { !scanner.connected }
        store.finishRecording()
        await store.waitForFinish()
        XCTAssertTrue(store.recording); XCTAssertEqual(store.state.draft?.id,id)
        XCTAssertTrue(store.error?.contains("Could not save the recording") == true)
        let attempts = transport.opens
        store.reconcileScannerConnection(at:Date().addingTimeInterval(300))
        XCTAssertEqual(transport.opens,attempts)
        try FileManager.default.removeItem(at:root)
        store.finishRecording()
        await store.waitForFinish()
        XCTAssertFalse(store.recording); XCTAssertEqual(try disk.load()?.trips.first?.id,id)
    }
    @MainActor
    func testIgnitionOnlyStartsAutomaticallyAndZeroRPMNeverFinishes() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"));_ = try savedVehicle(disk)
        let transport=LifecycleTransport();transport.rpmReply="410C0000"
        let scanner=ScannerRecorder(makeSession:{transport}),gps=GPSFixture()
        let store=AppStore(disk:disk,scanner:scanner,activity:ActivitySpy(),gps:gps,scannerAvailable:{_ in true})
        defer { store.disconnectScanner() }
        await until("ignition-only automatic recording") { store.recording }
        let id=try XCTUnwrap(store.state.draft?.id),start=Date()
        scanner.onSample?(OBDSample(timestamp:start,signals:["rpm":800],command:"010C",reply:"SYNTHETIC"))
        for second in 1...20 {
            scanner.onSample?(OBDSample(timestamp:start.addingTimeInterval(Double(second)),signals:["speedKph":0,"rpm":0],command:"010C",reply:"SYNTHETIC"))
        }
        XCTAssertTrue(store.recording);XCTAssertEqual(store.state.draft?.id,id)
        store.finishRecording();await store.waitForFinish()
        try await Task.sleep(for:.milliseconds(600))
        XCTAssertFalse(store.recording,"Manual Finish must not immediately restart on continuing data")
    }
    @MainActor
    func testConfirmedBluetoothLossFinalizesAfterShortGrace() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"));_ = try savedVehicle(disk)
        let transport=LifecycleTransport();transport.rpmReply="410C0000"
        var available=true
        let scanner=ScannerRecorder(makeSession:{transport})
        let store=AppStore(disk:disk,scanner:scanner,activity:ActivitySpy(),gps:GPSFixture(),scannerAvailable:{_ in available})
        defer { store.disconnectScanner() }
        await until("automatic start") { store.recording }
        let id=try XCTUnwrap(store.state.draft?.id),last=try XCTUnwrap(store.state.draft?.samples?.last?.timestamp)
        available=false;let loss=Date();store.reconcileScannerConnection(at:loss)
        XCTAssertEqual(store.state.draft?.scannerReconnectDeadline,loss.addingTimeInterval(10))
        store.reconcileScannerConnection(at:loss.addingTimeInterval(9));XCTAssertTrue(store.recording)
        store.reconcileScannerConnection(at:loss.addingTimeInterval(10));await store.waitForFinish()
        XCTAssertFalse(store.recording);let trip=try XCTUnwrap(store.state.trips.first)
        XCTAssertEqual(trip.id,id);XCTAssertEqual(trip.startedAt.addingTimeInterval(trip.duration),last)
        available=true;store.reconcileScannerConnection(at:Date())
        await until("next ignition-only recording") { store.recording }
        XCTAssertNotEqual(store.state.draft?.id,id)
    }
    @MainActor
    func testExpiredGapDropsUnconfirmedWalkingAndDoesNotStartFromGPS() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk = LocalStore(url:root.appendingPathComponent("state.json")); _ = try savedVehicle(disk)
        let transport = LifecycleTransport(), scanner = ScannerRecorder(makeSession:{transport}), gps = GPSFixture()
        var available = true
        let store = AppStore(disk:disk,scanner:scanner,activity:ActivitySpy(),gps:gps,scannerAvailable:{ _ in available })
        defer { store.disconnectScanner() }
        await until("recording") { store.recording }
        transport.available = false; available = false
        await until("lost scanner") { !scanner.connected }
        let draft = try XCTUnwrap(store.state.draft), end = try XCTUnwrap(draft.samples?.last?.timestamp)
        let walk = RoutePoint(latitude:49,longitude:-124,timestamp:end.addingTimeInterval(30),accuracy:5,speed:1)
        gps.onPoint?(walk)
        XCTAssertEqual(store.state.draft?.route,[walk])
        store.tick(end.addingTimeInterval(121))
        await store.waitForFinish()
        XCTAssertFalse(store.recording); XCTAssertEqual(gps.stops,1)
        let saved = try XCTUnwrap(store.state.trips.first)
        XCTAssertEqual(saved.id,draft.id); XCTAssertTrue(saved.route.isEmpty)
        XCTAssertEqual(saved.duration,end.timeIntervalSince(draft.startedAt),accuracy:0.001)
        gps.onPoint?(walk); store.tick(end.addingTimeInterval(300))
        XCTAssertFalse(store.recording); XCTAssertEqual(store.state.trips.count,1)
        transport.available = true; available = true
        store.reconcileScannerConnection(at:Date().addingTimeInterval(300))
        await until("fresh engine starts separate trip after expired gap") { store.recording }
        XCTAssertNotEqual(store.state.draft?.id,draft.id)
    }
    @MainActor
    func testUnboundAdapterAndUnknownVINCannotAutomaticallyRecord() async throws {
        for unknownVIN in [true,false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:root) }
            let disk = LocalStore(url:root.appendingPathComponent("state.json"))
            var vehicle = try savedVehicle(disk,settings:ScannerSettings(transport:.obdLinkMXPlus,accessorySerial:unknownVIN ? "FIXTURE" : nil))
            vehicle.vin = "1D4GP00R55B123456"
            var state = try XCTUnwrap(disk.load()); state.vehicles = [vehicle]; try disk.save(state)
            let transport = LifecycleTransport(), scanner = ScannerRecorder(makeSession:{transport}), gps = GPSFixture()
            let store = AppStore(disk:disk,scanner:scanner,activity:ActivitySpy(),gps:gps,scannerAvailable:{ _ in true })
            defer { store.disconnectScanner() }
            if unknownVIN { await until("VIN unavailable") { transport.opens > 0 && !scanner.connecting } }
            else { try await Task.sleep(nanoseconds:100_000_000); XCTAssertEqual(transport.opens,0) }
            XCTAssertFalse(store.recording); XCTAssertEqual(gps.starts,0)
        }
    }
    @MainActor
    func testFailedReconnectDoesNotExtendGapAndWrongVehicleCannotAppend() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk = LocalStore(url:root.appendingPathComponent("state.json")); var vehicle = try savedVehicle(disk)
        vehicle.vin = "1D4GP00R55B123456"
        var state = try XCTUnwrap(disk.load()); state.vehicles = [vehicle]; try disk.save(state)
        let transport = LifecycleTransport(); transport.vin = vehicle.vin
        let scanner = ScannerRecorder(makeSession:{transport}), gps = GPSFixture()
        let store = AppStore(disk:disk,scanner:scanner,activity:ActivitySpy(),gps:gps,scannerAvailable:{ _ in true })
        defer { store.disconnectScanner() }
        await until("first trip") { store.recording }
        transport.available = false
        await until("lost ECU") { !scanner.connected }
        let before = try XCTUnwrap(store.state.draft), deadline = try XCTUnwrap(before.scannerReconnectDeadline)
        transport.available = true; transport.vin = "1D4GP00R55B123457"
        store.reconcileScannerConnection(at:Date().addingTimeInterval(61))
        await until("wrong vehicle rejected") { transport.opens > 1 && !scanner.connecting }
        XCTAssertFalse(scanner.connected)
        XCTAssertEqual(store.state.draft?.id,before.id)
        XCTAssertEqual(store.state.draft?.samples,before.samples)
        XCTAssertEqual(store.state.draft?.scannerReconnectDeadline,deadline)
        store.tick(deadline.addingTimeInterval(1))
        await store.waitForFinish()
        XCTAssertFalse(store.recording); XCTAssertEqual(store.state.trips.first?.id,before.id)
    }
    @MainActor
    func testRecoveryAfterDisconnectExcludesUnconfirmedRouteAndDoesNotStartGPS() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk = LocalStore(url:root.appendingPathComponent("state.json")); _ = try savedVehicle(disk)
        let t = Date().addingTimeInterval(-300)
        var state = try XCTUnwrap(disk.load())
        var draft = RecordingDraft(vehicleID:state.selectedVehicleID,source:.scanner,startedAt:t,updatedAt:t)
        draft.accept(OBDSample(timestamp:t,signals:["rpm":800],command:"010C",reply:"SYNTHETIC"))
        draft.scannerReconnectDeadline = t.addingTimeInterval(120)
        draft.accept(RoutePoint(latitude:49,longitude:-124,timestamp:t.addingTimeInterval(60),accuracy:5,speed:1))
        state.draft = draft; try disk.save(state)
        let gps = GPSFixture()
        let store = AppStore(disk:disk,activity:ActivitySpy(),gps:gps,scannerAvailable:{ _ in false })
        XCTAssertFalse(store.recording); XCTAssertEqual(gps.starts,0)
        XCTAssertEqual(store.state.trips.first?.id,draft.id)
        XCTAssertTrue(store.state.trips.first?.route.isEmpty == true)
        XCTAssertEqual(store.state.trips.first?.duration,0)
    }
    func testEngineOffNeedsRepeatedFreshZeroRPMAndStoppedVehicle() {
        let t = Date(timeIntervalSince1970:1700000000)
        func sample(_ seconds: Double, _ signals: [String:Double]) -> OBDSample {
            OBDSample(timestamp:t.addingTimeInterval(seconds),signals:signals,command:"010C",reply:"SYNTHETIC")
        }
        var boundary = ScannerTripBoundary()
        XCTAssertFalse(boundary.engineOff(after:sample(0,["rpm":0])))
        XCTAssertFalse(boundary.engineOff(after:sample(1,["speedKph":0])))
        XCTAssertFalse(boundary.engineOff(after:sample(2,["rpm":0])))
        XCTAssertFalse(boundary.engineOff(after:sample(3,["rpm":800])))
        XCTAssertFalse(boundary.engineOff(after:sample(4,["rpm":0])))
        XCTAssertFalse(boundary.engineOff(after:sample(5,["speedKph":20])))
        XCTAssertFalse(boundary.engineOff(after:sample(8,["rpm":0])))
        boundary.reset()
        XCTAssertFalse(boundary.engineOff(after:sample(8.5,["rpm":800])))
        XCTAssertFalse(boundary.engineOff(after:sample(9,["speedKph":0,"rpm":0])))
        XCTAssertFalse(boundary.engineOff(after:sample(30,["speedKph":0,"rpm":0])))
        XCTAssertTrue(boundary.engineOff(after:sample(33,["rpm":0])))
        XCTAssertFalse(ScannerTripBoundary.engineRunning(sample(0,["speedKph":30])))
        XCTAssertFalse(ScannerTripBoundary.engineRunning(sample(0,["rpm":0])))
    }
    @MainActor
    func testManualIgnitionOnlyRecordingSurvivesAppSwitchAndZeroRPM() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"));_ = try savedVehicle(disk)
        let transport=LifecycleTransport();transport.rpmReply="410C0000"
        let scanner=ScannerRecorder(makeSession:{transport}),gps=GPSFixture()
        let store=AppStore(disk:disk,scanner:scanner,activity:ActivitySpy(),gps:gps,scannerAvailable:{_ in true})
        defer { store.disconnectScanner() }
        await until("ignition-only connection") { scanner.connected }
        await until("automatic ignition-only recording") { store.recording }
        store.finishRecording();await store.waitForFinish()
        store.source = .scanner;store.startRecording()
        let id=try XCTUnwrap(store.state.draft?.id),start=Date()
        NotificationCenter.default.post(name:UIApplication.didEnterBackgroundNotification,object:nil)
        for second in 0...20 {
            scanner.onSample?(OBDSample(timestamp:start.addingTimeInterval(Double(second)),signals:["speedKph":0,"rpm":0],command:"010C",reply:"SYNTHETIC"))
        }
        NotificationCenter.default.post(name:UIApplication.didBecomeActiveNotification,object:nil)
        XCTAssertTrue(store.recording);XCTAssertEqual(store.state.draft?.id,id)
        XCTAssertFalse(store.state.trips.contains(where:{$0.id == id}));XCTAssertTrue(scanner.connected)
        XCTAssertEqual(gps.stops,1)
        store.finishRecording();await store.waitForFinish()
        XCTAssertEqual(store.state.trips.first?.id,id)
    }
    func testLiveActivitySnapshotUsesOnlyRealCountsAndElapsedTime() {
        let date = Date(timeIntervalSince1970:1700000000)
        var draft = RecordingDraft(source:.scanner,startedAt:date,updatedAt:date,scannerTransport:.obdLinkMXPlus)
        draft.accept(OBDSample(timestamp:date.addingTimeInterval(65),signals:["rpm":832],command:"010C",reply:"SYNTHETIC"))
        let live = RecordingActivitySnapshot(draft:draft,scannerConnected:true)
        XCTAssertEqual(live.state.responses,1); XCTAssertEqual(live.state.elapsedText,"01:05")
        XCTAssertEqual(live.state.status,"Recording"); XCTAssertTrue(live.source.contains("MX+"))
        XCTAssertEqual(RecordingActivitySnapshot(draft:draft,scannerConnected:false).state.status,"Scanner disconnected")
    }
}
