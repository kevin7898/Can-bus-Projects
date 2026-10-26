import XCTest
import Combine
import UIKit
import CoreLocation
@testable import CANConnect

@MainActor
final class GPSFixture: GPSRecording {
    let objectWillChange = ObservableObjectPublisher()
    var speedKMH: Double?
    var lastFix: Date?
    var status = "Synthetic GPS"
    var onPoint: ((RoutePoint) -> Void)?
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var starts = 0
    var stops = 0
    func requestAutomaticAuthorization() {}
    func start() { starts += 1; onReady?() }
    func stop() { stops += 1 }
}

final class GPSRecordingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970:1_700_000_000.125)
    private func point(_ seconds: Double, _ latitude: Double = 49) -> RoutePoint {
        RoutePoint(latitude:latitude,longitude:-124,timestamp:start.addingTimeInterval(seconds),accuracy:5,speed:10)
    }
    func testScannerRouteDoesNotDoubleCountDistanceOrRegressCheckpointTime() throws {
        var draft = RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        draft.accept(OBDSample(timestamp:start,signals:["speedKph":36],command:"010D",reply:"SYNTHETIC"))
        draft.accept(point(0))
        draft.accept(point(10,49.001))
        draft.accept(OBDSample(timestamp:start.addingTimeInterval(5),signals:["speedKph":36],command:"010D",reply:"SYNTHETIC"))
        XCTAssertEqual(draft.updatedAt,start.addingTimeInterval(10),"Delayed OBD delivery cannot move the checkpoint backwards")
        draft.accept(point(6,49.0006)) // out-of-order GPS is rejected
        draft.accept(point(10,49.002)) // duplicate timestamp is rejected
        XCTAssertEqual(draft.route.count,2)
        XCTAssertEqual(draft.distanceKM,0.1112,accuracy:0.002,"The canonical policy prefers observed GPS distance without adding OBD distance")
        let trip = draft.trip(endedAt:start.addingTimeInterval(10))
        let restored = try XCTUnwrap(TripArchive.decode(TripArchive(trips:[trip]).encoded()).trips.first)
        XCTAssertEqual(restored.route,trip.route); XCTAssertEqual(restored.samples,trip.samples)
        let payload = try MacRecording.encode(restored)
        let attachment = XCTAttachment(data:payload,uniformTypeIdentifier:"public.json")
        attachment.name = "Synthetic mixed scanner GPS upload"; attachment.lifetime = .keepAlways; add(attachment)
        let wire = try DriveLineArchive.decoded(payload)
        let recording = try XCTUnwrap(wire.recordings.first)
        XCTAssertEqual(recording.gpsPoints.count,2); XCTAssertEqual(recording.signalSamples.count,2)
        XCTAssertEqual(recording.gpsPoints[1].latitude,49.001)
        XCTAssertEqual(recording.gpsPoints[1].timestamp,start.addingTimeInterval(10))
        XCTAssertNil(recording.signalSamples.first?.values["gpsSpeedMps"],"Do not turn GPS speed into an ECU measurement")
        XCTAssertEqual(try MacRecording.encode(restored),payload,"Transfer retries must use the same payload")
    }
    func testRouteMapSeparatesOutagesInsteadOfDrawingAnInventedRoad() {
        let route = [point(0),point(10,49.001),point(65,49.002),point(75,49.003)]
        XCTAssertEqual(RoutePoint.segments(route),[Array(route[0...1]),Array(route[2...3])])
        XCTAssertEqual(RoutePoint.segments([]),[])
        XCTAssertEqual(RoutePoint.segments([point(0)]),[[point(0)]])
    }
    @MainActor
    func testPhoneGPSStillStartsSavesAndStopsNormally() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let gps = GPSFixture(), disk = LocalStore(url:root.appendingPathComponent("state.json"))
        let store = AppStore(disk:disk,gps:gps,scannerAvailable:{_ in false})
        var vehicle = VehicleProfile(); vehicle.make = "Test"; vehicle.model = "Synthetic GPS"
        try store.saveVehicle(vehicle)
        store.source = .phoneGPS; store.startRecording()
        XCTAssertTrue(store.recording); XCTAssertFalse(store.pendingGPS); XCTAssertEqual(gps.starts,1)
        let began = try XCTUnwrap(store.state.draft?.startedAt)
        let point = RoutePoint(latitude:49,longitude:-124,timestamp:began,accuracy:5,speed:nil)
        gps.onPoint?(point)
        NotificationCenter.default.post(name:UIApplication.didEnterBackgroundNotification,object:nil)
        XCTAssertEqual(try disk.load()?.draft?.route,[point])
        store.finishRecording()
        await store.waitForFinish()
        XCTAssertEqual(store.state.trips.first?.route,[point]); XCTAssertEqual(gps.stops,1)
        gps.onPoint?(point)
        XCTAssertNil(store.state.draft)
    }
}

