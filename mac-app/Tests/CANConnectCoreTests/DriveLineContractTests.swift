import XCTest
import CryptoKit
import DriveLineShared
@testable import CANConnectCore

final class DriveLineContractTests:XCTestCase {
    func testPhase8ImportReceiptStatesKeepAcknowledgementSeparateFromProcessing() {
        let vehicle=UUID()
        var receipt=ImportReceipt(vehicleID:vehicle,originalName:"fixture.json",archiveName:"preserved.json",contentHash:String(repeating:"a",count:64),byteCount:20)
        XCTAssertEqual(receipt.semanticState,.queued);XCTAssertEqual(receipt.statusTitle,"Queued")
        receipt.status = .processing;XCTAssertEqual(receipt.semanticState,.processing)
        receipt.status = .failed;XCTAssertEqual(receipt.semanticState,.failed);XCTAssertTrue(receipt.statusTitle.contains("original preserved"))
        receipt.status = .processed;XCTAssertEqual(receipt.semanticState,.complete)
    }
    func testPhase7FourVehicleProfilesRoundTripWithStableIndependentIdentity() throws {
        let profiles=[
            Vehicle(name:"Fictional Jetta",year:"2013",make:"Volkswagen",model:"Jetta TDI",vehicleClass:.passengerCar,fuelType:"Diesel"),
            Vehicle(name:"F-150",year:"2021",make:"Ford",model:"F-150",vehicleClass:.lightTruck,fuelType:"Gasoline"),
            Vehicle(name:"CB500X ABS",year:"2023",make:"Honda",model:"CB500X ABS",vehicleClass:.motorcycle,fuelType:"Gasoline"),
            Vehicle(name:"T880",year:"2025",make:"Kenworth",model:"T880",vehicleClass:.heavyTruck,fuelType:"Diesel")
        ]
        var state=LibraryState();state.vehicles=profiles;state.selectedVehicleID=profiles[0].id
        state.trips=[Trip(vehicleID:profiles[0].id,name:"Jetta",source:"fixture",samples:[]),Trip(vehicleID:profiles[1].id,name:"Ford",source:"fixture",samples:[])]
        state.fuelEntries=[FuelEntry(vehicleID:profiles[2].id,date:Date(),litresPurchased:1,totalCost:1,odometerKm:1,isFullFill:true)]
        let decoded=try LibraryRepository.decoder().decode(LibraryState.self,from:LibraryRepository.encoder().encode(state))
        XCTAssertEqual(decoded.vehicles.map(\.id),profiles.map(\.id))
        XCTAssertEqual(decoded.trips.filter{$0.vehicleID==profiles[0].id}.count,1)
        XCTAssertEqual(decoded.trips.filter{$0.vehicleID==profiles[3].id}.count,0)
        XCTAssertEqual(decoded.fuelEntries.first?.vehicleID,profiles[2].id)
    }

    func testPhase7LegacyVehicleDecodeIsAdditiveAndManualVINMayRemainMissing() throws {
        let id=UUID()
        let data="{\"id\":\"\(id.uuidString)\",\"name\":\"Manual custom vehicle\",\"year\":\"\",\"make\":\"\",\"model\":\"\",\"vin\":\"\",\"notes\":\"\"}".data(using:.utf8)!
        let vehicle=try JSONDecoder().decode(Vehicle.self,from:data)
        XCTAssertEqual(vehicle.id,id);XCTAssertEqual(vehicle.vehicleClass,.passengerCar)
        XCTAssertEqual(vehicle.configuredSources,[.manual,.phoneGPS]);XCTAssertFalse(vehicle.isArchived)
        XCTAssertTrue(vehicle.vin.isEmpty)
    }
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

    func testIPhoneFuelOnlyTransferImportsStableFillAndReceiptWithoutARecording() throws {
        let vehicle=Vehicle(name:"Synthetic transfer vehicle")
        let bytes=Data("sanitized cross-platform receipt".utf8)
        let digest=SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
        let metadata=DriveLineReceiptMetadata(fileName:"fixture.txt",mediaType:"text/plain",byteCount:bytes.count,sha256:digest)
        let fill=DriveLineFuelEntry(id:UUID(),vehicleID:vehicle.id,date:Date(timeIntervalSince1970:100),litresPurchased:42,totalCost:70,currencyCode:"CAD",odometerKm:200_000,isFullFill:true,stationName:"Fixture",notes:"Sanitized",receipt:metadata)
        let payload=try DriveLineArchive(producer:DriveLineProducer(app:"DriveLine iPhone",version:"test",platform:"iOS"),sources:[],vehicles:[DriveLineVehicle(id:vehicle.id,name:vehicle.name)],recordings:[],fuelEntries:[fill],receiptFiles:[digest:bytes]).encoded()
        let result=try RecordingImporter.parse(data:payload,name:"companion-fuel.json",vehicleID:vehicle.id,receiptID:UUID())
        XCTAssertTrue(result.trips.isEmpty)
        XCTAssertEqual(result.fuelEntries.first?.id,fill.id)
        XCTAssertEqual(result.fuelEntries.first?.litresPurchased,42)
        XCTAssertEqual(result.fuelEntries.first?.currencyCode,"CAD")
        XCTAssertEqual(result.receiptFiles,[digest:bytes])
    }

