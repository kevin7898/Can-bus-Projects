import XCTest
@testable import CANConnect

final class DriveLineContractTests:XCTestCase {
    private func fixture(_ name:String) throws -> Data {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf:root.appendingPathComponent("shared/DriveLineShared/Tests/DriveLineSharedTests/Fixtures/\(name).json"))
    }
    func testGoldenFixtureMatchesSharedMetricsAndProvenance() throws {
        let data=try fixture("golden-v2")
        let shared=try DriveLineArchive.decoded(data)
        let canonical=try XCTUnwrap(shared.recordings.first)
        let expected=DriveLineMetricPolicy.metrics(for:canonical)
        let archive=try TripArchive.decode(data)
        let trip=try XCTUnwrap(archive.trips.first)
        XCTAssertEqual(trip.id,canonical.recordingID)
        XCTAssertEqual(trip.vehicleID,canonical.vehicleID)
        XCTAssertEqual(trip.distanceKM,try XCTUnwrap(expected.distanceKm),accuracy:0.000_001)
        XCTAssertEqual(trip.duration,expected.durationSeconds,accuracy:0.000_001)
        XCTAssertEqual(try XCTUnwrap(trip.fuelLitres),try XCTUnwrap(expected.tripFuelLitres),accuracy:0.000_001)
        XCTAssertEqual(try XCTUnwrap(trip.economy),try XCTUnwrap(expected.economyL100Km),accuracy:0.000_001)
        let restoredMetrics=DriveLineMetricPolicy.metrics(for:trip.sharedRecording)
        XCTAssertEqual(restoredMetrics.coverage.first(where:{$0.key == "fuelRateLph"})?.fraction,
                       expected.coverage.first(where:{$0.key == "fuelRateLph"})?.fraction)
        let observations=DriveLineMetricPolicy.latestObservations([trip.sharedRecording])
        XCTAssertEqual(DriveLineMetricPolicy.boostGaugeKpa(observations:observations)?.value,35)
        XCTAssertEqual(trip.source,.scanner)
        XCTAssertEqual(archive.fills.first?.receipt?.sha256,String(repeating:"a",count:64))
        XCTAssertEqual(Set(canonical.sourceIDs),Set(["gps","obd"]))
    }
    func testVersionOneArchiveStillLoadsUnchanged() throws {
        let id=UUID(),vehicleID=UUID(),date="2026-01-01T12:00:00.125Z"
        let data=Data(#"{"schemaVersion":1,"trips":[{"id":"\#(id.uuidString)","vehicleID":"\#(vehicleID.uuidString)","name":"Legacy","startedAt":"\#(date)","duration":10,"distanceKM":1.25,"source":"phoneGPS","isSample":false,"route":[]}]}"#.utf8)
        let archive=try TripArchive.decode(data)
        XCTAssertEqual(archive.trips.first?.id,id)
        XCTAssertEqual(archive.trips.first?.vehicleID,vehicleID)
        XCTAssertEqual(archive.trips.first?.distanceKM,1.25)
    }
    func testUnassignedLegacyFillSurvivesVersionTwoRoundTrip() throws {
        let fill=FuelEntry(vehicleID:nil,date:Date(timeIntervalSince1970:1_767_268_800),litres:10,costCAD:20,odometerKM:100,full:true)
        let decoded=try TripArchive.decode(TripArchive(trips:[],fills:[fill]).encoded())
        XCTAssertEqual(decoded.fills.first?.id,fill.id)
        XCTAssertNil(decoded.fills.first?.vehicleID)
        XCTAssertEqual(decoded.fills.first?.litresPurchased,10)
    }
    @MainActor func testNewerGPSOnlyTripDoesNotHideOlderScannerSignalsOrEnterRealTotals() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=AppStore(disk:LocalStore(url:root.appendingPathComponent("state.json")),scannerAvailable:{_ in false})
        var vehicle=VehicleProfile();vehicle.make="Synthetic";vehicle.model="Fixture";try store.saveVehicle(vehicle)
        let now=Date()
        let old=Trip(vehicleID:vehicle.id,name:"Scanner",startedAt:now.addingTimeInterval(-100),duration:10,distanceKM:0.1,source:.scanner,isSample:false,
                     samples:[OBDSample(timestamp:now.addingTimeInterval(-90),signals:["rpm":1700],command:"010C",reply:"SYNTHETIC")])
        let newer=Trip(vehicleID:vehicle.id,name:"GPS",startedAt:now,duration:10,distanceKM:0.1,source:.phoneGPS,isSample:false)
        let sample=Trip(vehicleID:vehicle.id,name:"Sample",startedAt:now,duration:10,distanceKM:999,source:.imported,isSample:true)
        store.state.trips=[newer,old,sample];store.now=now
        XCTAssertEqual(store.latestRecordedValue("rpm"),1700)
        XCTAssertEqual(store.weekKM,0.2,accuracy:0.000_001)
    }
    @MainActor func testArchiveImportRejectsVINRemappingAcrossStableVehicleIDs() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=AppStore(disk:LocalStore(url:root.appendingPathComponent("state.json")),scannerAvailable:{_ in false})
        var local=VehicleProfile();local.make="Synthetic";local.model="Local";local.vin="1D4GP00R55B123456"
        try store.saveVehicle(local)
        let originalVehicles=store.state.vehicles
        var foreign=local;foreign.id=UUID();foreign.model="Foreign"
        let trip=Trip(vehicleID:foreign.id,name:"Foreign",startedAt:Date(),duration:1,distanceKM:0,source:.imported,isSample:false)
        let bytes=try TripArchive(vehicles:[foreign],trips:[trip]).encoded()
        XCTAssertThrowsError(try store.importTrips(bytes))
        XCTAssertEqual(store.state.vehicles,originalVehicles)
    }
}
