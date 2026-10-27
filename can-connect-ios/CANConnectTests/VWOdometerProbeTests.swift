import XCTest
@testable import CANConnect

@MainActor
final class VWOdometerProbeTests:XCTestCase {
    func testCandidateRequiresCorrectECUIdentifierLengthAndAgreement() {
        let hd=VWOdometerProbe.cluster[1]
        XCTAssertEqual(VWOdometerProbe.candidateKM(hd,reply:"77E 07 62 22 B8 03 9E 00 D0",response:"77E"),60686.544)
        for invalid in ["7E8 07 62 22 B8 03 9E 00 D0", "77E 07 62 22 B9 03 9E 00 D0", "77E 06 62 22 B8 03 9E 00", "77E 03 7F 22 31", "77E 07 62 22 B8 FF FF FF FF", "NO DATA", "77E 07 62 22 B8 03 9E 00 D0\r77E 07 62 22 B8 03 9E 00 D1"] {
            XCTAssertNil(VWOdometerProbe.candidateKM(hd,reply:invalid,response:"77E"),invalid)
        }
        XCTAssertEqual(VWOdometerProbe.candidateKM(VWOdometerProbe.gearbox[1],reply:"7E9 07 62 38 41 00 00 97 6B",response:"7E9"),3876.3)
        XCTAssertEqual(VWOdometerProbe.candidateKM(VWOdometerProbe.gearbox[2],reply:"7E9 07 62 38 87 6B 97 00 00",response:"7E9"),3876.3)
    }
    func testFuelVolumeUsesSeparateUnitsAndRejectsMalformedOrWrongECU() {
        XCTAssertEqual(VWOdometerProbe.fuelLitres(reply:"77E 05 62 22 9A 01 18"),35)
        XCTAssertNil(VWOdometerProbe.fuelLitres(reply:"7E8 05 62 22 9A 01 18"))
        XCTAssertNil(VWOdometerProbe.fuelLitres(reply:"77E 05 62 22 9A FF FF"))
        XCTAssertNil(VWOdometerProbe.fuelLitres(reply:"77E 04 62 22 9A 01"))
        XCTAssertNil(VWOdometerProbe.fuelLitres(reply:"77E 03 7F 22 31"))
        XCTAssertNil(VWOdometerProbe.candidateKM(VWOdometerProbe.cluster[0],reply:"77E 05 62 22 03 66 FF",response:"77E"),"Captured 2-byte cluster reply must not be silently coerced into 3-byte odometer")
    }
    func testTripDiscoveryIsBoundedFingerprintGatedAndNeverPromotesDistance() async {
        let transport=OdometerProbeFixture()
        let report=await VWOdometerProbe(transport:transport).run(settings:.init(),vehicle:vehicle,tripDiscovery:true)
        XCTAssertTrue(report.status.hasPrefix("Finished"),report.status)
        XCTAssertEqual(VWOdometerProbe.tripDiscoveryDIDs.count,32)
        let queries=Set(VWOdometerProbe.tripDiscoveryDIDs.map { String(format:"22%04X",$0) })
        XCTAssertEqual(transport.commands.filter { queries.contains($0) }.count,64)
        XCTAssertFalse(transport.commands.contains("216D"))
        XCTAssertFalse(transport.commands.contains("22108C"))
        XCTAssertEqual(report.entries.compactMap(\.candidateKM).count,0)
        XCTAssertEqual(report.entries.compactMap(\.candidateLitres).count,0)
        let captured=report.entries.filter { $0.command == "222200" }
        XCTAssertEqual(captured.map(\.payloadHex),["0D 48","0D 48"])
        XCTAssertEqual(captured.map(\.diagnosticSession),["default","extended"])
        XCTAssertTrue(captured.allSatisfy { $0.observedAt != nil })
        XCTAssertTrue(transport.commands.contains("1001"))
        XCTAssertTrue(transport.disconnected)
    }
    func testTripDiscoveryRejectsWrongClusterAndWrongResponseAttribution() async {
        let transport=OdometerProbeFixture();transport.wrongCluster=true
        let report=await VWOdometerProbe(transport:transport).run(settings:.init(),vehicle:vehicle,tripDiscovery:true)
        XCTAssertFalse(report.status.hasPrefix("Finished"))
        XCTAssertFalse(transport.commands.contains("222200"))
        XCTAssertFalse(transport.commands.contains("1003"))
        for reply in ["7E8 05 62 22 00 0D 48","77E 05 62 22 01 0D 48","77E 03 7F 22 31","77E 05 62 22 00 0D 48\r77E 05 62 22 00 0D 49"] {
            XCTAssertNil(VWOdometerProbe.rawClusterPayload(reply,did:0x2200))
        }
    }
    func testTripDiscoveryCancellationRestoresDefaultSession() async {
        let transport=OdometerProbeFixture();transport.waitAfterSession=true
        let task=Task { await VWOdometerProbe(transport:transport).run(settings:.init(),vehicle:vehicle,tripDiscovery:true) }
        while !transport.sessionEntered { await Task.yield() }
        task.cancel();let report=await task.value
        XCTAssertTrue(report.status.contains("Cancelled"))
        XCTAssertEqual(transport.commands.last,"1001")
        XCTAssertTrue(transport.disconnected)
    }
    func testSecondBatchIsDisjointBoundedAndRetainsSessionCleanup() async {
        XCTAssertTrue(Set(VWTripDiscoveryBatch.first.identifiers).isDisjoint(with:VWTripDiscoveryBatch.second.identifiers))
        XCTAssertEqual(VWTripDiscoveryBatch.second.identifiers.count,32)
        for reject in [false,true] {
            let transport=OdometerProbeFixture();transport.rejectSession=reject
            let report=await VWOdometerProbe(transport:transport).run(settings:.init(),vehicle:vehicle,tripDiscovery:true,tripBatch:.second)
            XCTAssertTrue(report.status.hasPrefix("Finished"),report.status)
            let requests=transport.commands.filter { $0.hasPrefix("22") && !["22F187","22F189"].contains($0) }
            let expected=VWTripDiscoveryBatch.second.identifiers.map { String(format:"22%04X",$0) }
            XCTAssertEqual(requests,reject ? expected:expected+expected)
            XCTAssertTrue(report.purpose?.contains("Batch 2") == true)
            XCTAssertTrue(report.entries.allSatisfy { $0.candidateKM == nil && $0.candidateLitres == nil })
            XCTAssertTrue(transport.commands.contains("1001"));XCTAssertTrue(transport.disconnected)
        }
    }
    private var vehicle:VehicleProfile {
        var v=VehicleProfile();v.make="Volkswagen";v.vin="TEST0000000000001";return v
    }
    func testClusterSessionExplicitFlowControlAndReturnToDefault() async {
        let transport=OdometerProbeFixture()
        let report=await VWOdometerProbe(transport:transport).run(settings:.init(),vehicle:vehicle)
        XCTAssertTrue(report.status.hasPrefix("Finished"),report.status)
        XCTAssertTrue(transport.commands.contains("ATFCSH714"))
        let session=transport.commands.firstIndex(of:"1003")!
        XCTAssertEqual(Array(transport.commands.dropFirst(session+1).prefix(5)),["222203","2222B8","22229A","1001","ATFCSM0"])
        XCTAssertEqual(report.entries.filter {$0.candidateKM != nil}.count,4)
        XCTAssertEqual(report.entries.compactMap(\.candidateLitres),[35,35])
        XCTAssertFalse(report.text.contains("TEST0000000000001"))
        XCTAssertTrue(transport.disconnected)
    }
    func testVINMismatchAndMovingVehicleStopBeforeManufacturerRequests() async {
        for moving in [false,true] {
            let transport=OdometerProbeFixture();transport.speed=moving ? 10:0
            var v=vehicle;if !moving { v.vin="TEST0000000000002" }
            let report=await VWOdometerProbe(transport:transport).run(settings:.init(),vehicle:v)
            XCTAssertFalse(report.status.hasPrefix("Finished"))
            XCTAssertFalse(transport.commands.contains(where:{$0.hasPrefix("22") || $0 == "1003"}))
            XCTAssertTrue(transport.disconnected)
        }
    }
    func testRejectedSessionNeverReadsExtendedCandidatesAndRestores() async {
        let transport=OdometerProbeFixture();transport.rejectSession=true
        let report=await VWOdometerProbe(transport:transport).run(settings:.init(),vehicle:vehicle)
        let session=transport.commands.firstIndex(of:"1003")!
        XCTAssertEqual(Array(transport.commands.dropFirst(session+1).prefix(2)),["1001","ATFCSM0"])
        XCTAssertTrue(report.entries.contains {$0.outcome.contains("Negative response 12")})
    }
    func testCancellationAfterSessionEntryRestoresBeforeDisconnect() async {
        let transport=OdometerProbeFixture();transport.waitAfterSession=true
        let task=Task { await VWOdometerProbe(transport:transport).run(settings:.init(),vehicle:vehicle) }
        while !transport.sessionEntered { await Task.yield() }
        task.cancel()
        let report=await task.value
        XCTAssertTrue(report.status.contains("Cancelled"),report.status)
        XCTAssertEqual(transport.commands.last,"1001")
        XCTAssertTrue(transport.disconnected)
    }
    func testProbeBlocksRecordingConnectionAndVehicleChanges() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"))
        var state=StoredState();state.vehicles=[vehicle];state.selectedVehicleID=vehicle.id
        try disk.save(state)
        let transport=OdometerProbeFixture();transport.waitAfterSession=true
        let scanner=ScannerRecorder(engine:.rebuilt,makeSession:{transport})
        let store=AppStore(disk:disk,scanner:scanner,gps:GPSFixture(),scannerAvailable:{_ in false})
        let task=Task { try await store.runOdometerProbe(settings:.init()) }
        while !transport.sessionEntered { await Task.yield() }
        XCTAssertTrue(store.odometerProbeRunning)
        store.source = .phoneGPS;store.startRecording();store.startRecordingFromToday()
        XCTAssertFalse(store.recording);XCTAssertFalse(store.pendingGPS)
        XCTAssertThrowsError(try store.connectScanner(settings:.init()))
        XCTAssertThrowsError(try store.chooseVehicle(vehicle.id))
        scanner.connect(settings:.init(),vehicle:vehicle)
        XCTAssertFalse(scanner.connecting)
        task.cancel();try await task.value
        XCTAssertFalse(store.odometerProbeRunning)
        XCTAssertNotNil(store.odometerProbeReport)
        XCTAssertFalse(store.automaticScannerRecordingEnabled)
        XCTAssertEqual(transport.commands.last,"1001")
    }
    func testMissingDefaultSessionAcknowledgmentIsNotSuccess() async {
        let transport=OdometerProbeFixture();transport.rejectRestore=true
        let report=await VWOdometerProbe(transport:transport).run(settings:.init(),vehicle:vehicle)
        XCTAssertFalse(report.status.hasPrefix("Finished"))
        XCTAssertTrue(report.status.contains("default-session reply missing"))
    }
}

