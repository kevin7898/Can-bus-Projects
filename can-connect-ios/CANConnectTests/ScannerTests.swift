import XCTest
@testable import CANConnect

@MainActor
private final class FixtureScanner: ScannerTransport {
    var vin: String? = nil
    var commandCount = 0
    var disconnected = false
    var noData = false
    var supported = [0x0C,0x0D,0x05]
    func open(host: String, port: UInt16) async throws -> ScannerIdentity { ScannerIdentity(vin:vin,adapter:"TEST FIXTURE",vehicleProtocol:"ISO 15765-4 CAN",supportedPIDs:supported) }
    func command(_ text: String) async throws -> String {
        commandCount += 1
        if noData { return "NO DATA\r>" }
        switch text { case "010C": return "41 0C 1A F8\r>"; case "010D": return "41 0D 3C\r>"; default: return "41 05 80\r>" }
    }
    func disconnect() { disconnected = true }
}
final class ScannerTests: XCTestCase {
    func testStandardDecodingAndRejectsMissingConflictingOrWrongPID() throws {
        XCTAssertEqual(OBDDecoder.decode("010C\r41 0C 1A F8\r>",pid:0x0C)?.signals["rpm"],1726)
        XCTAssertEqual(OBDDecoder.decode("410D3C",pid:0x0D)?.signals["speedKph"],60)
        XCTAssertEqual(OBDDecoder.decode("41 05 80",pid:5)?.signals["coolantC"],88)
        XCTAssertEqual(OBDDecoder.decode("41 42 36 B0",pid:0x42)?.signals["voltage"],14)
        XCTAssertEqual(OBDDecoder.decode("41 5E 00 64",pid:0x5E)?.signals["fuelRateLph"],5)
        for reply in ["NO DATA", "41 0C 1A", "41 0D 3C", "41 0C 1A F8\r41 0C 1B 00"] { XCTAssertNil(OBDDecoder.decode(reply,pid:0x0C)) }
    }
    func testRecordingsPreserveIndividualReadingsAndDoNotBridgeOutages() throws {
        let start = Date(timeIntervalSince1970:1_700_000_000.123)
        var draft = RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        for seconds in [0.0,5.0,30.0] { draft.accept(try XCTUnwrap(OBDDecoder.decode("41 0D 3C",pid:13,at:start.addingTimeInterval(seconds)))) }
        draft.accept(try XCTUnwrap(OBDDecoder.decode("41 05 80",pid:5,at:start.addingTimeInterval(31))))
        XCTAssertEqual(draft.distanceKM,60*5/3600,accuracy:0.0001)
        let trip = draft.trip(endedAt:start.addingTimeInterval(32))
        XCTAssertEqual(trip.samples?.count,4); XCTAssertNil(trip.fuelLitres); XCTAssertFalse(trip.isSample)
        XCTAssertNil(trip.samples?.last?.signals["speedKph"])
        let decoded = try TripArchive.decode(TripArchive(trips:[trip]).encoded()).trips[0]
        XCTAssertEqual(decoded.samples?.first?.timestamp.timeIntervalSince1970 ?? 0,start.timeIntervalSince1970,accuracy:0.001)
        XCTAssertEqual(decoded.samples?.first?.reply,"41 0D 3C")
    }
    func testFuelRequiresMeasuredRateAndAdequateCoverage() throws {
        let date = Date(timeIntervalSince1970:1_700_000_000)
        var draft = RecordingDraft(source:.scanner,startedAt:date,updatedAt:date)
        for seconds in stride(from:0.0,through:20.0,by:5.0) {
            draft.accept(OBDDecoder.decode("41 0D 3C",pid:13,at:date.addingTimeInterval(seconds))!)
            draft.accept(OBDDecoder.decode("41 5E 00 64",pid:94,at:date.addingTimeInterval(seconds))!)
        }
        let trip = draft.trip(endedAt:date.addingTimeInterval(20))
        XCTAssertEqual(try XCTUnwrap(trip.fuelLitres),5*20/3600,accuracy:0.0001)
        XCTAssertEqual(try XCTUnwrap(trip.economy),5*100/60,accuracy:0.001)
        XCTAssertNil(draft.trip(endedAt:date.addingTimeInterval(60)).fuelLitres)
    }
    @MainActor
    func testPollingFreshnessDisconnectAndVehicleBinding() async throws {
        let fixture = FixtureScanner(); let scanner = ScannerRecorder(makeSession:{fixture})
        var vehicle = VehicleProfile(); vehicle.make = "Test"; vehicle.model = "Fixture"
        let gotSamples = expectation(description:"decoded actual fixture responses"); gotSamples.expectedFulfillmentCount = 3; gotSamples.assertForOverFulfill = false
        scanner.onSample = { _ in gotSamples.fulfill() }
        scanner.connect(settings:ScannerSettings(host:"192.168.0.10",port:35000),vehicle:vehicle)
        await fulfillment(of:[gotSamples],timeout:3)
        XCTAssertTrue(scanner.connected); XCTAssertEqual(scanner.vehicleID,vehicle.id)
        XCTAssertEqual(scanner.value("rpm",at:Date()),1726)
        XCTAssertNil(scanner.value("rpm",at:Date().addingTimeInterval(11)))
        scanner.disconnect()
        XCTAssertNil(scanner.value("rpm",at:Date())); XCTAssertTrue(fixture.disconnected)
        XCTAssertFalse(scanner.connected)
    }
    @MainActor
    func testMismatchedVINNeverStartsPolling() async throws {
        let fixture = FixtureScanner(); fixture.vin = "1D4GP00R55B123456"
        let scanner = ScannerRecorder(makeSession:{fixture})
        var vehicle = VehicleProfile(); vehicle.vin = "1D4GP00R55B123457"
        let failed = expectation(description:"VIN mismatch")
        scanner.onDisconnect = { message in XCTAssertTrue(message.contains("VIN differs")); failed.fulfill() }
        scanner.connect(settings:ScannerSettings(host:"192.168.0.10",port:35000),vehicle:vehicle)
        await fulfillment(of:[failed],timeout:3)
        XCTAssertEqual(fixture.commandCount,0); XCTAssertFalse(scanner.connected)
    }
    @MainActor
    func testRecordingCheckpointsAndExpiredVehicleLossSavesRealSamples() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let fixture = FixtureScanner(); let scanner = ScannerRecorder(makeSession:{fixture})
        let disk = LocalStore(url:root.appendingPathComponent("state.json")); let store = AppStore(disk:disk,scanner:scanner,gps:GPSFixture())
        var vehicle = VehicleProfile(); vehicle.make = "Test"; vehicle.model = "Synthetic ECU"
        try store.saveVehicle(vehicle)
        try store.connectScanner(host:"192.168.0.10",port:35000)
        try await Task.sleep(nanoseconds:150_000_000)
        store.startRecording(); XCTAssertTrue(store.recording)
        XCTAssertThrowsError(try store.chooseVehicle(store.state.vehicles[0].id))
        let recorded = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in (store.state.draft?.samples?.count ?? 0) >= 2 },object:nil)
        await fulfillment(of:[recorded],timeout:3)
        store.tick(Date().addingTimeInterval(5))
        XCTAssertGreaterThan(try XCTUnwrap(disk.load()?.draft?.samples?.count),0)
        fixture.noData = true
        let stopped = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in !scanner.connected },object:nil)
        await fulfillment(of:[stopped],timeout:6)
        XCTAssertTrue(store.recording,"A transport loss keeps the trip during its reconnect grace")
        store.tick(Date().addingTimeInterval(121))
        await store.waitForFinish()
        XCTAssertFalse(store.recording)
        let trip = try XCTUnwrap(store.sortedTrips.first)
        XCTAssertEqual(trip.source,.scanner); XCTAssertFalse(trip.isSample)
        XCTAssertGreaterThan(trip.samples?.count ?? 0,0)
        XCTAssertEqual(try disk.load()?.trips.first?.id,trip.id)
    }
    @MainActor
    func testMXPlusRecordingRetainsTransportAndSourceResponses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let fixture = FixtureScanner(); let scanner = ScannerRecorder(makeSession:{fixture})
        let disk = LocalStore(url:root.appendingPathComponent("state.json")); let store = AppStore(disk:disk,scanner:scanner,gps:GPSFixture())
        var vehicle = VehicleProfile(); vehicle.make = "Test"; vehicle.model = "Synthetic MX+"
        try store.saveVehicle(vehicle)
        try store.connectScanner(settings:ScannerSettings(transport:.obdLinkMXPlus,accessorySerial:"SYNTHETIC"))
        let connected = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in scanner.connected },object:nil)
        await fulfillment(of:[connected],timeout:3)
        XCTAssertTrue(scanner.status.contains("MX+ Bluetooth"))
        store.startRecording()
        let samples = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in (store.state.draft?.samples?.count ?? 0) >= 3 },object:nil)
        await fulfillment(of:[samples],timeout:3)
        store.finishRecording(); scanner.disconnect()
        await store.waitForFinish()
        let trip = try XCTUnwrap(store.sortedTrips.first)
        XCTAssertEqual(trip.scannerTransport,.obdLinkMXPlus)
        XCTAssertEqual(trip.source,.scanner); XCTAssertFalse(trip.isSample)
        XCTAssertTrue(trip.samples?.contains(where:{$0.command == "010C" && $0.reply == "41 0C 1A F8\r>"}) ?? false)
        let archive = try TripArchive.decode(store.archive([trip]).encoded())
        XCTAssertEqual(archive.trips.first?.scannerTransport,.obdLinkMXPlus)
        let wire = try DriveLineArchive.decoded(MacRecording.encode(trip))
        XCTAssertEqual(wire.recordings.first?.metadata["scannerTransport"],ScannerConnectionKind.obdLinkMXPlus.rawValue)
        XCTAssertEqual(try disk.load()?.vehicles.last?.scannerConnection?.kind,.obdLinkMXPlus)
    }

}

