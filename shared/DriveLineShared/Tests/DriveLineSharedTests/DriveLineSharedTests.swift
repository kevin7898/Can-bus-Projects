import XCTest
import CryptoKit
@testable import DriveLineShared

final class DriveLineSharedTests: XCTestCase {
    func testAppearancePersistsAndDefaultsToSystem() throws {
        let suite = "DriveLineAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DriveLineAppearanceStore(defaults: defaults)
        XCTAssertEqual(store.selection, .system)
        store.selection = .dark
        XCTAssertEqual(DriveLineAppearanceStore(defaults: defaults).selection, .dark)
        defaults.set("future-value", forKey: DriveLineAppearance.storageKey)
        XCTAssertEqual(store.selection, .system)
    }

    func testAppearanceResolvesSystemLightAndDark() {
        XCTAssertEqual(DriveLineAppearance.system.resolved(systemIsDark: false), .light)
        XCTAssertEqual(DriveLineAppearance.system.resolved(systemIsDark: true), .dark)
        XCTAssertEqual(DriveLineAppearance.light.resolved(systemIsDark: true), .light)
        XCTAssertEqual(DriveLineAppearance.dark.resolved(systemIsDark: false), .dark)
    }

    func testMacNavigationContractKeepsPrimaryAndSecondaryDestinationsReachable() {
        XCTAssertEqual(DriveLineMacDestination.primary, [.today,.drives,.fuel,.signals,.garage])
        XCTAssertEqual(DriveLineMacDestination.secondary, [.imports,.server])
        XCTAssertEqual(Set(DriveLineMacDestination.primary + DriveLineMacDestination.secondary), Set(DriveLineMacDestination.allCases))
    }

    func testPhoneNavigationAndMoreCapabilitiesAreReachable() {
        XCTAssertEqual(DriveLinePhoneDestination.allCases,[.today,.drives,.record,.garage,.more])
        XCTAssertEqual(Set(DriveLineMoreCapability.allCases),Set([.connections,.transfers,.serverPairing,.settings]))
    }

    func testRecordingDeepLinkOpensRecord() throws {
        XCTAssertEqual(DriveLinePhoneRoute.destination(for:try XCTUnwrap(URL(string:"canconnect://recording"))),.record)
        XCTAssertNil(DriveLinePhoneRoute.destination(for:try XCTUnwrap(URL(string:"canconnect://trips"))))
        XCTAssertNil(DriveLinePhoneRoute.destination(for:try XCTUnwrap(URL(string:"https://example.com/recording"))))
    }

    func testEveryRequiredSemanticStateHasTextAndIcon() {
        XCTAssertEqual(DriveLineSemanticState.allCases,[.ready,.active,.waiting,.queued,.processing,.degraded,.stale,.unavailable,.offline,.failed,.recovered,.complete,.readOnly])
        for state in DriveLineSemanticState.allCases {
            XCTAssertFalse(state.title.isEmpty)
            XCTAssertFalse(state.icon.isEmpty)
        }
    }

    func testPhase8StateMatrixIsCompleteActionableAndUsesExactVocabulary() throws {
        let matrix=DriveLineStateMatrix.all
        XCTAssertEqual(matrix.count,119)
        XCTAssertEqual(matrix.map(\.id),Array(1...119))
        XCTAssertTrue(matrix.allSatisfy { !$0.trigger.isEmpty && !$0.persistedEvidence.isEmpty && !$0.wording.isEmpty && !$0.recoveryResult.isEmpty })
        XCTAssertTrue(matrix.allSatisfy { DriveLineSemanticState.allCases.contains($0.state) })
        XCTAssertEqual(try XCTUnwrap(DriveLineStateMatrix.state(42)).state,.failed)
        XCTAssertEqual(try XCTUnwrap(DriveLineStateMatrix.state(42)).actions,[.retrySave])
        XCTAssertTrue(try XCTUnwrap(DriveLineStateMatrix.state(42)).wording.contains("draft"))
        XCTAssertEqual(try XCTUnwrap(DriveLineStateMatrix.state(49)).state,.processing)
        XCTAssertTrue(try XCTUnwrap(DriveLineStateMatrix.state(49)).wording.contains("acknowledged"))
        XCTAssertEqual(try XCTUnwrap(DriveLineStateMatrix.state(58)).state,.complete)
        XCTAssertEqual(try XCTUnwrap(DriveLineStateMatrix.state(95)).state,.readOnly)
        XCTAssertTrue(try XCTUnwrap(DriveLineStateMatrix.state(95)).wording.contains("never replaced"))
        XCTAssertEqual(try XCTUnwrap(DriveLineStateMatrix.state(11)).platform,.mac)
        XCTAssertEqual(try XCTUnwrap(DriveLineStateMatrix.state(12)).platform,.iPhone)
        XCTAssertEqual(try XCTUnwrap(DriveLineStateMatrix.state(110)).platform,.mac)
    }

    func testPhase8MatrixNeverUsesMisleadingGenericStatusWords() {
        for item in DriveLineStateMatrix.all {
            let label=item.state.rawValue.lowercased()
            XCTAssertNotEqual(label,"connected")
            XCTAssertNotEqual(label,"synced")
            XCTAssertNotEqual(label,"error")
        }
    }

    func testPhase8EvidenceLanguageKeepsGapsAndPreservationHonest() throws {
        XCTAssertTrue(try XCTUnwrap(DriveLineStateMatrix.state(34)).wording.contains("not bridged"))
        XCTAssertTrue(try XCTUnwrap(DriveLineStateMatrix.state(48)).wording.contains("does not mean"))
        XCTAssertTrue(try XCTUnwrap(DriveLineStateMatrix.state(60)).wording.contains("identical frozen payload"))
        XCTAssertTrue(try XCTUnwrap(DriveLineStateMatrix.state(91)).wording.contains("never physical"))
        XCTAssertTrue(try XCTUnwrap(DriveLineStateMatrix.state(107)).wording.contains("not reassigned"))
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }

