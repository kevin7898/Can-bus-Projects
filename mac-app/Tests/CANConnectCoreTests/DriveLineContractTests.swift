import XCTest
import DriveLineShared
@testable import CANConnectCore

final class DriveLineContractTests:XCTestCase {
    private func fixture(_ name:String) throws -> Data {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf:root.appendingPathComponent("shared/DriveLineShared/Tests/DriveLineSharedTests/Fixtures/\(name).json"))
    }
    func testGoldenFixtureMatchesSharedMetricsAndProvenance() throws {
        let data=try fixture("golden-v2")
        let shared=try DriveLineArchive.decoded(data)
        let canonical=try XCTUnwrap(shared.recordings.first)
        let expected=DriveLineMetricPolicy.metrics(for:canonical)
        let result=try RecordingImporter.parse(data:data,name:"golden-v2.json",vehicleID:canonical.vehicleID,receiptID:UUID())
        let trip=try XCTUnwrap(result.trips.first)
        XCTAssertEqual(trip.id,canonical.recordingID)
        XCTAssertEqual(trip.vehicleID,canonical.vehicleID)
        XCTAssertEqual(try XCTUnwrap(trip.distanceKm),try XCTUnwrap(expected.distanceKm),accuracy:0.000_001)
        XCTAssertEqual(trip.duration,expected.durationSeconds,accuracy:0.000_001)
        XCTAssertEqual(try XCTUnwrap(trip.fuelUsedL),try XCTUnwrap(expected.tripFuelLitres),accuracy:0.000_001)
        XCTAssertEqual(try XCTUnwrap(trip.economyL100),try XCTUnwrap(expected.economyL100Km),accuracy:0.000_001)
        let restoredMetrics=DriveLineMetricPolicy.metrics(for:trip.sharedRecording)
        XCTAssertEqual(restoredMetrics.coverage.first(where:{$0.key == "fuelRateLph"})?.fraction,
                       expected.coverage.first(where:{$0.key == "fuelRateLph"})?.fraction)
        let observations=DriveLineMetricPolicy.latestObservations([trip.sharedRecording])
        XCTAssertEqual(DriveLineMetricPolicy.boostGaugeKpa(observations:observations)?.value,35)
        XCTAssertEqual(result.fuelEntries.first?.receipt?.sha256,String(repeating:"a",count:64))
        let restoredArchive=try DriveLineArchive.decoded(TripExport.json(trip,fuelEntries:result.fuelEntries))
        XCTAssertEqual(restoredArchive.fuelEntries.first?.receipt?.sha256,String(repeating:"a",count:64))
        XCTAssertTrue(trip.source.contains("Synthetic GPS"));XCTAssertTrue(trip.source.contains("Synthetic OBD"))
    }
    func testVersionOneLibraryLoadsInMemoryAsVersionTwoWithoutRewriting() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let original=Data(#"{"schemaVersion":1,"vehicles":[],"trips":[],"receipts":[],"preferences":{},"serverPort":8765,"allowLAN":false,"autoStartServer":false}"#.utf8)
        try original.write(to:root.appendingPathComponent("library.json"))
        let repository=try LibraryRepository(root:root)
        XCTAssertEqual(try repository.load().schemaVersion,2)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("library.json")),original,"Loading must not rewrite the user's version-1 library")
    }
}
