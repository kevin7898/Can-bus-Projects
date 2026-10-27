import XCTest
@testable import CANConnect

final class TelemetryRebuildTests:XCTestCase {
    func testLateCheckpointCannotChangeFinalizedBytesOrFinalMetadata() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let start=Date(timeIntervalSince1970:1000)
        let draft=RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        let buffer=try RebuiltTripBuffer(url:root.appendingPathComponent("finish-race.dlt"),draft:draft)
        try buffer.append(OBDSample(timestamp:start,signals:["rpm":800],command:"010C",reply:"41 0C 0C 80"))
        var final=try buffer.materialize(draft);final.updatedAt=start.addingTimeInterval(30)
        try buffer.finalize(final)
        let before=try Data(contentsOf:buffer.url)
        let markerURL=buffer.url.appendingPathExtension("finalized")
        let marker=try Data(contentsOf:markerURL)
        let completed=expectation(description:"superseded checkpoint completed")
        buffer.checkpoint(draft) { message in XCTAssertNil(message);completed.fulfill() }
        await fulfillment(of:[completed],timeout:2)
        XCTAssertEqual(try Data(contentsOf:buffer.url),before)
        XCTAssertEqual(try Data(contentsOf:markerURL),marker)
        XCTAssertEqual(try RebuiltTripBuffer.recover(url:buffer.url)?.updatedAt,final.updatedAt)
        XCTAssertEqual(try RebuiltTripBuffer.recover(url:buffer.url)?.samples?.count,1)
    }

    func testIndexedLogDoesNotResurrectAnIntentionallyDeletedTrip() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json")),vehicle=VehicleProfile(),start=Date(timeIntervalSince1970:1000)
        let draft=RecordingDraft(vehicleID:vehicle.id,source:.scanner,startedAt:start,updatedAt:start)
        let buffer=try RebuiltTripBuffer(url:root.appendingPathComponent("TripLogs/"+draft.id.uuidString+".dlt"),draft:draft)
        try buffer.append(OBDSample(timestamp:start,signals:["rpm":1726],command:"010C",reply:"41 0C 1A F8"))
        let complete=try buffer.materialize(draft);try buffer.finalize(complete)
        var state=StoredState();state.vehicles=[vehicle];state.selectedVehicleID=vehicle.id
        // Finalized but not indexed remains recoverable.
        try disk.save(state)
        XCTAssertEqual(try disk.load()?.draft?.id,draft.id)
        state.trips=[complete.trip(endedAt:start)];try disk.save(state)
        state.trips=[];try disk.save(state)
        XCTAssertNil(try disk.load()?.draft)
    }

    func testTornDiskWriteRetriesFromExactPrefixWithoutLosingAdmittedSample() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let start=Date(timeIntervalSince1970:1000),draft=RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        let buffer=try RebuiltTripBuffer(url:root.appendingPathComponent("disk-fault.dlt"),draft:draft) { handle,frame in
            try handle.write(contentsOf:frame.prefix(2))
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let sample=OBDSample(timestamp:start,signals:["rpm":1726],command:"010C",reply:"41 0C 1A F8")
        try buffer.append(sample)
        let recovered=try buffer.materialize(draft)
        XCTAssertEqual(recovered.samples,[sample])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).contains { $0.lastPathComponent.contains("damaged-") })
        try buffer.finalize(recovered)
        XCTAssertThrowsError(try buffer.append(sample))
    }
    func testGPSIsAppendedAndRestoredIndependentlyOfBoundedMapPreview() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let start=Date(timeIntervalSince1970:1000)
        var draft=RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        let buffer=try RebuiltTripBuffer(url:root.appendingPathComponent("gps.dlt"),draft:draft)
        draft.rebuiltBuffer=buffer
        for i in 0..<4200 {
            let point=RoutePoint(latitude:49+Double(i)*0.000001,longitude:-124,timestamp:start.addingTimeInterval(Double(i)),accuracy:5,speed:1)
            try buffer.append(point);draft.accept(point)
            if i % 64 == 0 { _ = try buffer.materialize(draft) }
        }
        XCTAssertLessThanOrEqual(draft.route.count,4096)
        XCTAssertEqual(draft.liveEvidence.pointCount,4200)
        let recovered=try buffer.materialize(draft)
        XCTAssertEqual(recovered.route.count,4200)
        XCTAssertEqual(recovered.route.first?.timestamp,start)
    }

    @MainActor func testRebuiltEngineFeedsExistingFacadeWithOneCommandInFlight() async throws {
        let transport=RebuildTransport()
        let scanner=ScannerRecorder(engine:.rebuilt,makeSession:{transport})
        var vehicle=VehicleProfile();vehicle.make="Synthetic";vehicle.model="Replay"
        let samples=expectation(description:"new engine samples");samples.expectedFulfillmentCount=3;samples.assertForOverFulfill=false
        scanner.onSample={ sample in
            XCTAssertEqual(sample.responseHeader,"7E8")
            if let rpm=sample.signals["rpm"] { XCTAssertEqual(rpm,1726) }
            samples.fulfill()
        }
        scanner.connect(settings:.init(host:"127.0.0.1"),vehicle:vehicle)
        await fulfillment(of:[samples],timeout:5)
        XCTAssertTrue(scanner.connected);XCTAssertEqual(scanner.vehicleID,vehicle.id)
        XCTAssertEqual(transport.maximumConcurrent,1)
        XCTAssertTrue(transport.commands.contains("ATCRA7E8"))
        XCTAssertFalse(transport.commands.contains("ATCAF0"),"Enhanced windows remain deferred")
        scanner.disconnect()
    }
    @MainActor func testRebuiltIdentityMismatchBlocksAllPolling() async throws {
        let transport=RebuildTransport(),scanner=ScannerRecorder(engine:.rebuilt,makeSession:{transport})
        var vehicle=VehicleProfile();vehicle.vin="TEST0000000000002"
        let failed=expectation(description:"blocked VIN")
        scanner.onDisconnect={ message in XCTAssertTrue(message.contains("VIN differs"));failed.fulfill() }
        scanner.connect(settings:.init(host:"127.0.0.1"),vehicle:vehicle)
        await fulfillment(of:[failed],timeout:4)
        XCTAssertFalse(scanner.connected);XCTAssertFalse(transport.commands.contains("010C"))
        scanner.disconnect()
    }
    @MainActor func testAdapterOwnershipCannotBeStolenOrReleasedByOtherOwner() throws {
        let key=UUID().uuidString,a=UUID(),b=UUID()
        try AdapterOwnership.acquire(key,owner:a)
        XCTAssertThrowsError(try AdapterOwnership.acquire(key,owner:b))
        AdapterOwnership.release(key,owner:b)
        XCTAssertThrowsError(try AdapterOwnership.acquire(key,owner:b))
        AdapterOwnership.release(key,owner:a)
        try AdapterOwnership.acquire(key,owner:b)
        AdapterOwnership.release(key,owner:b)
    }
    func testGroupedScalingsUseIndependentExpectedValues() throws {
        let rpm=try XCTUnwrap(OBDDecoder.decodePayload([0x1A,0xF8],pid:12,at:Date(),ecu:"7EA",command:"010C",reply:"7EA 04 41 0C 1A F8"))
        XCTAssertEqual(rpm.signals["rpm"],1726);XCTAssertEqual(rpm.requestHeader,"7E2")
        let fuel=try XCTUnwrap(OBDDecoder.decodePayload([0,100],pid:94,at:Date(),ecu:"7E8",command:"015E",reply:"7E8 04 41 5E 00 64"))
        XCTAssertEqual(fuel.signals["fuelRateLph"],5)
        XCTAssertNil(OBDDecoder.decodePayload([0],pid:94,at:Date(),ecu:"7E8",command:"015E",reply:"truncated"))
    }
    func testBoundedTripBufferMaterializesExactLegacySamplesAndRecovers() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let start=Date(timeIntervalSince1970:1000)
        var draft=RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        let buffer=try RebuiltTripBuffer(url:root.appendingPathComponent("test.dlt"),draft:draft)
        draft.rebuiltBuffer=buffer;draft.liveEvidence.streaming=true
        for i in 0..<1000 {
            let sample=OBDSample(timestamp:start.addingTimeInterval(Double(i)),signals:["speedKph":60,"fuelRateLph":6],command:"010D5E",reply:"41 0D 3C 5E 00 78")
            try buffer.append(sample);draft.accept(sample)
            // A controlled producer drains between batches, without pretending
            // an unbounded disk queue can accept an infinite burst.
            if i % 64 == 0 { _ = try buffer.materialize(draft) }
        }
        XCTAssertEqual(draft.samples?.count,256);XCTAssertEqual(draft.liveEvidence.sampleCount,1000)
        let complete=try buffer.materialize(draft)
        XCTAssertEqual(complete.samples?.count,1000)
        XCTAssertEqual(complete.samples?.first?.timestamp,start)
        try buffer.finalize();try buffer.finalize()
        XCTAssertEqual(try RebuiltTripBuffer.recover(url:buffer.url)?.samples?.count,1000)
        let archive=TripArchive(trips:[complete.trip(endedAt:start.addingTimeInterval(999))])
        XCTAssertEqual(try TripArchive.decode(archive.encoded()).trips.first?.samples?.count,1000)
    }
    @MainActor func testJournalNeverPersistsIdentityOrPartialIdentity() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let journal=ScannerJournal(directory:root)
        journal.append(command:"0902",reply:"TEST0000000000001")
        journal.append(command:"0904",reply:"partial SECRET")
        journal.append(command:"ERROR",reply:"TEST0000000000001")
        try await journal.flush()
        for file in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) {
            let text=try String(contentsOf:file,encoding:.utf8)
            XCTAssertFalse(text.contains("TEST0000"));XCTAssertFalse(text.contains("SECRET"))
        }
    }
}

