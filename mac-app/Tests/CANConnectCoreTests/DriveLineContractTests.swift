import XCTest
import DriveLineShared
@testable import CANConnectCore

final class DriveLineContractTests:XCTestCase {
    func testMacTodayUsesOnlyRealSelectedVehicleDataAndKeepsMissingFuelUnavailable() throws {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=try XCTUnwrap(TimeZone(secondsFromGMT:0))
        let now=try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-25T18:00:00Z"))
        let vehicle=Vehicle(name:"Real Jetta"), other=Vehicle(name:"Other")
        let real=Trip(vehicleID:vehicle.id,name:"Real",source:"GPS",samples:[],isDemo:false,
                      recordedStartedAt:now.addingTimeInterval(-1200),recordedEndedAt:now,recordedDistanceKm:20,tripFuelLitres:nil)
        let demo=Trip(vehicleID:vehicle.id,name:"Demo",source:"Synthetic",samples:[],isDemo:true,
                      recordedStartedAt:now.addingTimeInterval(-60),recordedEndedAt:now,recordedDistanceKm:999,tripFuelLitres:99)
        let foreign=Trip(vehicleID:other.id,name:"Other",source:"GPS",samples:[],recordedStartedAt:now,recordedEndedAt:now,recordedDistanceKm:500)
        let fill=FuelEntry(vehicleID:vehicle.id,date:now,litresPurchased:42,totalCost:70,odometerKm:200_000,isFullFill:true)
        let demoFill=FuelEntry(vehicleID:vehicle.id,date:now.addingTimeInterval(1),litresPurchased:100,totalCost:0,odometerKm:1,isFullFill:true,isDemo:true)
        var state=LibraryState();state.vehicles=[vehicle,other];state.selectedVehicleID=vehicle.id;state.trips=[demo,foreign,real];state.fuelEntries=[demoFill,fill]

        let value=MacTodayPresentation.make(state:state,now:now,calendar:calendar)

        XCTAssertEqual(value.todayTrips.map(\.id),[real.id])
        XCTAssertEqual(value.todayDistanceKm,20)
        XCTAssertNil(value.todayFuelLitres,"Missing measured trip fuel must not render as zero")
        XCTAssertEqual(value.latestTrip?.id,real.id)
        XCTAssertEqual(value.latestFill?.id,fill.id)
    }

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
    func testVersionOneLibraryLoadsInMemoryAsVersionThreeWithoutRewriting() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let original=Data(#"{"schemaVersion":1,"vehicles":[],"trips":[],"receipts":[],"preferences":{},"serverPort":8765,"allowLAN":false,"autoStartServer":false}"#.utf8)
        try original.write(to:root.appendingPathComponent("library.json"))
        let repository=try LibraryRepository(root:root)
        XCTAssertEqual(try repository.load().schemaVersion,3)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("library.json")),original,"Loading must not rewrite the user's version-1 library")
    }
    func testJourneyAnnotationRoundTripDoesNotChangeArchivePayload() throws {
        let vehicle=Vehicle(name:"Synthetic")
        let trip=Trip(vehicleID:vehicle.id,name:"Evidence",source:"Imported fixture",samples:[],recordedStartedAt:Date(timeIntervalSince1970:1_700_000_000),recordedEndedAt:Date(timeIntervalSince1970:1_700_000_010),recordedDistanceKm:1)
        let archive=try TripExport.json(trip)
        var state=LibraryState();state.vehicles=[vehicle];state.trips=[trip]
        state.journeyAnnotations[trip.id.uuidString]=DriveLineJourneyAnnotation(recordingID:trip.id,purpose:.service,reviewed:true,note:"Fixture")
        let restored=try LibraryRepository.decoder().decode(LibraryState.self,from:LibraryRepository.encoder().encode(state))
        XCTAssertEqual(restored.schemaVersion,3)
        XCTAssertEqual(restored.journeyAnnotations[trip.id.uuidString]?.purpose,.service)
        XCTAssertEqual(try TripExport.json(try XCTUnwrap(restored.trips.first)),archive)
    }
}
