import XCTest
@testable import CANConnect

final class CoreTests: XCTestCase {
    private let start = Date(timeIntervalSince1970:1_700_000_000)
    func testSignalSlotsAreIndependentAndAllowDuplicates() {
        var p = Preferences()
        p.signals["drive.0"] = .voltage
        p.signals["engine.0"] = .voltage
        XCTAssertEqual(p.signals["drive.0"],.voltage)
        XCTAssertEqual(p.signals["engine.0"],.voltage)
        XCTAssertEqual(p.signals["drive.1"],.boost)
        XCTAssertEqual(p.signals["economy.3"],.voltage)
    }
    func testGPSRejectsPoorAccuracyAndJumps() {
        var draft = RecordingDraft(source:.phoneGPS,startedAt:start,updatedAt:start)
        func point(_ lat: Double, _ seconds: Double, accuracy: Double = 5) -> RoutePoint { RoutePoint(latitude:lat,longitude:-123.95,timestamp:start.addingTimeInterval(seconds),accuracy:accuracy,speed:10) }
        draft.accept(point(49.18,0))
        draft.accept(point(49.181,10,accuracy:100))
        draft.accept(point(50,10))
        XCTAssertEqual(draft.route.count,1)
        draft.accept(point(49.181,10))
        XCTAssertEqual(draft.route.count,2)
        XCTAssertEqual(draft.distanceKM,0.1112,accuracy:0.002)
        draft.accept(point(49.182,60)) // don't invent distance across a GPS outage
        XCTAssertEqual(draft.distanceKM,0.1112,accuracy:0.002)
    }
    func testGPSDoesNotInventVehicleReadings() {
        let trip = RecordingDraft(source:.phoneGPS,startedAt:start,updatedAt:start).trip(endedAt:start.addingTimeInterval(30))
        XCTAssertNil(trip.economy); XCTAssertNil(trip.fuelLitres); XCTAssertFalse(trip.isSample)
        XCTAssertEqual(trip.duration,30)
    }
    func testPartialFillsIncludedBetweenFullFills() {
        func entry(_ odo: Double, _ litres: Double, _ full: Bool, sample: Bool = false) -> FuelEntry { FuelEntry(date:start,litres:litres,costCAD:20,odometerKM:odo,full:full,isSample:sample) }
        let entries = [entry(1000,40,true),entry(1200,10,false),entry(1600,20,true),entry(1700,90,true,sample:true)]
        XCTAssertEqual(FuelMath.latestEconomy(entries) ?? 0,5,accuracy:0.001)
        XCTAssertNil(FuelMath.latestEconomy([entry(1000,40,true)]))
    }
    func testArchiveRoundTripAndValidation() throws {
        let original = TripArchive(trips:SampleData.state(now:start).trips)
        let decoded = try TripArchive.decode(original.encoded())
        XCTAssertEqual(decoded.trips.count,5)
        XCTAssertEqual(decoded.trips[0].distanceKM,24.8)
        var invalid = original; invalid.schemaVersion = 99
        XCTAssertThrowsError(try TripArchive.decode(invalid.encoded()))
        invalid = original; invalid.trips.append(original.trips[0])
        XCTAssertThrowsError(try TripArchive.decode(invalid.encoded()))
        invalid = original; invalid.trips[0].distanceKM = -1
        XCTAssertThrowsError(try TripArchive.decode(invalid.encoded()))
    }
    func testAtomicPersistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = LocalStore(url:directory.appendingPathComponent("state.json"))
        XCTAssertNil(try store.load())
        var state = SampleData.state(now:start); state.preferences.signals["drive.0"] = .voltage
        try store.save(state)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.trips,state.trips)
        XCTAssertEqual(loaded.preferences.signals["drive.0"],.voltage)
    }
    @MainActor func testCorruptStateIsPreservedReadOnlyAndRestoresOnlyValidatedBackup() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store=LocalStore(url:directory.appendingPathComponent("state.json"))
        var original=StoredState();original.onboardingCompleted=true
        try store.save(original)
        var newer=original;newer.server.address="http://127.0.0.1:8765"
        try store.save(newer)
        XCTAssertEqual(store.validBackup()?.server.address,original.server.address)
        try Data("{ corrupt synthetic state".utf8).write(to:store.url)
        let app=AppStore(disk:store,scannerAvailable:{_ in false})
        XCTAssertTrue(app.libraryReadOnly);XCTAssertTrue(app.backupAvailable)
        XCTAssertTrue(app.error?.contains("original bytes are preserved") == true)
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(at:store.recoveryURL,includingPropertiesForKeys:nil)).count >= 1)
        app.restoreStateBackup()
        XCTAssertFalse(app.libraryReadOnly);XCTAssertNil(app.error)
        XCTAssertEqual(try store.load()?.server.address,original.server.address)
    }
    func testInvalidBackupDoesNotReplaceCorruptPrimary() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store=LocalStore(url:directory.appendingPathComponent("state.json"))
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let corrupt=Data("synthetic corrupt primary".utf8)
        try corrupt.write(to:store.url);try Data("synthetic corrupt backup".utf8).write(to:store.backupURL)
        XCTAssertThrowsError(try store.restoreBackup())
        XCTAssertEqual(try Data(contentsOf:store.url),corrupt)
    }
    func testGPSWarmupRejectsCachedAndPoorFixesUntilFreshPoint() {
        let began = Date(timeIntervalSince1970:1_700_000_000)
        XCTAssertFalse(GPSRecorder.acceptsFix(timestamp:began.addingTimeInterval(-1),accuracy:9,beganAt:began,now:began.addingTimeInterval(1)))
        XCTAssertTrue(GPSRecorder.acceptsFix(timestamp:began.addingTimeInterval(1),accuracy:9,beganAt:began,now:began.addingTimeInterval(2)))
        XCTAssertFalse(GPSRecorder.acceptsFix(timestamp:began.addingTimeInterval(1),accuracy:51,beganAt:began,now:began.addingTimeInterval(2)))
        XCTAssertFalse(GPSRecorder.acceptsFix(timestamp:began.addingTimeInterval(1),accuracy:-1,beganAt:began,now:began.addingTimeInterval(2)))
        XCTAssertFalse(GPSRecorder.acceptsFix(timestamp:began.addingTimeInterval(1),accuracy:9,beganAt:began,now:began.addingTimeInterval(30)))
        XCTAssertEqual(GPSRecorder.bestLimitedAccuracy([(began.addingTimeInterval(1),84),(began.addingTimeInterval(1),63)],beganAt:began,now:began.addingTimeInterval(2)),63)
        XCTAssertNil(GPSRecorder.bestLimitedAccuracy([(began.addingTimeInterval(-1),80),(began.addingTimeInterval(1),40)],beganAt:began,now:began.addingTimeInterval(2)))
    }

}