@MainActor
private final class OdometerProbeFixture:ScannerTransport {
    var commands:[String]=[]
    var disconnected=false, rejectSession=false, rejectRestore=false, waitAfterSession=false, sessionEntered=false
    var wrongCluster=false
    var speed:UInt8=0
    func open(host:String,port:UInt16) async throws -> ScannerIdentity {
        .init(vin:"TEST0000000000001",adapter:"SYNTHETIC",vehicleProtocol:"CAN",supportedPIDs:[13])
    }
    func command(_ text:String) async throws -> String {
        commands.append(text)
        switch text {
        case "22F187":return wrongCluster ? "NO DATA":"77E 10 0D 62 F1 87 35 43 36\r77E 21 39 32 30 38 35 33 41"
        case "22F189":return "77E 07 62 F1 89 30 38 30 39"
        case "222200":return "77E 05 62 22 00 0D 48"
        case "ATDPN":return "A6"
        case "010D":return String(format:"7E8 03 41 0D %02X",speed)
        case "1003":
            sessionEntered=true
            if waitAfterSession { try await Task.sleep(for:.seconds(10)) }
            return rejectSession ? "77E 03 7F 10 12":"77E 06 50 03 00 32 01 F4"
        case "1001":return rejectRestore ? "NO DATA":"77E 06 50 01 00 32 01 F4"
        case "22229A":return "77E 05 62 22 9A 01 18"
        case "222203":return "77E 06 62 22 03 00 ED 0E"
        case "2222B8":return "77E 07 62 22 B8 03 9E 00 D0"
        default:return text.hasPrefix("AT") ? "OK":"NO DATA"
        }
    }
    func disconnect() { disconnected=true }
}
