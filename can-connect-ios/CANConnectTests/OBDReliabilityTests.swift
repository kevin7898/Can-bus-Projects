import XCTest
@testable import CANConnect

final class OBDReliabilityTests:XCTestCase {
    func testLongSchedulerDiagnosticsDoNotForgetEarlierCoverage() throws {
        let start=ContinuousClock.now
        var scheduler=OBDPollScheduler(pids:[0x0C],now:start)
        for i in 0..<1000 {
            let time=start.advanced(by:.seconds(Double(i)))
            let request=try XCTUnwrap(scheduler.next(at:time))
            scheduler.record(request,outcome:.success,responseLatency:0.02,at:time)
        }
        let stats=try XCTUnwrap(scheduler.diagnostics(at:start.advanced(by:.seconds(999))).pids[0x0C])
        XCTAssertEqual(stats.successes,1000)
        XCTAssertEqual(try XCTUnwrap(stats.coverageFraction),1,accuracy:0.001)
        XCTAssertEqual(stats.effectiveCadenceSeconds,1)
        XCTAssertEqual(stats.maximumObservationGapSeconds,1)
    }
    func testRequestOutcomesRemainDistinct() {
        XCTAssertEqual(OBDPollScheduler.classify(reply:"7F 01 78",pid:12,decoded:nil,ecu:nil),.pending)
        XCTAssertEqual(OBDPollScheduler.classify(reply:"7F 01 11",pid:12,decoded:nil,ecu:nil),.rejected)
        XCTAssertEqual(OBDPollScheduler.classify(reply:"41 0D 20",pid:12,decoded:nil,ecu:nil),.wrongSourceOrService)
        XCTAssertEqual(OBDPollScheduler.classify(reply:"NO DATA",pid:12,decoded:nil,ecu:nil),.noData)
        XCTAssertEqual(OBDPollScheduler.classify(reply:"garbage",pid:12,decoded:nil,ecu:nil),.malformed)
    }
    func testIncrementalLiveDistanceSurvivesOneGPSFixAndMatchesCanonical() throws {
        let start=Date(timeIntervalSince1970:1000)
        var draft=RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        draft.accept(RoutePoint(latitude:49,longitude:-124,timestamp:start,accuracy:5,speed:0))
        for i in 0...240 {
            draft.accept(OBDSample(timestamp:start.addingTimeInterval(Double(i)*5),signals:["speedKph":60,"rpm":1800],command:"010D",reply:"SYNTHETIC"))
        }
        XCTAssertEqual(draft.distanceKM,20,accuracy:0.0001)
        XCTAssertEqual(draft.trip(endedAt:draft.updatedAt).distanceKM,draft.distanceKM,accuracy:0.0001)
        XCTAssertEqual(draft.liveEvidence.latest["rpm"]?.timestamp,draft.updatedAt)
        var decoded=try JSONDecoder().decode(RecordingDraft.self,from:JSONEncoder().encode(draft))
        decoded.prepareLiveEvidence()
        XCTAssertEqual(decoded.liveEvidence.speedIntegral,draft.liveEvidence.speedIntegral)
    }
    func testCheckpointTailRecoveryAndFinalizedIdentityCannotResurrect() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"))
        let start=Date(timeIntervalSince1970:1000)
        var draft=RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        try disk.save(StoredState(draft:draft))
        for i in 0..<3 {
            draft.accept(OBDSample(timestamp:start.addingTimeInterval(Double(i)),signals:["rpm":1800],command:"010C",reply:"SYNTHETIC"))
            let message:String?=await withCheckedContinuation { continuation in
                disk.checkpoint(draft) { continuation.resume(returning:$0) }
            }
            XCTAssertNil(message)
        }
        let file=try FileHandle(forWritingTo:disk.activeJournalURL)
        try file.seekToEnd();try file.write(contentsOf:Data([0,0,0,0,0,0,0,20,123]));try file.close()
        let recovered=try XCTUnwrap(disk.load()?.draft)
        XCTAssertEqual(recovered.id,draft.id);XCTAssertEqual(recovered.samples,draft.samples)
        var saved=try XCTUnwrap(disk.load())
        saved.trips=[draft.trip(endedAt:draft.updatedAt)];saved.draft=nil
        try disk.save(saved)
        XCTAssertNil(try disk.load()?.draft)
        XCTAssertEqual(try disk.load()?.trips.count,1)
    }
}