@MainActor private final class RebuildTransport:ScannerTransport {
    var capabilities="7E8 06 41 00 00 18 00 01"
    var commands:[String]=[]
    var concurrent=0,maximumConcurrent=0
    func open(host:String,port:UInt16) async throws -> ScannerIdentity {
        ScannerIdentity(vin:nil,adapter:"Synthetic",vehicleProtocol:"ISO CAN",supportedPIDs:[12,13,94])
    }
    func command(_ text:String) async throws -> String {
        concurrent += 1;maximumConcurrent=max(maximumConcurrent,concurrent);defer { concurrent -= 1 }
        commands.append(text);try await Task.sleep(for:.milliseconds(1))
        switch text {
        case "ATDPN": return "A6"
        case "0100": return capabilities
        case "0120": return "7E8 06 41 20 00 00 00 01"
        case "0140": return "7E8 06 41 40 00 00 00 04"
        case "010C": return "7E8 04 41 0C 1A F8"
        case "010D": return "7E8 03 41 0D 3C"
        case "015E": return "7E8 04 41 5E 00 64"
        case "0902": return "7E8 10 14 49 02 01 54 45 53\r7E8 21 54 30 30 30 30 30 30\r7E8 22 30 30 30 30 30 30 31"
        default: return "OK"
        }
    }
    func disconnect() {}
}

