import XCTest
@testable import CANConnect

final class JettaReadingsTests: XCTestCase {
    func testEngineRPMSelectionDoesNotUseConflictingDSGReply() throws {
        let reply = "7E8 04 41 0C 1C 98 00 00 00\r7E9 04 41 0C 00 00 00 00 00"
        XCTAssertNil(OBDDecoder.decode(reply,pid:12))
        let sample = try XCTUnwrap(OBDDecoder.decode(reply,pid:12,ecu:"7E8"))
        XCTAssertEqual(sample.signals["rpm"],1830)
        XCTAssertEqual(sample.responseHeader,"7E8"); XCTAssertEqual(sample.requestHeader,"7E0")
        XCTAssertNil(OBDDecoder.decode("7E904410C0000",pid:12,ecu:"7E8"))
        XCTAssertNil(OBDDecoder.decode("410C1C98",pid:12,ecu:"7E8"))
        let old = Data(#"{"timestamp":0,"signals":{"rpm":0},"command":"010C","reply":"410C0000"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(OBDSample.self,from:old).responseHeader)
    }
    func testMultiFrameBoostKeepsOnlyCompleteCorrectlySequencedEnginePayload() throws {
        let reply = "7E8100C417003145313\r7E921B6000000000000\r7E821B6000000000000"
        let sample = try XCTUnwrap(OBDDecoder.decode(reply,pid:0x70,ecu:"7E8"))
        XCTAssertEqual(try XCTUnwrap(sample.signals["boostAbsoluteKpa"]),Double(0x13B6)/32,accuracy:0.001)
        XCTAssertEqual(try XCTUnwrap(sample.signals["boostCommandedKpa"]),Double(0x1453)/32,accuracy:0.001)
        XCTAssertNil(sample.signals["boostBAbsoluteKpa"])
        for bad in ["7E8100C417003145313", "7E8100C417003145313\r7E822B6000000000000", "7E9100C417003145313\r7E921B6000000000000"] {
            XCTAssertNil(OBDDecoder.decode(bad,pid:0x70,ecu:"7E8"))
        }
    }
    func testStandardDPFFieldsRespectSupportBitsAndDoNotInventSootMass() throws {
        let sample = try XCTUnwrap(OBDDecoder.decode("7E81009418B5F03FF00\r7E82100001900000000",pid:0x8B,ecu:"7E8"))
        XCTAssertEqual(sample.signals["dpfRegenActive"],1)
        XCTAssertEqual(sample.signals["dpfRegenTrigger"],100)
        XCTAssertEqual(sample.signals["dpfAverageRegenKM"],25)
        XCTAssertNil(sample.signals["dpfAverageRegenMinutes"])
        XCTAssertFalse(sample.signals.keys.contains(where:{$0.lowercased().contains("soot")}))
        XCTAssertNil(OBDDecoder.decode("418B0000FF00100020",pid:0x8B))
        let pressure = try XCTUnwrap(OBDDecoder.decode("7E81009417A01FFFF00\r7E82100000000000000",pid:0x7A,ecu:"7E8"))
        XCTAssertEqual(try XCTUnwrap(pressure.signals["dpfDifferentialKpa"]),-0.01,accuracy:0.0001)
        XCTAssertNil(pressure.signals["dpfInletKpa"])
    }
    func testExhaustSensorIdentityAndAirflow() throws {
        let sample = try XCTUnwrap(OBDDecoder.decode("7E8100B41780F17AC10\r7E8214C0EBE0C660000",pid:0x78,ecu:"7E8"))
        XCTAssertEqual(sample.signals.count,4)
        XCTAssertEqual(try XCTUnwrap(sample.signals["egt1C"]),566,accuracy:0.001)
        XCTAssertEqual(try XCTUnwrap(sample.signals["egt4C"]),277.4,accuracy:0.001)
        XCTAssertEqual(OBDDecoder.decode("411003E8",pid:0x10)?.signals["mafGps"],10)
    }
    @MainActor
    func testSupportDiscoveryContinuesThroughRegenerationPageAndStopsAtAbsentContinuation() async throws {
        var commands: [String] = []
        let identity = try await ELMIdentification.read { command in
            commands.append(command)
            switch command {
            case "ATI": return "ELM327 fixture"
            case "0902": return "NO DATA"
            case "0100": return "410000100001"
            case "0120": return "412000000001"
            case "0140": return "414000000001"
            case "0160": return "416000000001"
            case "0180": return "418000200000"
            case "ATDP": return "ISO 15765-4 CAN 11/500"
            default: return "OK"
            }
        }
        XCTAssertTrue(identity.supportedPIDs.contains(0x8B))
        XCTAssertTrue(commands.contains("0180")); XCTAssertFalse(commands.contains("01A0"))
    }
    func testEngineECUSelectionRequiresMatchingRealProfile() {
        var v = VehicleProfile(); v.year = 2014; v.make = "Volkswagen"; v.model = "Jetta"; v.engine = "TDI"; v.transmission = "DSG"
        XCTAssertTrue(Jetta2014Profile.matches(v))
        v.year = 2016; XCTAssertFalse(Jetta2014Profile.matches(v)); v.year = 2014
        v.engine = "TSI"; XCTAssertFalse(Jetta2014Profile.matches(v))
        v.fuel = .diesel; v.isSample = true; XCTAssertFalse(Jetta2014Profile.matches(v))

    }
    func testRecordingAndMacWirePreserveExtendedFieldsAndECUIdentity() throws {
        let sample = try XCTUnwrap(OBDDecoder.decode("7E81009418B5F03FF00\r7E82100001900000000",pid:0x8B,at:Date(timeIntervalSince1970:1700000000.123),ecu:"7E8"))
        XCTAssertTrue(sample.isValid)
        var draft = RecordingDraft(source:.scanner,startedAt:sample.timestamp,updatedAt:sample.timestamp,scannerTransport:.obdLinkMXPlus)
        draft.accept(sample)
        let trip = draft.trip(endedAt:sample.timestamp.addingTimeInterval(1))
        XCTAssertEqual(try TripArchive.decode(TripArchive(trips:[trip]).encoded()).trips.first?.samples?.first,sample)
        let wire = try DriveLineArchive.decoded(MacRecording.encode(trip))
        let row = try XCTUnwrap(wire.recordings.first?.signalSamples.first)
        XCTAssertEqual(row.responseHeader,"7E8")
        XCTAssertEqual(row.values["dpfRegenTrigger"],100)
    }
}

@MainActor
private final class TargetedJettaFixture: ScannerTransport {
    var commands: [String] = []
    private var headers = false
    func open(host: String, port: UInt16) async throws -> ScannerIdentity {
        ScannerIdentity(vin:nil,adapter:"SYNTHETIC MX+",vehicleProtocol:"ISO 15765-4 CAN 11/500",supportedPIDs:[12])
    }
    func command(_ text: String) async throws -> String {
        commands.append(text)
        switch text {
        case "ATH1": headers = true; return "OK"
        case "0100": return "7E806410000100001"
        case "0120": return "7E806412000000001"
        case "0140": return "7E806414000000001"
        case "0160": return "7E806416000000001"
        case "0180": return "7E806418000200000"
        case "010C": return headers ? "7E804410C1C98\r7E904410C0000" : "410C1C98\r410C0000"
        case "018B": return "7E81009418B5F03FF00\r7E82100001900000000"
        default: return "OK"
        }
    }
    func disconnect() {}
}

extension JettaReadingsTests {
    @MainActor
    func testCombinedSootCardUsesECUPercentIndependentlyOfGrams() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let fixture = TargetedJettaFixture(); let scanner = ScannerRecorder(makeSession:{fixture})
        let store = AppStore(disk:LocalStore(url:root.appendingPathComponent("state.json")),scanner:scanner,gps:GPSFixture(),scannerAvailable:{_ in false})
        store.source = .scanner
        XCTAssertEqual(store.regenTriggerText,"—")
        let ready = expectation(description:"ECU trigger received")
        scanner.onSample = { if $0.signals["dpfRegenTrigger"] != nil { ready.fulfill() } }
        var vehicle = VehicleProfile(); vehicle.make="Volkswagen";vehicle.model="Jetta";vehicle.year=2014;vehicle.engine="TDI";vehicle.transmission="DSG"
        scanner.connect(settings:ScannerSettings(transport:.obdLinkMXPlus),vehicle:vehicle)
        await fulfillment(of:[ready],timeout:3)
        scanner.onSample = nil
        XCTAssertEqual(store.regenTriggerText,"100")
        XCTAssertEqual(store.signalText(.sootMass),"—","Percent must not invent grams")
        store.source = .phoneGPS; XCTAssertEqual(store.regenTriggerText,"—")
        store.source = .scanner; scanner.disconnect(); XCTAssertEqual(store.regenTriggerText,"—")
    }
    @MainActor
    func testMatchingProfileSelectsEngineAndPollsAdvertisedExtendedReadings() async throws {
        let transport = TargetedJettaFixture();let scanner = ScannerRecorder(makeSession:{transport})
        var vehicle = VehicleProfile();vehicle.make="Volkswagen";vehicle.model="Jetta";vehicle.year=2014;vehicle.engine="TDI";vehicle.transmission="DSG"
        let recorded=expectation(description:"engine RPM and advertised DPF replies");recorded.expectedFulfillmentCount=2;recorded.assertForOverFulfill=false
        var samples:[OBDSample]=[]
        scanner.onSample = { sample in samples.append(sample);recorded.fulfill() }
        scanner.connect(settings:ScannerSettings(transport:.obdLinkMXPlus),vehicle:vehicle)
        await fulfillment(of:[recorded],timeout:3)
        scanner.disconnect()
        XCTAssertEqual(samples.first?.signals["rpm"],1830)
        XCTAssertTrue(samples.contains {$0.signals["dpfRegenTrigger"] == 100})
        XCTAssertTrue(samples.allSatisfy {$0.responseHeader == "7E8" && $0.requestHeader == "7E0"})
        XCTAssertTrue(transport.commands.contains("ATSH7E0"));XCTAssertTrue(transport.commands.contains("ATCRA7E8"))
        XCTAssertTrue(transport.commands.contains("0180"));XCTAssertTrue(transport.commands.contains("018B"))
        XCTAssertFalse(transport.commands.contains {$0.hasPrefix("22")},"Unsupported VW candidates must not be queried on every connection")
    }
}

