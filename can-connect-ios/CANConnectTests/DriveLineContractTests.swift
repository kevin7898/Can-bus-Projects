import XCTest
import CryptoKit
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
    @MainActor func testJourneyAnnotationPersistsWithoutChangingFrozenTransferPayload() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"))
        let store=AppStore(disk:disk,scannerAvailable:{_ in false})
        var vehicle=VehicleProfile();vehicle.make="Synthetic";vehicle.model="Fixture";try store.saveVehicle(vehicle)
        let trip=Trip(vehicleID:vehicle.id,name:"Evidence",startedAt:Date(),duration:10,distanceKM:0.1,source:.scanner,isSample:false,
                      samples:[OBDSample(timestamp:Date(),signals:["rpm":1_500],command:"010C",reply:"SYNTHETIC")])
        let payload=try MacRecording.encode(trip)
        store.state.trips=[trip]
        store.state.transfers=[TransferItem(tripID:trip.id,name:trip.name,endpoint:"http://mac.local",vehicle:vehicle,payload:payload)]
        store.save()
        store.saveJourneyAnnotation(DriveLineJourneyAnnotation(recordingID:trip.id,purpose:.business,reviewed:true,note:"Fixture visit"))
        XCTAssertEqual(store.state.transfers.first?.payload,payload)
        let restarted=AppStore(disk:disk,scannerAvailable:{_ in false})
        XCTAssertEqual(restarted.journeyAnnotation(for:trip.id).purpose,.business)
        XCTAssertTrue(restarted.journeyAnnotation(for:trip.id).reviewed)
        XCTAssertEqual(restarted.state.transfers.first?.payload,payload)
    }

    @MainActor func testFuelAddEditValidationAllowsExplicitCorrectionWithoutChangingTripTelemetry() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=AppStore(disk:LocalStore(url:root.appendingPathComponent("state.json")),scannerAvailable:{_ in false})
        var vehicle=VehicleProfile();vehicle.make="Synthetic";vehicle.model="Fuel fixture";try store.saveVehicle(vehicle)
        let start=Date(timeIntervalSince1970:1_700_000_000)
        let trip=Trip(vehicleID:vehicle.id,name:"Measured drive",startedAt:start,duration:10,distanceKM:1,source:.scanner,
                      isSample:false,economy:6,fuelLitres:0.06,
                      samples:[OBDSample(timestamp:start,signals:["fuelRateLph":3],command:"015E",reply:"SYNTHETIC")])
        store.state.trips=[trip];store.save()
        let before=try XCTUnwrap(store.state.trips.first)
        _=try store.saveFill(litres:40,cost:70,currencyCode:"cad",odometer:1_000,full:true,date:start,
                             stationName:" Fixture North ",notes:" First full ")
        _=try store.saveFill(litres:10,cost:18,currencyCode:"USD",odometer:1_200,full:false,date:start.addingTimeInterval(100),stationName:nil,notes:nil)
        let last=try store.saveFill(litres:20,cost:36,currencyCode:"CAD",odometer:1_600,full:true,date:start.addingTimeInterval(200),stationName:nil,notes:nil)
        XCTAssertEqual(try XCTUnwrap(FuelMath.latestEconomy(store.vehicleFills)),5,accuracy:0.000_001)
        XCTAssertEqual(store.vehicleFills.first?.currencyCode,"CAD")
        XCTAssertThrowsError(try store.saveFill(id:last.id,litres:20,cost:36,currencyCode:"EURO",odometer:900,full:true,date:start.addingTimeInterval(200),stationName:nil,notes:nil))
        XCTAssertThrowsError(try store.saveFill(id:last.id,litres:20,cost:36,currencyCode:"EUR",odometer:900,full:true,date:start.addingTimeInterval(200),stationName:nil,notes:nil))
        let corrected=try store.saveFill(id:last.id,litres:20,cost:36,currencyCode:"EUR",odometer:900,full:true,date:start.addingTimeInterval(200),stationName:nil,notes:"Legitimate dashboard correction",allowOdometerCorrection:true)
        XCTAssertEqual(corrected.odometerKM,900)
        XCTAssertEqual(store.state.trips.first,before)
        XCTAssertEqual(store.state.trips.first?.fuelLitres,0.06,"Purchased fuel edits must not alter measured trip fuel")
    }

    @MainActor func testReceiptCompleteArchiveRestoreDeduplicatesFilesAndKeepsMissingMetadata() throws {
        let sourceRoot=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let restoredRoot=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let missingRoot=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { for root in [sourceRoot,restoredRoot,missingRoot] { try? FileManager.default.removeItem(at:root) } }
        let sourceDisk=LocalStore(url:sourceRoot.appendingPathComponent("state.json"))
        let source=AppStore(disk:sourceDisk,scannerAvailable:{_ in false})
        var vehicle=VehicleProfile();vehicle.make="Synthetic";vehicle.model="Receipt fixture";try source.saveVehicle(vehicle)
        let data=Data("sanitized receipt file bytes".utf8)
        let digest=SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        let metadata=DriveLineReceiptMetadata(fileName:"receipt.txt",mediaType:"text/plain",byteCount:data.count,sha256:digest)
        let attachment=ReceiptAttachment(metadata:metadata,data:data)
        _=try source.saveFill(litres:40,cost:70,currencyCode:"CAD",odometer:1_000,full:true,date:Date(timeIntervalSince1970:100),stationName:"Fixture",notes:nil,receipt:attachment)
        _=try source.saveFill(litres:20,cost:35,currencyCode:"USD",odometer:1_400,full:true,date:Date(timeIntervalSince1970:200),stationName:nil,notes:nil,receipt:attachment)
        let trip=Trip(vehicleID:vehicle.id,name:"Archive anchor",startedAt:Date(timeIntervalSince1970:100),duration:10,distanceKM:1,source:.phoneGPS,isSample:false)
        source.state.trips=[trip];source.save()
        let complete=try source.archive([trip])
        XCTAssertEqual(complete.receiptFiles?.count,1,"Identical receipt content is stored once")
        XCTAssertEqual(complete.receiptFiles?[digest],data)
        let stateBytes=try Data(contentsOf:sourceRoot.appendingPathComponent("state.json"))
        XCTAssertFalse(String(decoding:stateBytes,as:UTF8.self).contains("sanitized receipt file bytes"),"Primary JSON stores metadata, not receipt bytes")

        let restored=AppStore(disk:LocalStore(url:restoredRoot.appendingPathComponent("state.json")),scannerAvailable:{_ in false})
        try restored.saveVehicle(vehicle)
        try restored.importTrips(complete.encoded())
        XCTAssertEqual(restored.vehicleFills.count,2)
        XCTAssertTrue(try XCTUnwrap(restored.vehicleFills.first?.receipt).sha256 == digest)
        XCTAssertTrue(restored.vehicleFills.allSatisfy { $0.receipt.map(restored.hasReceipt) == true })

        var missing=complete;missing.receiptFiles=nil
        let missingStore=AppStore(disk:LocalStore(url:missingRoot.appendingPathComponent("state.json")),scannerAvailable:{_ in false})
        try missingStore.saveVehicle(vehicle);try missingStore.importTrips(missing.encoded())
        XCTAssertEqual(missingStore.vehicleFills.first?.receipt?.sha256,digest)
        XCTAssertFalse(missingStore.vehicleFills.contains { $0.receipt.map(missingStore.hasReceipt) == true },"Missing files remain explicitly unavailable")
    }

    func testPhase6TripStoryAndSignalsDetailUseIdenticalSharedEvidence() throws {
        let start=Date(timeIntervalSince1970:1_700_000_000),vehicleID=UUID()
        let trip=Trip(vehicleID:vehicleID,name:"Parity",startedAt:start,duration:30,distanceKM:0.3,source:.scanner,isSample:true,
            route:[0.0,10.0,20.0,30.0].map { RoutePoint(latitude:49+$0*0.00001,longitude:-124,timestamp:start.addingTimeInterval($0),accuracy:4,speed:10) },
            samples:[
                OBDSample(timestamp:start,signals:["rpm":1_000],command:"010C",reply:"SYNTHETIC"),
                OBDSample(timestamp:start.addingTimeInterval(10),signals:["rpm":2_000],command:"010C",reply:"SYNTHETIC"),
                OBDSample(timestamp:start.addingTimeInterval(30),signals:["rpm":4_000],command:"010C",reply:"SYNTHETIC")
            ])
        let recording=trip.sharedRecording,cursorDate=start.addingTimeInterval(10)
        let story=DriveLineJourneyPolicy.cursor(at:cursorDate,recording:recording,signalKeys:["rpm"])
        let descriptor=DriveLineJourneyPolicy.signalDescriptor("rpm",recording:recording)
        let detailSeries=DriveLineJourneyPolicy.signalSeries(descriptor.key,unit:descriptor.unit ?? "",recording:recording)
        let detail=DriveLineJourneyPolicy.signalStatistics(detailSeries,at:cursorDate)
        XCTAssertEqual(story.observations["rpm"]?.value,detail.current?.value)
        XCTAssertEqual(story.observations["rpm"]?.timestamp,detail.current?.timestamp)
        XCTAssertEqual(story.observations["rpm"]?.sourceID,detail.current?.sourceID)
        XCTAssertEqual(descriptor.unit,"rpm")
        XCTAssertEqual(detailSeries.coverage?.fraction,DriveLineMetricPolicy.coverageSummaries(recording).first(where:{$0.key == "rpm"})?.fraction)
        XCTAssertTrue(recording.isSample)
    }

    func testPhase6PhoneAdapterKeepsGPSOnlyOBDOnlyAndMissingSignalsHonest() {
        let start=Date(timeIntervalSince1970:1_700_000_000),vehicleID=UUID()
        let gps=Trip(vehicleID:vehicleID,name:"GPS",startedAt:start,duration:20,distanceKM:0.2,source:.phoneGPS,isSample:false,
            route:[0.0,10.0,20.0].map { RoutePoint(latitude:49+$0*0.00001,longitude:-124,timestamp:start.addingTimeInterval($0),accuracy:4,speed:10) })
        let obd=Trip(vehicleID:vehicleID,name:"OBD",startedAt:start,duration:20,distanceKM:0,source:.scanner,isSample:false,
            samples:[OBDSample(timestamp:start,signals:["rpm":1_500],command:"010C",reply:"SYNTHETIC"),
                     OBDSample(timestamp:start.addingTimeInterval(10),signals:["rpm":1_600],command:"010C",reply:"SYNTHETIC")])
        XCTAssertTrue(DriveLineJourneyPolicy.signalDescriptors(recording:gps.sharedRecording).contains(where:{$0.key == "gps.speedKph"}))
        XCTAssertTrue(DriveLineJourneyPolicy.distanceAlignmentAvailability(gps.sharedRecording).isAvailable)
        XCTAssertFalse(DriveLineJourneyPolicy.distanceAlignmentAvailability(obd.sharedRecording).isAvailable)
        let missing=DriveLineJourneyPolicy.signalSeries("coolantC",unit:"°C",recording:obd.sharedRecording)
        XCTAssertTrue(missing.segments.isEmpty)
        XCTAssertEqual(DriveLineJourneyPolicy.signalStatistics(missing,at:obd.startedAt).freshness,.unavailable)
    }
}