    func testVersion2GoldenMetricsAndDeterministicRoundTrip() throws {
        let archive = try DriveLineArchive.decoded(fixture("golden-v2"))
        let recording = try XCTUnwrap(archive.recordings.first)
        let metrics = DriveLineMetricPolicy.metrics(for: recording)
        XCTAssertEqual(archive.schemaVersion, 2)
        XCTAssertEqual(recording.recordingID.uuidString, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(metrics.durationSeconds, 20, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.distanceKm), 0.200_15, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(metrics.tripFuelLitres), 0.02, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.economyL100Km), 9.9925, accuracy: 0.05)
        XCTAssertEqual(metrics.coverage.first(where: { $0.key == "fuelRateLph" })?.fraction, 1)
        XCTAssertEqual(metrics.distanceSource, "gps")
        XCTAssertEqual(try DriveLineArchive.decoded(archive.encoded()), archive)
        XCTAssertEqual(try archive.encoded(), try archive.encoded())
        var precise=archive
        precise.recordings[0].startedAt=Date(timeIntervalSince1970:1_700_000_000.123456)
        XCTAssertEqual(try DriveLineArchive.decoded(precise.encoded()).recordings[0].startedAt,precise.recordings[0].startedAt)
    }

    func testVersion1MigrationPreservesStableIdentityAndPrecision() throws {
        let archive = try DriveLineArchive.decoded(fixture("migration-v1"))
        let recording = try XCTUnwrap(archive.recordings.first)
        XCTAssertEqual(archive.schemaVersion, 2)
        XCTAssertEqual(recording.recordingID.uuidString, "33333333-3333-4333-8333-333333333333")
        XCTAssertEqual(recording.vehicleID.uuidString, "22222222-2222-4222-8222-222222222222")
        XCTAssertEqual(recording.startedAt.timeIntervalSince1970, 1_767_268_800.125, accuracy: 0.000_001)
    }

    func testLatestSignalsBoostAndSamplesStayIndependent() throws {
        let original = try XCTUnwrap(DriveLineArchive.decoded(fixture("golden-v2")).recordings.first)
        var gpsOnly = original
        gpsOnly.recordingID = UUID()
        gpsOnly.startedAt = original.endedAt.addingTimeInterval(100)
        gpsOnly.endedAt = gpsOnly.startedAt.addingTimeInterval(10)
        gpsOnly.signalSamples = []
        let latest = DriveLineMetricPolicy.latestObservations([original, gpsOnly])
        XCTAssertEqual(latest["rpm"]?.value, 1700)
        XCTAssertEqual(DriveLineMetricPolicy.boostGaugeKpa(observations: latest, at: original.endedAt)?.value, 35)
        XCTAssertNil(DriveLineMetricPolicy.boostGaugeKpa(observations: latest, at: original.endedAt.addingTimeInterval(100)))
        var sample = original
        sample.recordingID = UUID()
        sample.isSample = true
        sample.signalSamples = [DriveLineSignalSample(timestamp: original.endedAt.addingTimeInterval(1), values: ["rpm": 9999])]
        XCTAssertEqual(DriveLineMetricPolicy.latestObservations([original, sample])["rpm"]?.value, 1700)
    }

    func testFillQuantityIsSeparateFromTripFuelAndSamplesExcluded() throws {
        let archive = try DriveLineArchive.decoded(fixture("golden-v2"))
        XCTAssertEqual(archive.recordings.first?.tripFuelLitres, 0.02)
        XCTAssertEqual(archive.fuelEntries.first?.litresPurchased, 42.5)
        let vehicleID = try XCTUnwrap(archive.vehicles.first?.id)
        let first = DriveLineFuelEntry(vehicleID: vehicleID, date: .distantPast, litresPurchased: 40,
                                       totalCost: 60, odometerKm: 10_000, isFullFill: true)
        let partial = DriveLineFuelEntry(vehicleID: vehicleID, date: .distantPast, litresPurchased: 10,
                                         totalCost: 15, odometerKm: 10_200, isFullFill: false)
        let last = DriveLineFuelEntry(vehicleID: vehicleID, date: .distantPast, litresPurchased: 20,
                                      totalCost: 30, odometerKm: 10_600, isFullFill: true)
        let sample = DriveLineFuelEntry(vehicleID: vehicleID, date: .distantPast, litresPurchased: 100,
                                        totalCost: 0, odometerKm: 10_700, isFullFill: true, isSample: true)
        XCTAssertEqual(try XCTUnwrap(DriveLineMetricPolicy.tankToTankEconomy([first, partial, last, sample])), 5, accuracy: 0.000_001)
        XCTAssertEqual(DriveLineMetricPolicy.normalizedDPFRegenTrigger(43), 43)
        XCTAssertNil(DriveLineMetricPolicy.normalizedDPFRegenTrigger(101))
    }

    func testCoverageCountsStationaryGPSAndNegativeSignalsWithoutBridgingGaps() {
        let start=Date(timeIntervalSince1970:1_767_268_800)
        let vehicleID=UUID(),recordingID=UUID()
        let gps=[0.0,10.0,50.0].map { DriveLineGPSPoint(timestamp:start.addingTimeInterval($0),latitude:49,longitude:-124,horizontalAccuracyM:5) }
        let signals=[0.0,10.0,30.0].map { DriveLineSignalSample(timestamp:start.addingTimeInterval($0),values:["outsideC":-5]) }
        let recording=DriveLineRecording(recordingID:recordingID,vehicleID:vehicleID,name:"Coverage",startedAt:start,
                                         endedAt:start.addingTimeInterval(50),sourceIDs:["gps","obd"],gpsPoints:gps,signalSamples:signals)
        let coverage=DriveLineMetricPolicy.coverageSummaries(recording)
        XCTAssertEqual(coverage.first(where:{$0.key == "gps"})?.observedSeconds,10)
        XCTAssertEqual(coverage.first(where:{$0.key == "outsideC"})?.observedSeconds,10)
    }

    func testPhase4AnnotationsAreSidecarStateAndDoNotChangeArchiveBytes() throws {
        let archive = try DriveLineArchive.decoded(fixture("golden-v2"))
        let before = try archive.encoded()
        let recordingID = try XCTUnwrap(archive.recordings.first?.recordingID)
        let annotation = DriveLineJourneyAnnotation(recordingID: recordingID, purpose: .business,
            reviewed: true, note: "Customer visit", startPlace: "Office", finishPlace: "Customer")
        let roundTrip = try DriveLineJSON.decoder().decode(DriveLineJourneyAnnotation.self,
            from: DriveLineJSON.encoder().encode(annotation))
        XCTAssertEqual(roundTrip.recordingID, recordingID)
        XCTAssertEqual(roundTrip.purpose, .business)
        XCTAssertTrue(roundTrip.reviewed)
        XCTAssertEqual(try archive.encoded(), before, "Sidecar annotations must not mutate an archive or queued payload")
    }

    func testPhase4JourneySummaryTimelineGapsAndCursorUseOnlyRecordedEvidence() throws {
        var recording = try XCTUnwrap(DriveLineArchive.decoded(fixture("golden-v2")).recordings.first)
        let start = recording.startedAt
        recording.endedAt = start.addingTimeInterval(60)
        recording.gpsPoints = [
            DriveLineGPSPoint(timestamp:start,latitude:49,longitude:-124,horizontalAccuracyM:5),
            DriveLineGPSPoint(timestamp:start.addingTimeInterval(10),latitude:49.0001,longitude:-124,horizontalAccuracyM:5),
            DriveLineGPSPoint(timestamp:start.addingTimeInterval(50),latitude:49.0002,longitude:-124,horizontalAccuracyM:5)
        ]
        recording.signalSamples = [
            DriveLineSignalSample(timestamp:start,values:["rpm":1_500,"fuelRateLph":3],sourceID:"obd"),
            DriveLineSignalSample(timestamp:start.addingTimeInterval(10),values:["rpm":1_600,"fuelRateLph":3],sourceID:"obd"),
            DriveLineSignalSample(timestamp:start.addingTimeInterval(40),values:["rpm":1_700,"dpfRegenTrigger":42],sourceID:"obd")
        ]
        recording.tripFuelLitres = nil
        let summary = DriveLineJourneyPolicy.summary(for: recording)
        XCTAssertEqual(summary.quality,.degraded)
        XCTAssertEqual(Set(summary.gaps.map(\.sourceID)),Set(["gps","obd"]))
        XCTAssertNil(summary.metrics.tripFuelLitres)
        XCTAssertTrue(summary.statement.contains("below the required 80% threshold"))
        let timeline = DriveLineJourneyPolicy.timeline(for: recording)
        XCTAssertTrue(timeline.contains(where:{$0.kind == "gpsLost" && $0.endTimestamp != nil}))
        XCTAssertTrue(timeline.contains(where:{$0.kind == "obdRecovered"}))
        XCTAssertTrue(timeline.contains(where:{$0.kind == "dpfRegenTriggerObserved" && $0.note?.contains("not physical DPF fullness") == true}))
        let cursor = DriveLineJourneyPolicy.cursor(at:start.addingTimeInterval(25),recording:recording,signalKeys:["rpm","missing"])
        XCTAssertNil(cursor.observations["rpm"],"A cursor cannot forward-fill across a 15-second signal gap")
        XCTAssertNil(cursor.observations["missing"])
    }

    func testPhase4SignalsKeepBreaksDuplicatesAndDerivedBoostProvenance() throws {
        var recording = try XCTUnwrap(DriveLineArchive.decoded(fixture("golden-v2")).recordings.first)
        let start = recording.startedAt
        recording.signalSamples += [
            DriveLineSignalSample(timestamp:start.addingTimeInterval(100),values:["rpm":2_000],sourceID:"obd"),
            DriveLineSignalSample(timestamp:start.addingTimeInterval(101),values:["boostAbsoluteKpa":136],sourceID:"obd")
        ]
        let rpm = DriveLineJourneyPolicy.signalSeries("rpm",unit:"rpm",recording:recording)
        XCTAssertEqual(rpm.provenance,.measured)
        XCTAssertEqual(rpm.segments.count,2)
        let boost = DriveLineJourneyPolicy.signalSeries("boostKpa",unit:"kPa gauge",recording:recording)
        XCTAssertEqual(boost.provenance,.derived)
        XCTAssertEqual(boost.algorithmIdentifier,"driveline.boost-gauge.v1")
        XCTAssertEqual(boost.segments.flatMap{$0}.first?.value,30)
        XCTAssertFalse(boost.segments.flatMap{$0}.contains(where:{$0.timestamp == start.addingTimeInterval(101)}),
                       "A stale barometer must not create derived boost")
    }

    func testPhase4FuelLedgerUsesOnlyValidFullFillBoundariesAndKeepsTripFuelSeparate() throws {
        let vehicleID=UUID(),start=Date(timeIntervalSince1970:1_700_000_000)
        let first=DriveLineFuelEntry(vehicleID:vehicleID,date:start,litresPurchased:40,totalCost:60,odometerKm:10_000,isFullFill:true)
        let partial=DriveLineFuelEntry(vehicleID:vehicleID,date:start.addingTimeInterval(1),litresPurchased:10,totalCost:17,odometerKm:10_200,isFullFill:false)
        let last=DriveLineFuelEntry(vehicleID:vehicleID,date:start.addingTimeInterval(2),litresPurchased:20,totalCost:36,odometerKm:10_600,isFullFill:true)
        let sample=DriveLineFuelEntry(vehicleID:vehicleID,date:start.addingTimeInterval(3),litresPurchased:100,totalCost:0,odometerKm:10_700,isFullFill:true,isSample:true)
        let ledger=DriveLineJourneyPolicy.fuelLedger([first,partial,last,sample])
        XCTAssertEqual(ledger.count,3)
        XCTAssertNil(ledger[0].tankEconomyL100Km)
        XCTAssertNil(ledger[1].tankEconomyL100Km)
        XCTAssertEqual(try XCTUnwrap(ledger[2].tankEconomyL100Km),5,accuracy:0.000_001)
        XCTAssertEqual(try XCTUnwrap(ledger[2].costPerLitre),1.8,accuracy:0.000_001)

        let recording=DriveLineRecording(recordingID:UUID(),vehicleID:vehicleID,name:"Measured",startedAt:start,
            endedAt:start.addingTimeInterval(10),sourceIDs:["obd"],
            signalSamples:[DriveLineSignalSample(timestamp:start,values:["fuelRateLph":3]),
                           DriveLineSignalSample(timestamp:start.addingTimeInterval(10),values:["fuelRateLph":3])],
            recordedDistanceKm:1)
        let series=DriveLineJourneyPolicy.tripFuelSeries([recording])
        XCTAssertEqual(series.count,1)
        XCTAssertEqual(series[0].litres,3.0/360.0,accuracy:0.000_001)
        XCTAssertEqual(ledger[2].entry.litresPurchased,20)
    }

    func testPhase4FuelLedgerNeverCrossesVehicleBoundaries() throws {
        let a=UUID(),b=UUID(),date=Date(timeIntervalSince1970:1_700_000_000)
        let entries=[
            DriveLineFuelEntry(vehicleID:a,date:date,litresPurchased:40,totalCost:60,odometerKm:1_000,isFullFill:true),
            DriveLineFuelEntry(vehicleID:b,date:date.addingTimeInterval(1),litresPurchased:30,totalCost:50,odometerKm:1_100,isFullFill:true),
            DriveLineFuelEntry(vehicleID:a,date:date.addingTimeInterval(2),litresPurchased:20,totalCost:32,odometerKm:1_400,isFullFill:true)
        ]
        let ledger=DriveLineJourneyPolicy.fuelLedger(entries)
        XCTAssertNil(ledger.first(where:{$0.entry.vehicleID == b})?.tankEconomyL100Km)
        XCTAssertEqual(try XCTUnwrap(ledger.first(where:{$0.entry.vehicleID == a && $0.entry.odometerKm == 1_400})?.tankEconomyL100Km),5,accuracy:0.000_001)
    }

    func testPhase4GPSOnlyOBDOnlyAndMixedQualityRemainDistinct() {
        let vehicleID=UUID(),start=Date(timeIntervalSince1970:1_700_000_000),end=start.addingTimeInterval(10)
        let gps=[DriveLineGPSPoint(timestamp:start,latitude:49,longitude:-124),DriveLineGPSPoint(timestamp:end,latitude:49.001,longitude:-124)]
        let obd=[DriveLineSignalSample(timestamp:start,values:["rpm":1_500],sourceID:"obd"),DriveLineSignalSample(timestamp:end,values:["rpm":1_600],sourceID:"obd")]
        let gpsOnly=DriveLineJourneyPolicy.summary(for:DriveLineRecording(recordingID:UUID(),vehicleID:vehicleID,name:"GPS",startedAt:start,endedAt:end,sourceIDs:["gps"],gpsPoints:gps))
        let obdOnly=DriveLineJourneyPolicy.summary(for:DriveLineRecording(recordingID:UUID(),vehicleID:vehicleID,name:"OBD",startedAt:start,endedAt:end,sourceIDs:["obd"],signalSamples:obd))
        let mixed=DriveLineJourneyPolicy.summary(for:DriveLineRecording(recordingID:UUID(),vehicleID:vehicleID,name:"Mixed",startedAt:start,endedAt:end,sourceIDs:["gps","obd"],gpsPoints:gps,signalSamples:obd))
        XCTAssertEqual(gpsOnly.quality,.limited);XCTAssertNotNil(gpsOnly.gpsCoverage);XCTAssertNil(gpsOnly.obdCoverage)
        XCTAssertEqual(obdOnly.quality,.limited);XCTAssertNil(obdOnly.gpsCoverage);XCTAssertNotNil(obdOnly.obdCoverage)
        XCTAssertEqual(mixed.quality,.complete);XCTAssertEqual(Set(mixed.sourceKinds),Set([.gps,.obd]))
    }

    func testPhase4MissingInputsNeverFabricateEvidence() {
        let recording=DriveLineRecording(recordingID:UUID(),vehicleID:UUID(),name:"Empty",startedAt:Date(timeIntervalSince1970:100),endedAt:Date(timeIntervalSince1970:120),sourceIDs:[])
        let summary=DriveLineJourneyPolicy.summary(for:recording)
        XCTAssertEqual(summary.quality,.unavailable)
        XCTAssertNil(summary.metrics.distanceKm);XCTAssertNil(summary.metrics.tripFuelLitres)
        XCTAssertNil(summary.gpsCoverage);XCTAssertNil(summary.obdCoverage)
        let events=DriveLineJourneyPolicy.timeline(for:recording)
        XCTAssertEqual(Set(events.map(\.kind)),Set(["recordingStarted","recordingFinished"]))
        XCTAssertTrue(DriveLineJourneyPolicy.signalSeries("dpfRegenTrigger",unit:"%",recording:recording).segments.isEmpty)
    }

    func testExtendedEventDecodesLegacyShapeAndExtensionDataSurvivesRoundTrip() throws {
        let json=#"{"id":"99999999-9999-4999-8999-999999999999","timestamp":1700000000,"kind":"scannerDisconnected","note":"Observed disconnect"}"#.data(using:.utf8)!
        let event=try DriveLineJSON.decoder().decode(DriveLineTripEvent.self,from:json)
        XCTAssertNil(event.endTimestamp)
        XCTAssertEqual(event.evidenceReferences,[])
        var archive=try DriveLineArchive.decoded(fixture("golden-v2"))
        archive.extensionData["future.phase"] = Data([0,1,2,3])
        XCTAssertEqual(try DriveLineArchive.decoded(archive.encoded()).extensionData["future.phase"],Data([0,1,2,3]))
    }

    func testReceiptAttachmentsRoundTripDeduplicateAndPermitMissingFiles() throws {
        let vehicle=DriveLineVehicle(id:UUID(),name:"Synthetic vehicle")
        let bytes=Data("sanitized receipt fixture".utf8)
        let digest=SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
        let metadata=DriveLineReceiptMetadata(fileName:"receipt.txt",mediaType:"text/plain",byteCount:bytes.count,sha256:digest)
        let first=DriveLineFuelEntry(vehicleID:vehicle.id,date:Date(timeIntervalSince1970:100),litresPurchased:40,totalCost:70,currencyCode:"CAD",odometerKm:1_000,isFullFill:true,receipt:metadata)
        let second=DriveLineFuelEntry(vehicleID:vehicle.id,date:Date(timeIntervalSince1970:200),litresPurchased:20,totalCost:35,currencyCode:"USD",odometerKm:1_400,isFullFill:true,receipt:metadata)
        let producer=DriveLineProducer(app:"Tests",version:"1",platform:"test")
        let complete=DriveLineArchive(producer:producer,sources:[],vehicles:[vehicle],recordings:[],fuelEntries:[first,second],receiptFiles:[digest:bytes])
        let restored=try DriveLineArchive.decoded(complete.encoded())
        XCTAssertEqual(restored.receiptFiles,[digest:bytes])
        XCTAssertEqual(restored.fuelEntries.map(\.receipt),[metadata,metadata])

        let missing=DriveLineArchive(producer:producer,sources:[],vehicles:[vehicle],recordings:[],fuelEntries:[first])
        XCTAssertTrue(try DriveLineArchive.decoded(missing.encoded()).receiptFiles.isEmpty,
                      "Missing receipt bytes must preserve metadata without fabricating a file")
        let corrupt=DriveLineArchive(producer:producer,sources:[],vehicles:[vehicle],recordings:[],fuelEntries:[first],receiptFiles:[digest:Data("different bytes".utf8)])
        XCTAssertThrowsError(try corrupt.encoded())
    }

    func testFuelCurrencyRequiresThreeAsciiLetters() throws {
        let vehicle=DriveLineVehicle(id:UUID(),name:"Synthetic vehicle")
        let producer=DriveLineProducer(app:"Tests",version:"1",platform:"test")
        for currency in ["", "CA", "CAD1", "C$D"] {
            let fill=DriveLineFuelEntry(vehicleID:vehicle.id,date:Date(timeIntervalSince1970:100),litresPurchased:1,totalCost:1,currencyCode:currency,odometerKm:1,isFullFill:true)
            XCTAssertThrowsError(try DriveLineArchive(producer:producer,sources:[],vehicles:[vehicle],recordings:[],fuelEntries:[fill]).encoded())
        }
        let lowercase=DriveLineFuelEntry(vehicleID:vehicle.id,date:Date(timeIntervalSince1970:100),litresPurchased:1,totalCost:1,currencyCode:"cad",odometerKm:1,isFullFill:true)
        XCTAssertNoThrow(try DriveLineArchive(producer:producer,sources:[],vehicles:[vehicle],recordings:[],fuelEntries:[lowercase]).encoded())
    }

    func testPhase6RegistrySearchGroupingAliasesSourcesUnitsAndUnknownSignals() {
        let start=Date(timeIntervalSince1970:1_700_000_000)
        let recording=DriveLineRecording(recordingID:UUID(),vehicleID:UUID(),name:"Signals",startedAt:start,
            endedAt:start.addingTimeInterval(20),sourceIDs:["scanner-a"],signalSamples:[
                DriveLineSignalSample(timestamp:start,values:["rpm":1_500,"vendor.7e8.mystery":12],sourceID:"scanner-a"),
                DriveLineSignalSample(timestamp:start.addingTimeInterval(10),values:["rpm":1_600,"dpfRegenTrigger":42],sourceID:"scanner-a")
            ])
        XCTAssertEqual(DriveLineJourneyPolicy.signalDescriptors(recording:recording,query:"tachometer").map(\.key),["rpm"])
        XCTAssertTrue(DriveLineJourneyPolicy.signalDescriptors(recording:recording,query:"scanner-a").contains(where:{$0.key == "vendor.7e8.mystery"}))
        XCTAssertTrue(DriveLineJourneyPolicy.signalDescriptors(recording:recording,query:"rpm").contains(where:{$0.key == "rpm"}))
        let unknown=DriveLineJourneyPolicy.signalDescriptor("vendor.7e8.mystery",recording:recording)
        XCTAssertEqual(unknown.displayName,"vendor.7e8.mystery")
        XCTAssertEqual(unknown.group,.otherUnknown)
        XCTAssertNil(unknown.unit)
        XCTAssertFalse(unknown.metadataAvailable)
        XCTAssertEqual(DriveLineJourneyPolicy.signalDescriptor("dpfRegenTrigger",recording:recording).displayName,"DPF regeneration trigger · normalized")
    }

    func testPhase6VisibleRangeStatisticsUseOnlyFiniteRecordedObservations() {
        let start=Date(timeIntervalSince1970:1_700_000_000)
        let recording=DriveLineRecording(recordingID:UUID(),vehicleID:UUID(),name:"Irregular",startedAt:start,
            endedAt:start.addingTimeInterval(100),sourceIDs:["obd"],signalSamples:[
                DriveLineSignalSample(timestamp:start,values:["rpm":1_000],sourceID:"obd"),
                DriveLineSignalSample(timestamp:start.addingTimeInterval(3),values:["rpm":2_000],sourceID:"obd"),
                DriveLineSignalSample(timestamp:start.addingTimeInterval(9),values:["rpm":Double.nan],sourceID:"obd"),
                DriveLineSignalSample(timestamp:start.addingTimeInterval(40),values:["rpm":4_000],sourceID:"obd"),
                DriveLineSignalSample(timestamp:start.addingTimeInterval(100),values:["rpm":8_000],sourceID:"obd")
            ])
        let series=DriveLineJourneyPolicy.signalSeries("rpm",unit:"rpm",recording:recording)
        XCTAssertEqual(series.segments.count,3,"Long gaps must remain separate segments")
        let range=DateInterval(start:start,end:start.addingTimeInterval(40))
        let stats=DriveLineJourneyPolicy.signalStatistics(series,at:start.addingTimeInterval(40),visibleRange:range)
        XCTAssertEqual(stats.observationCount,3)
        XCTAssertEqual(stats.minimum,1_000)
        XCTAssertEqual(stats.maximum,4_000)
        XCTAssertEqual(try XCTUnwrap(stats.recordedObservationAverage),7_000.0/3.0,accuracy:0.000_001)
        XCTAssertEqual(stats.current?.value,4_000)
        XCTAssertEqual(stats.freshness,.fresh)
        XCTAssertEqual(DriveLineJourneyPolicy.signalStatistics(series,at:start.addingTimeInterval(70),visibleRange:range).freshness,.stale)
        XCTAssertEqual(DriveLineJourneyPolicy.signalStatistics(series,at:start.addingTimeInterval(-1),visibleRange:range).freshness,.unavailable)
        let beforeFuture=DriveLineJourneyPolicy.signalStatistics(series,at:start.addingTimeInterval(35),visibleRange:range)
        XCTAssertNil(beforeFuture.current,"A future observation must never be presented at an earlier cursor")
        XCTAssertEqual(beforeFuture.freshness,.stale)
    }

    func testPhase6SharedCursorSynchronizesSignalAndRecordedRouteWithoutForwardFill() {
        let start=Date(timeIntervalSince1970:1_700_000_000)
        let gps=[0.0,10.0,20.0].map { DriveLineGPSPoint(timestamp:start.addingTimeInterval($0),latitude:49+$0*0.00001,longitude:-124,horizontalAccuracyM:4,speedMps:10,sourceID:"gps") }
        let samples=[0.0,10.0,40.0].map { DriveLineSignalSample(timestamp:start.addingTimeInterval($0),values:["rpm":1_500+$0],sourceID:"obd") }
        let recording=DriveLineRecording(recordingID:UUID(),vehicleID:UUID(),name:"Cursor",startedAt:start,
            endedAt:start.addingTimeInterval(40),sourceIDs:["gps","obd"],gpsPoints:gps,signalSamples:samples)
        let atTen=DriveLineJourneyPolicy.cursor(at:start.addingTimeInterval(10),recording:recording,signalKeys:["rpm","gps.speedKph"])
        XCTAssertEqual(atTen.gpsPoint?.timestamp,start.addingTimeInterval(10))
        XCTAssertEqual(atTen.observations["rpm"]?.timestamp,atTen.gpsPoint?.timestamp)
        XCTAssertEqual(atTen.observations["gps.speedKph"]?.value,36)
        let beforeTen=DriveLineJourneyPolicy.cursor(at:start.addingTimeInterval(9),recording:recording,signalKeys:["rpm"])
        XCTAssertEqual(beforeTen.gpsPoint?.timestamp,start,"A future GPS observation must not move the route marker early")
        XCTAssertEqual(beforeTen.observations["rpm"]?.timestamp,start,"A future scanner observation must not be forward-filled")
        let inGap=DriveLineJourneyPolicy.cursor(at:start.addingTimeInterval(25),recording:recording,signalKeys:["rpm"])
        XCTAssertNil(inGap.observations["rpm"])
        XCTAssertEqual(inGap.gpsPoint?.timestamp,start.addingTimeInterval(20))
    }

    func testPhase6ElapsedAndDistanceAlignmentUseRecordedRouteProgressOnly() throws {
        let start=Date(timeIntervalSince1970:1_700_000_000),vehicleID=UUID()
        let gps=[0.0,10.0,20.0,30.0,40.0].map { seconds in
            DriveLineGPSPoint(timestamp:start.addingTimeInterval(seconds),latitude:49+seconds*0.00001,longitude:-124,horizontalAccuracyM:4,speedMps:10)
        }
        let samples=[0.0,10.0,20.0,30.0,40.0].map { DriveLineSignalSample(timestamp:start.addingTimeInterval($0),values:["rpm":1_500+$0]) }
        let mixed=DriveLineRecording(recordingID:UUID(),vehicleID:vehicleID,name:"Mixed",startedAt:start,
            endedAt:start.addingTimeInterval(40),sourceIDs:["gps","obd"],gpsPoints:gps,signalSamples:samples)
        XCTAssertTrue(DriveLineJourneyPolicy.distanceAlignmentAvailability(mixed).isAvailable)
        XCTAssertEqual(DriveLineJourneyPolicy.alignmentExtent(mixed,alignment:.elapsedTime),0...40)
        let distance=try XCTUnwrap(DriveLineJourneyPolicy.alignmentExtent(mixed,alignment:.travelledDistance))
        XCTAssertGreaterThan(distance.upperBound,0)
        let series=DriveLineJourneyPolicy.signalSeries("rpm",unit:"rpm",recording:mixed)
        let aligned=DriveLineJourneyPolicy.alignedSegments(series,recording:mixed,alignment:.travelledDistance).flatMap{$0}
        XCTAssertEqual(aligned.count,5)
        let position=try XCTUnwrap(DriveLineJourneyPolicy.position(at:start.addingTimeInterval(20),recording:mixed,alignment:.travelledDistance))
        XCTAssertEqual(DriveLineJourneyPolicy.timestamp(at:position,recording:mixed,alignment:.travelledDistance),start.addingTimeInterval(20))

        let obdOnly=DriveLineRecording(recordingID:UUID(),vehicleID:vehicleID,name:"OBD",startedAt:start,
            endedAt:start.addingTimeInterval(40),sourceIDs:["obd"],signalSamples:samples)
        XCTAssertFalse(DriveLineJourneyPolicy.distanceAlignmentAvailability(obdOnly).isAvailable)
        XCTAssertTrue(DriveLineJourneyPolicy.distanceAlignmentAvailability(obdOnly).explanation.contains("no GPS"))
        var sparse=mixed;sparse.recordingID=UUID();sparse.gpsPoints=[gps[0],gps[1]]
        XCTAssertFalse(DriveLineJourneyPolicy.distanceAlignmentAvailability(sparse).isAvailable)
        XCTAssertTrue(DriveLineJourneyPolicy.distanceAlignmentAvailability(sparse).explanation.contains("50%"))
    }

    func testPhase6BoostFreshnessDPFLanguageAndComparisonIdentity() throws {
        let start=Date(timeIntervalSince1970:1_700_000_000),vehicleID=UUID()
        let first=DriveLineRecording(recordingID:UUID(),vehicleID:vehicleID,name:"First",startedAt:start,
            endedAt:start.addingTimeInterval(120),sourceIDs:["obd"],signalSamples:[
                DriveLineSignalSample(timestamp:start,values:["barometricKpa":100],sourceID:"barometer"),
                DriveLineSignalSample(timestamp:start.addingTimeInterval(70),values:["boostAbsoluteKpa":135,"dpfRegenTrigger":60],sourceID:"obd"),
                DriveLineSignalSample(timestamp:start.addingTimeInterval(80),values:["boostAbsoluteKpa":140],sourceID:"obd")
            ])
        let boost=DriveLineJourneyPolicy.signalSeries("boostKpa",unit:"kPa gauge",recording:first)
        XCTAssertEqual(boost.algorithmIdentifier,"driveline.boost-gauge.v1")
        XCTAssertEqual(boost.algorithmVersion,"1")
        XCTAssertEqual(boost.segments.flatMap{$0}.map(\.value),[35],"A barometer older than 75 seconds must not derive boost")
        XCTAssertTrue(DriveLineMetricPolicy.dpfRegenTriggerExplanation.contains("not physical DPF fullness"))

        var shorter=first;shorter.recordingID=UUID();shorter.name="Shorter";shorter.endedAt=start.addingTimeInterval(60);shorter.signalSamples=[]
        XCTAssertNil(DriveLineJourneyPolicy.comparisonIneligibility(primary:first,candidate:shorter))
        XCTAssertNotEqual(DriveLineJourneyPolicy.alignmentExtent(first,alignment:.elapsedTime),DriveLineJourneyPolicy.alignmentExtent(shorter,alignment:.elapsedTime))
        XCTAssertTrue(DriveLineJourneyPolicy.signalSeries("rpm",unit:"rpm",recording:shorter).segments.isEmpty)
        var other=shorter;other.recordingID=UUID();other.vehicleID=UUID()
        XCTAssertTrue(DriveLineJourneyPolicy.comparisonIneligibility(primary:first,candidate:other)?.contains("same vehicle") == true)
    }

    func testPhase7VINDecoderSuggestsReviewable2014CorrectionForFictionalVolkswagen() throws {
        let result=try DriveLineVINDecoder.decode("3VWAAAAA0EM000001",enteredModelYear:2013,currentYear:2026)
        XCTAssertEqual(result.normalizedVIN,"3VWAAAAA0EM000001")
        XCTAssertEqual(result.manufacturer,"Volkswagen")
        XCTAssertEqual(result.candidateModelYears,[1984,2014])
        XCTAssertEqual(result.suggestedModelYear,2014)
        XCTAssertTrue(result.checksumValidated)
    }

    func testPhase7VINDecoderKeepsAmbiguousCycleAndUnknownWMIHonest() throws {
        let result=try DriveLineVINDecoder.decode("ZZZAAAAA0EM000001",currentYear:2026)
        XCTAssertNil(result.manufacturer)
        XCTAssertNil(result.suggestedModelYear)
        XCTAssertTrue(result.modelYearIsAmbiguous)
        XCTAssertEqual(result.candidateModelYears,[1984,2014])
    }

    func testPhase7VINDecoderRejectsInvalidCharactersLengthAndNorthAmericanChecksum() {
        XCTAssertThrowsError(try DriveLineVINDecoder.decode("3VWAAAAA1EM000001",enteredModelYear:2013,currentYear:2026))
        XCTAssertThrowsError(try DriveLineVINDecoder.decode("3VWAAAAA0EM00000I",enteredModelYear:2013,currentYear:2026))
        XCTAssertThrowsError(try DriveLineVINDecoder.decode("3VWAAAAA0EM0000",enteredModelYear:2013,currentYear:2026))
    }

    func testPhase7VehicleContractAddsGarageFieldsWithoutBreakingLegacyDecode() throws {
        let id=UUID()
        let legacy="{\"id\":\"\(id.uuidString)\",\"name\":\"Legacy\",\"year\":\"2013\",\"make\":\"Volkswagen\",\"model\":\"Jetta\"}".data(using:.utf8)!
        let decoded=try JSONDecoder().decode(DriveLineVehicle.self,from:legacy)
        XCTAssertEqual(decoded.id,id)
        XCTAssertEqual(decoded.configuredSources,[])
        XCTAssertFalse(decoded.isArchived)

        let vehicle=DriveLineVehicle(id:id,name:"Fictional Jetta",year:"2013",make:"Volkswagen",model:"Jetta",
            vehicleClass:.passengerCar,fuelType:"Diesel",vin:"3VWAAAAA0EM000001",preferredUnits:.metric,
            preferredGPS:.phone,configuredSources:[.manual,.phoneGPS,.obdScanner])
        XCTAssertEqual(try JSONDecoder().decode(DriveLineVehicle.self,from:JSONEncoder().encode(vehicle)),vehicle)
    }

    func testPhase9RenderingReductionPreservesGapsIsolatedPointsExtremaAndOriginalEvidence() throws {
        let start=DriveLinePerformanceFixture.baseDate
        var first:[DriveLineSignalPoint]=[]
        first.reserveCapacity(5_000)
        for index in 0..<5_000 {
            let value:Double
            if index == 1_337 { value = -900 }
            else if index == 4_321 { value = 1_200 }
            else { value = Double(index%100) }
            first.append(DriveLineSignalPoint(timestamp:start.addingTimeInterval(Double(index)),value:value,sourceID:"sanitized-obd"))
        }
        let isolated=DriveLineSignalPoint(timestamp:start.addingTimeInterval(10_000),value:77,sourceID:"sanitized-obd")
        let original=[first,[isolated]]
        let rendered=DriveLineRenderingPolicy.signalSegments(original,limit:240)

        XCTAssertEqual(original[0].count,5_000,"Display reduction must never mutate the original evidence")
        XCTAssertEqual(rendered.count,2,"Recorded gaps remain separate segments")
        XCTAssertEqual(rendered[1],[isolated],"An isolated recorded point must remain visible")
        XCTAssertLessThanOrEqual(rendered.flatMap{$0}.count,242)
        let renderedValues=rendered.flatMap{$0}.map{$0.value}
        XCTAssertEqual(renderedValues.min(),-900)
        XCTAssertEqual(renderedValues.max(),1_200)
        XCTAssertEqual(original[0][1_337].value,-900,"Cursor/statistics retain access to original observations")
    }

    func testPhase9SanitizedCorpusHasRequiredScaleAndNeverContributesToRealTotals() {
        let started=ContinuousClock.now
        var observations=0
        var gpsOnly=0,obdOnly=0,mixed=0,longGap=false
        for index in 0..<DriveLinePerformanceFixture.journeyCount {
            autoreleasepool {
                let recording=DriveLinePerformanceFixture.recording(at:index)
                observations += recording.gpsPoints.count + recording.signalSamples.count
                if !recording.gpsPoints.isEmpty && recording.signalSamples.isEmpty { gpsOnly += 1 }
                else if recording.gpsPoints.isEmpty && !recording.signalSamples.isEmpty { obdOnly += 1 }
                else { mixed += 1 }
                let timestamps=recording.gpsPoints.map(\.timestamp)+recording.signalSamples.map(\.timestamp)
                let ordered=timestamps.sorted()
                longGap = longGap || zip(ordered,ordered.dropFirst()).contains { $1.timeIntervalSince($0)>60 }
                XCTAssertTrue(recording.isSample)
            }
        }
        let elapsed=ContinuousClock.now-started
        print("PHASE9_METRIC corpus_generation_seconds=\(elapsed.components.seconds).\(abs(elapsed.components.attoseconds)/1_000_000_000_000_000)")
        XCTAssertEqual(observations,1_000_000)
        XCTAssertEqual(DriveLinePerformanceFixture.vehicles.count,4)
        XCTAssertTrue(DriveLinePerformanceFixture.vehicles.contains(where:\.isArchived))
        XCTAssertEqual(DriveLinePerformanceFixture.fuelEntries.count,40)
        XCTAssertTrue(DriveLinePerformanceFixture.fuelEntries.allSatisfy{$0.isSample && $0.receipt != nil})
        XCTAssertEqual(Set(DriveLinePerformanceFixture.transferStates),["queued","failed","complete"])
        XCTAssertGreaterThan(gpsOnly,0);XCTAssertGreaterThan(obdOnly,0);XCTAssertGreaterThan(mixed,0);XCTAssertTrue(longGap)
        let samples=(0..<3).map { DriveLinePerformanceFixture.recording(at:$0) }
        XCTAssertTrue(DriveLineMetricPolicy.latestObservations(samples).isEmpty,"Sample observations must not become real latest values")
    }

    func testPhase9ThirtyMinuteRecordingAndPlaybackUseOriginalEvidence() throws {
        let recording=DriveLinePerformanceFixture.thirtyMinuteRecording()
        XCTAssertEqual(recording.endedAt.timeIntervalSince(recording.startedAt),1_800)
        XCTAssertEqual(recording.gpsPoints.count,1_801)
        XCTAssertEqual(recording.signalSamples.count,1_801)
        let metrics=DriveLineMetricPolicy.metrics(for:recording)
        XCTAssertEqual(metrics.durationSeconds,1_800)
        let series=DriveLineJourneyPolicy.signalSeries("rpm",unit:"rpm",recording:recording)
        let rendered=DriveLineRenderingPolicy.signalSegments(series.segments,limit:300)
        XCTAssertLessThanOrEqual(rendered.flatMap{$0}.count,300)
        for second in stride(from:0,through:1_800,by:5) {
            let date=recording.startedAt.addingTimeInterval(Double(second))
            let cursor=DriveLineJourneyPolicy.cursor(at:date,recording:recording,signalKeys:["rpm"])
            XCTAssertNotNil(cursor.observations["rpm"])
            XCTAssertNotNil(cursor.gpsPoint)
        }
        XCTAssertEqual(series.segments.flatMap{$0}.count,1_801,"Playback rendering must not reduce stored evidence")
    }

    func testPhase9RepresentativeLibraryChartMapAndArchiveOperationsRemainBounded() throws {
        func measured<T>(_ label:String,_ operation:()->T)->T {
            let started=ContinuousClock.now
            let result=operation()
            let elapsed=ContinuousClock.now-started
            let milliseconds=Double(elapsed.components.seconds)*1_000 +
                Double(elapsed.components.attoseconds)/1_000_000_000_000_000
            print("PHASE9_METRIC \(label)_milliseconds=\(String(format:"%.3f",milliseconds))")
            XCTAssertLessThan(milliseconds,15_000,"\(label) exceeded the deliberately generous regression ceiling")
            return result
        }

        let summaries=measured("library_filter_500") {
            (0..<DriveLinePerformanceFixture.journeyCount).map {
                DriveLinePerformanceFixture.recording(at:$0,observationCount:20)
            }.filter { $0.name.localizedCaseInsensitiveContains("sample journey") }
        }
        XCTAssertEqual(summaries.count,500)

        let analysisRecording=DriveLinePerformanceFixture.recording(at:2,observationCount:100_000)
        let descriptors=measured("signal_search") {
            DriveLineJourneyPolicy.groupedSignalDescriptors(recording:analysisRecording,query:"engine")
        }
        XCTAssertFalse(descriptors.isEmpty)
        let series=measured("signal_series_50000") {
            DriveLineJourneyPolicy.signalSeries("rpm",unit:"rpm",recording:analysisRecording)
        }
        XCTAssertEqual(series.segments.flatMap{$0}.count,50_000)
        let rendered=measured("chart_prepare_50000") {
            DriveLineRenderingPolicy.signalSegments(series.segments)
        }
        XCTAssertLessThanOrEqual(rendered.flatMap{$0}.count,DriveLineRenderingPolicy.defaultPointLimit+2)
        let statistics=measured("visible_statistics_50000") {
            DriveLineJourneyPolicy.signalStatistics(series,at:analysisRecording.endedAt,
                visibleRange:DateInterval(start:analysisRecording.startedAt,end:analysisRecording.endedAt))
        }
        XCTAssertEqual(statistics.observationCount,50_000)
        let duration=analysisRecording.endedAt.timeIntervalSince(analysisRecording.startedAt)
        let zoomedCounts=measured("chart_zoom_pan_20") {
            (0..<20).map { window -> Int in
                let start=analysisRecording.startedAt.addingTimeInterval(duration*Double(window)/40)
                let end=min(analysisRecording.endedAt,start.addingTimeInterval(duration/4))
                let cursor=start.addingTimeInterval(end.timeIntervalSince(start)/2)
                return DriveLineJourneyPolicy.signalStatistics(series,at:cursor,
                    visibleRange:DateInterval(start:start,end:end)).observationCount
            }
        }
        XCTAssertTrue(zoomedCounts.allSatisfy{$0>0})
        let scrubbedValues=measured("signal_scrub_12") {
            (0..<12).compactMap { position in
                DriveLineJourneyPolicy.cursor(
                    at:analysisRecording.startedAt.addingTimeInterval(duration*Double(position)/11),
                    recording:analysisRecording,signalKeys:["rpm"]).observations["rpm"]?.value
            }
        }
        XCTAssertGreaterThan(scrubbedValues.count,8)

        let routeRecording=DriveLinePerformanceFixture.recording(at:0,observationCount:50_000)
        let route=measured("route_prepare_50000") {
            DriveLineMetricPolicy.routeSegments(routeRecording.gpsPoints)
        }
        XCTAssertFalse(route.isEmpty)
        let mapMarkers=measured("map_cursor_20") {
            let routeDuration=routeRecording.endedAt.timeIntervalSince(routeRecording.startedAt)
            return (0..<20).compactMap { position in
                DriveLineJourneyPolicy.cursor(
                    at:routeRecording.startedAt.addingTimeInterval(routeDuration*Double(position)/19),
                    recording:routeRecording,signalKeys:[]).gpsPoint
            }
        }
        XCTAssertGreaterThan(mapMarkers.count,15)

        let vehicleMetrics=measured("vehicle_switch_4") {
            DriveLinePerformanceFixture.vehicles.enumerated().map { index,vehicle in
                let recording=DriveLinePerformanceFixture.recording(at:index,observationCount:2_000)
                XCTAssertEqual(recording.vehicleID,vehicle.id)
                return DriveLineMetricPolicy.metrics(for:recording)
            }
        }
        XCTAssertEqual(vehicleMetrics.count,4)

        measured("repeated_journey_selection_100") {
            for index in 0..<100 {
                autoreleasepool {
                    let recording=DriveLinePerformanceFixture.recording(at:index,observationCount:2_000)
                    _=DriveLineMetricPolicy.metrics(for:recording)
                    _=DriveLineJourneyPolicy.signalSeries("rpm",unit:"rpm",recording:recording)
                }
            }
        }

        let archiveRecording=DriveLinePerformanceFixture.recording(at:2,observationCount:20_000)
        let sources=[
            DriveLineSourceDescriptor(id:"synthetic-gps",kind:.synthetic,name:"Sanitized GPS"),
            DriveLineSourceDescriptor(id:"synthetic-obd",kind:.synthetic,name:"Sanitized OBD"),
            DriveLineSourceDescriptor(id:"synthetic",kind:.synthetic,name:"Sanitized fixture")
        ]
        let archive=DriveLineArchive(producer:DriveLineProducer(app:"DriveLine tests",version:"9",platform:"sanitized"),
            sources:sources,vehicles:DriveLinePerformanceFixture.vehicles,recordings:[archiveRecording])
        let bytes=measured("archive_export_20000") { try! archive.encoded() }
        let decoded=measured("archive_import_20000") { try! DriveLineArchive.decoded(bytes) }
        XCTAssertEqual(decoded.recordings.first?.recordingID,archiveRecording.recordingID)
        XCTAssertEqual(decoded.recordings.first?.signalSamples.count,archiveRecording.signalSamples.count)
    }
}