@MainActor
private final class LocationManagerFixture: CLLocationManager {
    var permission: CLAuthorizationStatus = .authorizedWhenInUse
    override var authorizationStatus: CLAuthorizationStatus { permission }
    var starts = 0
    var stops = 0
    var alwaysRequests = 0
    override func startUpdatingLocation() { starts += 1 }
    override func stopUpdatingLocation() { stops += 1 }
    override func requestAlwaysAuthorization() { alwaysRequests += 1 }
    override func requestWhenInUseAuthorization() {}
}

extension GPSRecordingTests {
    @MainActor
    func testBackgroundTripWaitsForForegroundAndResumesWithoutRestartingScanner() async {
        let manager = LocationManagerFixture()
        var foreground = false
        let gps = GPSRecorder(manager:manager,isForeground:{ foreground })
        var points: [RoutePoint] = []
        gps.onPoint = { points.append($0) }
        gps.start()
        XCTAssertEqual(manager.starts,0)
        XCTAssertTrue(gps.status.contains("GPS waiting"))
        XCTAssertEqual(manager.alwaysRequests,0,"Background recording cannot request broader permission")
        foreground = true
        NotificationCenter.default.post(name:UIApplication.didBecomeActiveNotification,object:nil)
        await Task.yield()
        XCTAssertEqual(manager.starts,1)
        let location = CLLocation(coordinate:CLLocationCoordinate2D(latitude:49,longitude:-124),altitude:0,horizontalAccuracy:4,verticalAccuracy:4,timestamp:Date())
        gps.locationManager(manager,didUpdateLocations:[location])
        XCTAssertEqual(points.count,1)
        foreground = false; gps.start()
        XCTAssertEqual(manager.starts,1,"A foreground-started session continues without restarting")
        gps.stop(); foreground = true
        NotificationCenter.default.post(name:UIApplication.didBecomeActiveNotification,object:nil)
        await Task.yield()
        XCTAssertEqual(manager.starts,1,"Finished trips cannot resume location collection")
    }
    @MainActor
    func testAlwaysPermissionAllowsSuccessiveBackgroundTripsAndRecoversAfterGrant() {
        let manager = LocationManagerFixture(); manager.permission = .authorizedAlways
        let gps = GPSRecorder(manager:manager,isForeground:{false})
        gps.start(); XCTAssertEqual(manager.starts,1)
        gps.stop(); gps.start(); XCTAssertEqual(manager.starts,2)
        manager.permission = .denied
        gps.locationManagerDidChangeAuthorization(manager)
        XCTAssertTrue(gps.status.contains("Location access is off"))
        manager.permission = .authorizedAlways
        gps.locationManagerDidChangeAuthorization(manager)
        XCTAssertEqual(manager.starts,3)
        gps.stop()
        gps.locationManagerDidChangeAuthorization(manager)
        XCTAssertEqual(manager.starts,3)
    }
    @MainActor
    func testWeakFixStaysUnrecordedAndRetryRestartsAcquisition() {
        let manager=LocationManagerFixture()
        let gps=GPSRecorder(manager:manager,isForeground:{true})
        gps.start()
        let weak=CLLocation(coordinate:CLLocationCoordinate2D(latitude:49,longitude:-124),altitude:0,
            horizontalAccuracy:84,verticalAccuracy:10,timestamp:Date())
        gps.locationManager(manager,didUpdateLocations:[weak])
        XCTAssertTrue(gps.status.contains("GPS signal weak"))
        XCTAssertNil(gps.lastFix,"A low-confidence location must not become recorded route evidence")
        gps.retry()
        XCTAssertEqual(manager.stops,1)
        XCTAssertEqual(manager.starts,2)
        XCTAssertEqual(gps.status,"Waiting for a GPS fix")
    }
    @MainActor
    func testAutomaticLocationPermissionUpgradeIsExplicitAndForegroundOnly() {
        let manager = LocationManagerFixture()
        var foreground = false
        let gps = GPSRecorder(manager:manager,isForeground:{foreground})
        gps.requestAutomaticAuthorization(); XCTAssertEqual(manager.alwaysRequests,0)
        foreground = true
        gps.start(); XCTAssertEqual(manager.alwaysRequests,0)
        gps.requestAutomaticAuthorization(); XCTAssertEqual(manager.alwaysRequests,1)
        gps.stop()
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey:"NSLocationAlwaysAndWhenInUseUsageDescription"))
    }
}


extension GPSRecordingTests {
    @MainActor
    func testFailedPhoneGPSWarmupClearsLocationIntent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let gps = GPSFixture()
        let store = AppStore(disk:LocalStore(url:root.appendingPathComponent("state.json")),gps:gps,scannerAvailable:{_ in false})
        var vehicle = VehicleProfile(); vehicle.make = "Test"; vehicle.model = "Permission fixture"
        try store.saveVehicle(vehicle)
        gps.onReady = nil
        store.source = .phoneGPS; store.startRecording()
        XCTAssertTrue(store.pendingGPS); XCTAssertFalse(store.recording)
        gps.onFailure?("Location denied")
        XCTAssertFalse(store.pendingGPS); XCTAssertFalse(store.recording)
        XCTAssertEqual(gps.stops,1)
    }
}