    func testReceiptFilesSurviveCompleteBackupRestoreAndDuplicateStorage() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backupParent=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:backupParent) }
        try FileManager.default.createDirectory(at:backupParent,withIntermediateDirectories:true)
        let repo=try LibraryRepository(root:root)
        let vehicle=Vehicle(name:"Synthetic backup vehicle")
        let bytes=Data("sanitized backup receipt".utf8)
        let digest=SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
        let metadata=DriveLineReceiptMetadata(fileName:"receipt.txt",mediaType:"text/plain",byteCount:bytes.count,sha256:digest)
        let first=FuelEntry(vehicleID:vehicle.id,date:Date(timeIntervalSince1970:100),litresPurchased:40,totalCost:70,currencyCode:"CAD",odometerKm:1_000,isFullFill:true,receipt:metadata)
        let second=FuelEntry(vehicleID:vehicle.id,date:Date(timeIntervalSince1970:200),litresPurchased:20,totalCost:35,currencyCode:"USD",odometerKm:1_400,isFullFill:true,receipt:metadata)
        try repo.storeReceiptFiles([digest:bytes],for:[first,second])
        XCTAssertNoThrow(try repo.storeReceiptFiles([digest:bytes],for:[first,second]))
        var state=LibraryState();state.vehicles=[vehicle];state.selectedVehicleID=vehicle.id;state.fuelEntries=[first,second];try repo.save(state)
        let backup=try repo.backup(to:backupParent)
        let restored=try LibraryRepository(root:backup)
        XCTAssertEqual(try restored.load().fuelEntries,[first,second])
        XCTAssertEqual(restored.receiptData(metadata),bytes)
        try FileManager.default.removeItem(at:restored.receiptURL(metadata))
        XCTAssertNil(restored.receiptData(metadata),"Missing receipt bytes remain unavailable while library metadata is retained")
        XCTAssertEqual(try restored.load().fuelEntries.first?.receipt,metadata)
    }

    func testCorruptLibraryPreservesBytesAndRestoresValidatedAtomicBackup() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let repo=try LibraryRepository(root:root)
        var original=LibraryState();let vehicle=Vehicle(name:"Sanitized recovery vehicle")
        original.vehicles=[vehicle];original.selectedVehicleID=vehicle.id
        try repo.save(original)
        var newer=original;newer.serverPort=9012;try repo.save(newer)
        XCTAssertEqual(repo.validStateBackup()?.serverPort,original.serverPort)
        let corrupt=Data("{ synthetic corrupt library".utf8);try corrupt.write(to:repo.manifest)
        XCTAssertThrowsError(try repo.load())
        let recovered=try repo.restoreStateBackup()
        XCTAssertEqual(recovered.selectedVehicleID,vehicle.id)
        XCTAssertEqual(try repo.load().serverPort,original.serverPort)
        let preserved=try FileManager.default.contentsOfDirectory(at:repo.recovery,includingPropertiesForKeys:nil)
        XCTAssertEqual(preserved.count,1)
        XCTAssertEqual(try Data(contentsOf:preserved[0]),corrupt)
    }

    func testInvalidLibraryBackupNeverCreatesEmptyReplacement() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let repo=try LibraryRepository(root:root),corrupt=Data("synthetic primary bytes".utf8)
        try corrupt.write(to:repo.manifest);try Data("synthetic backup bytes".utf8).write(to:repo.stateBackup)
        XCTAssertThrowsError(try repo.restoreStateBackup())
        XCTAssertEqual(try Data(contentsOf:repo.manifest),corrupt)
    }

    func testPhase6MacPreferencesMigrateStableSignalKeysAndKeepDuplicates() throws {
        var legacy=VehiclePreferences()
        legacy.signalKeys=nil
        let encoded=try JSONEncoder().encode(legacy)
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        object.removeValue(forKey:"signalKeys")
        let decoded=try JSONDecoder().decode(VehiclePreferences.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(decoded.resolvedSignalKeys,legacy.signals.map(\.rawValue))

        var configured=decoded
        configured.signalKeys=["rpm","rpm","vendor.unknown","gps.speedKph","boostKpa","dpfRegenTrigger"]
        let restored=try JSONDecoder().decode(VehiclePreferences.self,from:JSONEncoder().encode(configured))
        XCTAssertEqual(restored.resolvedSignalKeys[0],"rpm")
        XCTAssertEqual(restored.resolvedSignalKeys[1],"rpm","Duplicate lane selections are intentional")
        XCTAssertEqual(restored.resolvedSignalKeys[2],"vendor.unknown")
    }

    func testPhase6MacAdapterUsesSharedSignalStatisticsAndUnknownMetadataPolicy() throws {
        let start=Date(timeIntervalSince1970:1_700_000_000),vehicle=Vehicle(name:"Synthetic")
        let trip=Trip(vehicleID:vehicle.id,name:"Signals",source:"Sanitized fixture",samples:[
            TelemetrySample(timestamp:start,signals:["rpm":1_000,"vendor.pid":7]),
            TelemetrySample(timestamp:start.addingTimeInterval(4),signals:["rpm":2_000,"vendor.pid":9]),
            TelemetrySample(timestamp:start.addingTimeInterval(30),signals:["rpm":9_000])
        ],isDemo:true,recordedStartedAt:start,recordedEndedAt:start.addingTimeInterval(30))
        let recording=trip.sharedRecording
        let series=DriveLineJourneyPolicy.signalSeries("rpm",unit:"rpm",recording:recording)
        let stats=DriveLineJourneyPolicy.signalStatistics(series,at:start.addingTimeInterval(4),
            visibleRange:DateInterval(start:start,end:start.addingTimeInterval(10)))
        XCTAssertEqual(stats.observationCount,2)
        XCTAssertEqual(stats.recordedObservationAverage,1_500)
        XCTAssertEqual(stats.current?.value,2_000)
        XCTAssertEqual(series.segments.count,2)
        let unknown=DriveLineJourneyPolicy.signalDescriptor("vendor.pid",recording:recording)
        XCTAssertEqual(unknown.displayName,"vendor.pid")
        XCTAssertNil(unknown.unit)
        XCTAssertEqual(unknown.group,.otherUnknown)
        XCTAssertTrue(recording.isSample)
    }
}