extension TelemetryRebuildTests {
    func testUnexpectedIdentityBesideStandardReplyCannotReachTripExport() throws {
        let reply="41 0C 1A F8\r49 02 01 54 45 53 54 30 30 30 30 30 30 30 30 30 30 30 30 31"
        let sample=try XCTUnwrap(OBDDecoder.decode(reply,pid:12))
        XCTAssertEqual(sample.signals["rpm"],1726)
        XCTAssertEqual(sample.reply,"[redacted]")
    }
}


extension TelemetryRebuildTests {
    // Non-identifying Mode 01 bitmap captured from the physical MX+ failure.
    private var mxPlusCapabilities:String {
        "SEARCHING...\r7E8 06 41 00 98 19 20 13 \r7E9 06 41 00 98 18 00 01 \r\r"
    }
    func testCapturedMXPlusCapabilitiesSelectStrictSupersetRegardlessOfProfile() throws {
        let candidates=TelemetryELM.supported(TelemetryELM.parse(mxPlusCapabilities).payloads,base:0)
        XCTAssertEqual(candidates.count,2)
        XCTAssertEqual(try TelemetryELM.primaryECU(candidates),"7E8")
        XCTAssertEqual(try TelemetryELM.primaryECU(["7E9":candidates["7E8"]!,"7E8":candidates["7E9"]!]),"7E9")
    }
    func testEqualAndIncomparableCapabilitiesRemainBlocked() {
        for candidates:[String:Set<Int>] in [
            ["7E8":[5,12,13],"7E9":[5,12,13]],
            ["7E8":[5,12,13,16],"7E9":[5,12,13,17]]
        ] {
            XCTAssertThrowsError(try TelemetryELM.primaryECU(candidates)) {
                XCTAssertEqual($0 as? TelemetryFailure,.ambiguous)
            }
        }
        XCTAssertThrowsError(try TelemetryELM.primaryECU(["7E8":[5,13]])) {
            XCTAssertEqual($0 as? TelemetryFailure,.unsupported)
        }
    }
    @MainActor func testCapturedMXPlusDiscoveryReachesVINRoutingAndPolling() async throws {
        let transport=RebuildTransport();transport.capabilities=mxPlusCapabilities
        let scanner=ScannerRecorder(engine:.rebuilt,makeSession:{transport})
        // A VIN-decoded profile may have no transmission/engine metadata.
        var vehicle=VehicleProfile();vehicle.year=2014;vehicle.make="VOLKSWAGEN";vehicle.model="Jetta"
        vehicle.vin="TEST0000000000001"
        let observed=expectation(description:"selected ECU sample");observed.assertForOverFulfill=false
        scanner.onSample={ sample in
            XCTAssertEqual(sample.responseHeader,"7E8")
            if sample.signals["rpm"] != nil { observed.fulfill() }
        }
        scanner.connect(settings:.init(host:"127.0.0.1"),vehicle:vehicle)
        await fulfillment(of:[observed],timeout:5)
        XCTAssertTrue(scanner.connected)
        XCTAssertTrue(transport.commands.contains("0902"))
        XCTAssertTrue(transport.commands.contains("ATCRA7E8"))
        XCTAssertFalse(transport.commands.contains("ATCRA7E9"))
        scanner.disconnect()
    }
    func testDisconnectedScannerPreflightNeverClaimsReady() {
        for connecting in [false,true] {
            let p=PhoneRecordingPresentation.make(state:StoredState(),selectedSource:.scanner,pendingGPS:false,
                scannerConnected:false,scannerConnecting:connecting,scannerStatus:"ECU discovery status",
                gpsStatus:"GPS ready",gpsSpeedKMH:nil,gpsLastFix:nil,now:Date())
            XCTAssertEqual(p.statusTitle,connecting ? "Connecting scanner":"Scanner not ready")
            XCTAssertEqual(p.statusMessage,"ECU discovery status")
        }
    }
}

