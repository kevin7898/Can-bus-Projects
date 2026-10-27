import XCTest
@testable import CANConnect

final class FuelRangeTests:XCTestCase {
    private func sample(_ seconds:Double,speed:Double?=nil,fuel:Double?=nil,source:String="7E8",epoch:UUID?=nil)->OBDSample {
        var signals:[String:Double]=[:];signals["speedKph"]=speed;signals["fuelRateLph"]=fuel
        return OBDSample(timestamp:Date(timeIntervalSince1970:seconds),signals:signals,command:"010D",reply:"fixture",responseHeader:source,clockEpoch:epoch,monotonicTime:seconds)
    }
    func testMatchedIntervalsRetainIdleFuelAndExcludeGapsAndDifferentSources() {
        var c=MatchedFuelCollector()
        c.accept(sample(0,speed:60,fuel:6));c.accept(sample(10,speed:60,fuel:6))
        XCTAssertEqual(c.window.km,1.0/6,accuracy:1e-8)
        XCTAssertEqual(c.window.litres,1.0/60,accuracy:1e-8)
        c.interrupt();c.accept(sample(20,speed:0,fuel:1));c.accept(sample(30,speed:0,fuel:1))
        XCTAssertEqual(c.window.km,1.0/6,accuracy:1e-8)
        XCTAssertEqual(c.window.litres,7.0/360,accuracy:1e-8)
        let before=c.window
        c.accept(sample(90,speed:100,fuel:10));XCTAssertEqual(c.window,before)
        c.interrupt();c.accept(sample(100,speed:60));c.accept(sample(100,fuel:6,source:"7E9"))
        c.accept(sample(110,speed:60));c.accept(sample(110,fuel:6,source:"7E9"))
        XCTAssertEqual(c.window,before)
    }
    func testAsynchronousReadingsUseOnlyOverlap() {
        var c=MatchedFuelCollector()
        c.accept(sample(0,speed:60));c.accept(sample(2,fuel:6));c.accept(sample(10,speed:60));c.accept(sample(12,fuel:6))
        XCTAssertEqual(c.window.km,60*8/3600,accuracy:1e-8)
        XCTAssertEqual(c.window.litres,6*8/3600,accuracy:1e-8)
    }
    func testRolling500WeightsDistanceAndTrimsOldestBin() throws {
        var w=RollingFuelWindow()
        for _ in 0..<400 { w.append(km:1,litres:0.05) }
        for _ in 0..<200 { w.append(km:1,litres:0.1) }
        XCTAssertEqual(w.km,500,accuracy:1e-8);XCTAssertEqual(try XCTUnwrap(w.economy),7,accuracy:1e-8)
        w.append(km:0.5,litres:0.05)
        XCTAssertEqual(w.km,500,accuracy:1e-8);XCTAssertEqual(w.litres,35.025,accuracy:1e-8)
        XCTAssertLessThanOrEqual(w.bins.count,502)
    }
    func testReserveRangeNoNegativeAndUnavailableWithoutEvidence() throws {
        var w=RollingFuelWindow();XCTAssertNil(w.range(fuel:24.375,reserve:5))
        w.append(km:100,litres:5)
        XCTAssertEqual(try XCTUnwrap(w.range(fuel:24.375,reserve:5)),387.5,accuracy:1e-8)
        XCTAssertEqual(w.range(fuel:4,reserve:5),0);XCTAssertNil(w.range(fuel:nil,reserve:5))
        XCTAssertNil(w.range(fuel:24,reserve:.nan))
    }
    func testEpochChangesAndDuplicateTimestampsBreakContinuity() {
        var c=MatchedFuelCollector();let a=UUID(),b=UUID()
        c.accept(sample(0,speed:60,fuel:6,epoch:a));c.accept(sample(10,speed:60,fuel:6,epoch:b))
        XCTAssertEqual(c.window.km,0)
        c.accept(sample(10,speed:120,fuel:12,epoch:b));XCTAssertEqual(c.window.km,0)
    }
    func testHistoryExcludesOtherVehiclesAndSyntheticTrips() async throws {
        let id=UUID(),other=UUID()
        func trip(_ vehicle:UUID,_ synthetic:Bool)->Trip {
            Trip(vehicleID:vehicle,name:"Fixture",startedAt:Date(timeIntervalSince1970:0),duration:10,distanceKM:999,source:.scanner,isSample:synthetic,samples:[sample(0,speed:60,fuel:6),sample(10,speed:60,fuel:6)])
        }
        let result=try await FuelRangeHistory().window(trips:[trip(id,false),trip(other,false),trip(id,true)],vehicleID:id)
        XCTAssertEqual(result.km,1.0/6,accuracy:1e-8)
    }
    func testReserveBackwardDecodingAndRoundTrip() throws {
        let old=Data("{\"make\":\"VW\",\"model\":\"Jetta\"}".utf8)
        var v=try JSONDecoder().decode(VehicleProfile.self,from:old)
        XCTAssertEqual(v.reserveLitres,5);v.reserveLitres=7.5
        XCTAssertEqual(try JSONDecoder().decode(VehicleProfile.self,from:JSONEncoder().encode(v)).reserveLitres,7.5)
        v.reserveLitres = .infinity;XCTAssertThrowsError(try v.validated())
    }
    func testClusterAllowlistPrivacyAndSamplePersistence() throws {
        let reply="77E 05 62 22 9A 00 C3"
        XCTAssertEqual(TelemetryPrivacy.reply(command:"22229A",reply:reply),reply)
        XCTAssertEqual(TelemetryPrivacy.reply(command:"22229A",reply:reply+"\r77E 04 62 F1 90 01"),"[redacted]")
        XCTAssertThrowsError(try TelemetryRequest.cluster("1003"));XCTAssertThrowsError(try TelemetryRequest.cluster("2E229A"))
        let s=OBDSample(timestamp:Date(),signals:["clusterFuelLitres":24.375],command:"22229A",reply:reply,requestHeader:"714",responseHeader:"77E")
        XCTAssertTrue(s.isValid);XCTAssertEqual(try JSONDecoder().decode(OBDSample.self,from:JSONEncoder().encode(s)),s)
    }
}