@MainActor
private final class SlowReadingsFixture: ScannerTransport {
    var commands: [String] = []
    func open(host: String, port: UInt16) async throws -> ScannerIdentity {
        ScannerIdentity(vin:nil,adapter:"SYNTHETIC",vehicleProtocol:"ISO 15765-4 CAN 11/500",supportedPIDs:[0x0C,0x46,0x33,0x2F])
    }
    func command(_ text: String) async throws -> String {
        commands.append(text)
        switch text {
        case "010C": return "410C0D00"
        case "0146": return "41463C"
        case "0133": return "413364"
        case "012F": return "412F80"
        default: return "OK"
        }
    }
    func disconnect() {}
}
extension JettaReadingsTests {
    @MainActor
    func testSlowReadingsRemainVisibleWithoutRepeatedPollingOrSyntheticSamples() async throws {
        let fixture = SlowReadingsFixture(); let scanner = ScannerRecorder(makeSession:{fixture})
        let ready = expectation(description:"all slow readings plus repeated RPM")
        var samples: [OBDSample] = []
        scanner.onSample = { sample in
            samples.append(sample)
            if samples.filter({$0.signals["rpm"] != nil}).count == 3 { ready.fulfill() }
        }
        scanner.connect(settings:ScannerSettings(host:"fixture"),vehicle:VehicleProfile())
        await fulfillment(of:[ready],timeout:5)
        scanner.onSample = nil
        for (key,command,limit) in [("outsideC","0146",75.0),("barometricKpa","0133",75.0),("fuelPercent","012F",45.0)] {
            let sample = try XCTUnwrap(samples.first(where:{$0.signals[key] != nil}))
            XCTAssertEqual(fixture.commands.filter{$0 == command}.count,1)
            XCTAssertEqual(samples.filter{$0.signals[key] != nil}.count,1)
            XCTAssertEqual(scanner.value(key,at:sample.timestamp.addingTimeInterval(limit-1)),sample.signals[key])
            XCTAssertNil(scanner.value(key,at:sample.timestamp.addingTimeInterval(limit+1)))
        }
        XCTAssertEqual(OBDDecoder.pollInterval(pid:0x46),60)
        XCTAssertEqual(OBDDecoder.pollInterval(pid:0x33),60)
        XCTAssertEqual(OBDDecoder.pollInterval(pid:0x2F),30)
        XCTAssertEqual(OBDDecoder.pollInterval(pid:0x7A),0.5)
        XCTAssertEqual(OBDDecoder.pollInterval(pid:0x8B),3)
        XCTAssertEqual(VWController.engine.pollInterval,60)
        XCTAssertEqual(OBDDecoder.freshness(for:"rpm"),10)
        scanner.disconnect()
        XCTAssertNil(scanner.value("outsideC",at:Date()))
    }
}