@MainActor
private final class CancelledSessionFixture: ScannerTransport {
    enum Phase { case opening, command, replacement }
    let phase: Phase
    let entered: XCTestExpectation?
    var cleanupFinished = false
    var canOpen: (() -> Bool)?
    var openedBeforeCleanup = false
    init(_ phase: Phase, entered: XCTestExpectation? = nil) { self.phase = phase; self.entered = entered }
    private func pendingUntilCancelled() async throws {
        entered?.fulfill()
        do { try await Task.sleep(nanoseconds:10_000_000_000) }
        catch {
            // Model ownership held by an in-flight operation until its cancellation unwinds.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline:.now()+0.03) { continuation.resume() }
            }
            cleanupFinished = true
            throw CancellationError()
        }
    }
    func open(host: String, port: UInt16) async throws -> ScannerIdentity {
        if phase == .replacement { openedBeforeCleanup = !(canOpen?() ?? false) }
        if phase == .opening { try await pendingUntilCancelled() }
        return ScannerIdentity(vin:nil,adapter:"SYNTHETIC SESSION",vehicleProtocol:"ISO 15765-4 CAN",supportedPIDs:[12])
    }
    func command(_ text: String) async throws -> String {
        if phase == .command { try await pendingUntilCancelled() }
        return "410C0D00"
    }
    func disconnect() {}
}