extension FuelRangeTests {
    @MainActor func testClusterFingerprintReadRestoreAndSingleOwner() async throws {
        let fixture=RangeClusterTransport()
        var vehicle=VehicleProfile();vehicle.year=2014;vehicle.make="Volkswagen";vehicle.model="Jetta";vehicle.vin="TEST0000000000001"
        var offset=0.0
        let engine=RebuiltScannerEngine(transport:fixture,vehicle:vehicle,settings:.init(),clock:{ProcessInfo.processInfo.systemUptime+offset})
        let restored=expectation(description:"Primary polling resumes after cluster window")
        var samples:[OBDSample]=[],advanced=false,done=false
        engine.onSample={ sample in
            samples.append(sample)
            if !advanced { advanced=true;offset += 20 }
            if fixture.commands.contains("222203"),sample.responseHeader == "7E8",!done { done=true;restored.fulfill() }
        }
        engine.start(after:nil)
        await fulfillment(of:[restored],timeout:6)
        await engine.stop()?.value
        XCTAssertEqual(samples.first { $0.signals["clusterFuelLitres"] != nil }?.signals["clusterFuelLitres"],24.375)
        XCTAssertEqual(samples.first { $0.signals["clusterOdometerCoarseKM"] != nil }?.signals["clusterOdometerCoarseKM"],263670)
        let index=try XCTUnwrap(fixture.commands.firstIndex(of:"222203"))
        XCTAssertEqual(Array(fixture.commands.dropFirst(index+1).prefix(3)),["ATFCSM0","ATSH7E0","ATCRA7E8"])
        XCTAssertEqual(fixture.maximumConcurrent,1)
        XCTAssertFalse(fixture.commands.contains("1003"));XCTAssertFalse(fixture.commands.contains("ATCAF0"))
        XCTAssertEqual(engine.clusterTiming.windows,1)
    }
    @MainActor func testUnknownClusterNeverReadsFuelOrOdometerAndResumesECU() async throws {
        let fixture=RangeClusterTransport();fixture.wrongVersion=true
        var vehicle=VehicleProfile();vehicle.year=2014;vehicle.make="VW";vehicle.model="Jetta";vehicle.vin="TEST0000000000001"
        var offset=0.0,advanced=false,done=false
        let engine=RebuiltScannerEngine(transport:fixture,vehicle:vehicle,settings:.init(),clock:{ProcessInfo.processInfo.systemUptime+offset})
        let restored=expectation(description:"Unknown cluster skipped")
        engine.onSample={ sample in
            if !advanced { advanced=true;offset += 20 }
            if fixture.commands.contains("22F189"),sample.responseHeader == "7E8",!done { done=true;restored.fulfill() }
        }
        engine.start(after:nil);await fulfillment(of:[restored],timeout:6);await engine.stop()?.value
        XCTAssertFalse(fixture.commands.contains("22229A"));XCTAssertFalse(fixture.commands.contains("222203"))
        XCTAssertEqual(engine.clusterTiming.failures,1)
    }
}

@MainActor private final class RangeClusterTransport:ScannerTransport {
    var commands:[String]=[],wrongVersion=false
    var concurrent=0,maximumConcurrent=0
    func open(host:String,port:UInt16) async throws -> ScannerIdentity {
        ScannerIdentity(vin:nil,adapter:"Fixture",vehicleProtocol:"ISO CAN",supportedPIDs:[12,13,94])
    }
    func command(_ text:String) async throws -> String {
        concurrent += 1;maximumConcurrent=max(maximumConcurrent,concurrent);defer { concurrent -= 1 }
        commands.append(text);try await Task.sleep(for:.milliseconds(1))
        switch text {
        case "ATDPN":return "A6"
        case "0100":return "7E8 06 41 00 00 18 00 01"
        case "0120":return "7E8 06 41 20 00 00 00 01"
        case "0140":return "7E8 06 41 40 00 00 00 04"
        case "010C":return "7E8 04 41 0C 1A F8"
        case "010D":return "7E8 03 41 0D 3C"
        case "015E":return "7E8 04 41 5E 00 64"
        case "0902":return "7E8 10 14 49 02 01 54 45 53\r7E8 21 54 30 30 30 30 30 30\r7E8 22 30 30 30 30 30 30 31"
        case "22F187":return "77E 10 0E 62 F1 87 35 43 36\r77E 21 39 32 30 38 35 33 41\r77E 22 20 AA AA AA AA AA AA"
        case "22F189":return wrongVersion ? "77E 07 62 F1 89 30 30 30 30":"77E 07 62 F1 89 30 38 30 39"
        case "22229A":return "77E 05 62 22 9A 00 C3"
        case "222203":return "77E 05 62 22 03 66 FF"
        default:return "OK"
        }
    }
    func disconnect() {}
}