extension TelemetryRebuildTests {
    @MainActor func testOpeningTimeoutReachesUserWithoutStorageDiagnosisOrClusterRequests() async {
        let transport=OpeningFailureTransport()
        let engine=RebuiltScannerEngine(transport:transport,vehicle:VehicleProfile(),settings:.init())
        let failed=expectation(description:"original connection error")
        engine.onFailure={ message in
            XCTAssertTrue(message.contains("timed out waiting for ATI"))
            XCTAssertFalse(message.lowercased().contains("storage"));failed.fulfill()
        }
        engine.start(after:nil);await fulfillment(of:[failed],timeout:3);await engine.stop()?.value
        XCTAssertTrue(transport.commands.isEmpty)
        XCTAssertEqual(RebuiltScannerEngine.failureCategory(AppFailure("MX+ timed out waiting for ATI. private-test-host")),"timeout")
        XCTAssertFalse(RebuiltScannerEngine.failureCategory(AppFailure("private-test-host")).contains("private-test-host"))
        XCTAssertTrue(RebuiltScannerEngine.failureMessage(TelemetryFailure.storage,opening:false).contains("storage"))
    }
    @MainActor func testIdentificationReportsExactOpeningStageBeforeFailure() async {
        var stage=ScannerOpeningStage.transport
        do {
            _ = try await ELMIdentification.read(progress:{stage=$0}) { command in
                if command == "0902" { throw AppFailure("fixture failure") }
                return command == "ATI" ? "SYNTHETIC":"OK"
            }
            XCTFail("Expected fixture failure")
        } catch { XCTAssertEqual(stage,.vehicleVIN) }
    }
}

@MainActor private final class OpeningFailureTransport:ScannerTransport {
    let openingStage:ScannerOpeningStage = .adapterIdentity
    var commands:[String]=[]
    func open(host:String,port:UInt16) async throws -> ScannerIdentity {
        throw AppFailure("MX+ timed out waiting for ATI. Check power, Bluetooth pairing and ignition, and close other OBD apps.")
    }
    func command(_ text:String) async throws -> String { commands.append(text);return "OK" }
    func disconnect() {}
}
