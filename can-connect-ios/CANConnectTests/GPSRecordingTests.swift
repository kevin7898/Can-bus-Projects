import XCTest
import Combine
import UIKit
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
        XCTAssertEqual(draft.distanceKM,0.05,accuracy:0.000001,"GPS must not add a second distance on top of OBD")
        let trip = draft.trip(endedAt:start.addingTimeInterval(10))
        let restored = try XCTUnwrap(TripArchive.decode(TripArchive(trips:[trip]).encoded()).trips.first)
        XCTAssertEqual(restored.route,trip.route); XCTAssertEqual(restored.samples,trip.samples)
        let payload = try MacRecording.encode(restored)
        let attachment = XCTAttachment(data:payload,uniformTypeIdentifier:"public.json")
        attachment.name = "Synthetic mixed scanner GPS upload"; attachment.lifetime = .keepAlways; add(attachment)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:payload) as? [String:Any])
        let rows = try XCTUnwrap(object["samples"] as? [[String:Any]])
        let gps = rows.filter { $0["latitude"] != nil }, obd = rows.filter { $0["signals"] != nil }
        XCTAssertEqual(gps.count,2); XCTAssertEqual(obd.count,2)
        XCTAssertEqual(gps[1]["latitude"] as? Double,49.001)
        XCTAssertEqual(gps[1]["timestamp"] as? Double,start.addingTimeInterval(10).timeIntervalSince1970)
        XCTAssertNil(gps[1]["signals"],"Do not turn GPS speed into an ECU measurement")
        XCTAssertEqual(rows.compactMap {$0["timestamp"] as? Double},rows.compactMap {$0["timestamp"] as? Double}.sorted())
        XCTAssertEqual(try MacRecording.encode(restored),payload,"Transfer retries must use the same payload")
    }
    func testRouteMapSeparatesOutagesInsteadOfDrawingAnInventedRoad() {
        let route = [point(0),point(10,49.001),point(65,49.002),point(75,49.003)]
        XCTAssertEqual(RoutePoint.segments(route),[Array(route[0...1]),Array(route[2...3])])
        XCTAssertEqual(RoutePoint.segments([]),[])
        XCTAssertEqual(RoutePoint.segments([point(0)]),[[point(0)]])
    }
    @MainActor
    func testPhoneGPSStillStartsSavesAndStopsNormally() throws {
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
        XCTAssertEqual(store.state.trips.first?.route,[point]); XCTAssertEqual(gps.stops,1)
        gps.onPoint?(point)
        XCTAssertNil(store.state.draft)
    }
}