extension ScannerTests {
    @MainActor
    func testCancelOpeningOrPendingReadBeforeImmediateReconnect() async throws {
        for (phase,explicitCancel) in [(CancelledSessionFixture.Phase.opening,false),(.opening,true),(.command,false),(.command,true)] {
            let entered=expectation(description:"first session entered pending operation")
            let first=CancelledSessionFixture(phase,entered:entered),next=CancelledSessionFixture(.replacement)
            next.canOpen = { first.cleanupFinished }
            var created=0
            let scanner=ScannerRecorder(makeSession:{ created+=1;return created==1 ? first:next })
            var vehicle=VehicleProfile();vehicle.make="Test";vehicle.model="Cancellation fixture"
            let settings=ScannerSettings(transport:.obdLinkMXPlus)
            scanner.connect(settings:settings,vehicle:vehicle)
            await fulfillment(of:[entered],timeout:2)
            let gotReplacement=expectation(description:"replacement supplies real fixture reply")
            gotReplacement.assertForOverFulfill=false
            scanner.onSample = { _ in gotReplacement.fulfill() }
            if explicitCancel { scanner.disconnect() }
            scanner.connect(settings:settings,vehicle:vehicle)
            await fulfillment(of:[gotReplacement],timeout:3)
            XCTAssertTrue(first.cleanupFinished)
            XCTAssertFalse(next.openedBeforeCleanup,"A replacement session must await old task teardown")
            XCTAssertTrue(scanner.connected);XCTAssertEqual(scanner.value("rpm",at:Date()),832)
            scanner.disconnect()
        }
    }
}
