import XCTest
import Darwin
@testable import CANConnect

@MainActor private final class ReplayIdentityTransport:ScannerTransport {
    func open(host:String,port:UInt16) async throws ->ScannerIdentity {
        ScannerIdentity(vin:nil,adapter:"SYNTHETIC",vehicleProtocol:"CAN",supportedPIDs:[12])
    }
    func command(_ text:String) async throws ->String {
        try await Task.sleep(nanoseconds:60_000_000_000)
        return "NO DATA"
    }
    func disconnect() {}
}

final class OBDReliabilityTests:XCTestCase {
    @MainActor func testAcquisitionAndCheckpointWithMillionObservationSavedLibrary() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"))
        let transport=ReplayIdentityTransport(),scanner=ScannerRecorder(makeSession:{transport})
        let store=AppStore(disk:disk,scanner:scanner,gps:GPSFixture(),scannerAvailable:{_ in false})
        var vehicle=VehicleProfile();vehicle.make="Volkswagen";vehicle.model="Jetta TDI";vehicle.year=2013
        store.state.vehicles=[vehicle];store.state.selectedVehicleID=vehicle.id
        scanner.connect(settings:ScannerSettings(),vehicle:vehicle)
        await fulfillment(of:[XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in scanner.connected },object:nil)],timeout:5)
        defer { scanner.onDisconnect=nil;scanner.disconnect() }
        let start=Date().addingTimeInterval(-1800)
        let archived=(0..<2000).map { OBDSample(timestamp:start.addingTimeInterval(Double($0)*0.5),signals:["rpm":1800,"speedKph":60],command:"010C",reply:"SYNTHETIC") }
        store.state.trips=(0..<500).map { index in
            Trip(name:"Sanitized sample \(index)",startedAt:start,duration:1000,distanceKM:16.6,source:.scanner,isSample:true,samples:archived)
        }
        store.state.draft=RecordingDraft(vehicleID:store.state.selectedVehicleID,source:.scanner,startedAt:start,updatedAt:start)
        let clock=ContinuousClock(),baselineStart=ContinuousClock.now
        try autoreleasepool { try disk.save(store.state) }
        let baseline=OBDPollScheduler.seconds(baselineStart.duration(to:clock.now))
        var baselineUsage=rusage();getrusage(RUSAGE_SELF,&baselineUsage)
        var latencies:[Double]=[]
        for i in 0...3600 {
            let sample=OBDSample(timestamp:start.addingTimeInterval(Double(i)*0.5),signals:["rpm":1800,"speedKph":60],command:"010C",reply:"SYNTHETIC")
            let begin=clock.now;store.scanner.onSample?(sample)
            latencies.append(OBDPollScheduler.seconds(begin.duration(to:clock.now)))
        }
        let draft=try XCTUnwrap(store.state.draft),checkpointStart=clock.now
        let failure:String?=await withCheckedContinuation { continuation in disk.checkpoint(draft) { continuation.resume(returning:$0) } }
        let checkpoint=OBDPollScheduler.seconds(checkpointStart.duration(to:clock.now))
        var afterUsage=rusage();getrusage(RUSAGE_SELF,&afterUsage)
        XCTAssertNil(failure);XCTAssertEqual(draft.samples?.count,3601)
        XCTAssertTrue(try disk.load()?.draft?.samples == draft.samples,"Recovered checkpoint must retain every raw observation")
        let sorted=latencies.sorted()
        print("OBD_LARGE_LIBRARY trips=500 saved_observations=1000000 replay_seconds=1800 replay_observations=3601 full_library_checkpoint_seconds=\(baseline) append_checkpoint_seconds=\(checkpoint) handler_p95_seconds=\(sorted[Int(Double(sorted.count-1)*0.95)]) handler_max_seconds=\(sorted.last!) baseline_darwin_ru_maxrss=\(baselineUsage.ru_maxrss) after_darwin_ru_maxrss=\(afterUsage.ru_maxrss)")
    }
    func testCheckpointBacklogCoalescesWithoutLosingNewestRawEvidence() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json")),start=Date(timeIntervalSince1970:1000)
        var draft=RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        try disk.save(StoredState(draft:draft))
        let gate=DispatchSemaphore(value:0)
        LocalStore.persistenceQueue.async { gate.wait() }
        let finished=expectation(description:"Newest coalesced checkpoint durable")
        for i in 0..<20 {
            draft.accept(.init(timestamp:start.addingTimeInterval(Double(i)),signals:["rpm":1800],command:"010C",reply:"SYNTHETIC"))
            disk.checkpoint(draft) { message in
                if i == 19 { XCTAssertNil(message);finished.fulfill() }
            }
        }
        gate.signal()
        await fulfillment(of:[finished],timeout:10)
        XCTAssertEqual(try disk.load()?.draft?.samples,draft.samples)
    }
    func testSlowTierCannotStarveWhenNoCorePIDsExist() throws {
        let start=ContinuousClock.now
        var scheduler=OBDPollScheduler(pids:[0x05,0x0B,0x33],now:start)
        var slow=0
        for i in 0..<20 {
            let now=start.advanced(by:.seconds(i*4))
            let request=try XCTUnwrap(scheduler.next(at:now))
            if request.pid == 0x33 { slow += 1 }
            scheduler.record(request,outcome:.success,responseLatency:4,at:now)
        }
        XCTAssertGreaterThan(slow,0)
    }
    @MainActor func testDiagnosticExportContainsOnlyAggregateEvidence() {
        let recorder=ScannerRecorder()
        let text=recorder.diagnosticsExport.lowercased()
        for prohibited in ["vin","serial","latitude","longitude","credential","host","reply"] { XCTAssertFalse(text.contains(prohibited)) }
    }
    func testThirtyMinuteIncrementalReplayMatchesAuditAlgorithmWithoutGrowingWork() throws {
        let start=Date(timeIntervalSince1970:1000)
        let samples=(0...3600).map { OBDSample(timestamp:start.addingTimeInterval(Double($0)*0.5),signals:["speedKph":60,"rpm":1800],command:"010D",reply:"SYNTHETIC") }
        let clock=ContinuousClock()
        var original:[OBDSample]=[],baselineDistance=0.0
        let before=clock.now
        for sample in samples {
            original.append(sample)
            let values=original.compactMap { sample -> (Date,Double)? in sample.signals["speedKph"].map { (sample.timestamp,$0) } }.sorted{$0.0<$1.0}
            baselineDistance=zip(values,values.dropFirst()).reduce(0.0) { total,pair in
                let seconds=pair.1.0.timeIntervalSince(pair.0.0)
                return total+(seconds > 0 && seconds <= 10 ? (pair.0.1+pair.1.1)/2*seconds:0)
            }/3600
        }
        let baseline=OBDPollScheduler.seconds(before.duration(to:clock.now))
        var draft=RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        let after=clock.now
        for sample in samples { draft.accept(sample) }
        let incremental=OBDPollScheduler.seconds(after.duration(to:clock.now))
        XCTAssertEqual(draft.distanceKM,baselineDistance,accuracy:0.000001)
        XCTAssertEqual(draft.samples,samples)
        print("OBD_REPLAY synthetic_duration_seconds=1800 observations=3601 baseline_seconds=\(baseline) incremental_seconds=\(incremental)")
    }
    @MainActor func testFinishIsAsynchronousIdempotentAndPreservesNewerMetadata() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"))
        let store=AppStore(disk:disk,gps:GPSFixture(),scannerAvailable:{_ in false})
        let start=Date(timeIntervalSince1970:1000)
        var draft=RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        for i in 0..<10000 { draft.accept(.init(timestamp:start.addingTimeInterval(Double(i)*0.1),signals:["rpm":1800,"speedKph":60],command:"010C",reply:"SYNTHETIC")) }
        store.state.draft=draft
        let begin=ContinuousClock.now
        store.finishRecording(endedAt:draft.updatedAt);store.finishRecording()
        let shell=OBDPollScheduler.seconds(begin.duration(to:.now))
        XCTAssertTrue(store.isFinishing);XCTAssertNotNil(store.state.draft)
        await Task.yield()
        store.state.preferences.wifiLogs=false
        await store.waitForFinish()
        XCTAssertFalse(store.isFinishing);XCTAssertNil(store.state.draft)
        XCTAssertEqual(store.state.trips.filter{$0.id == draft.id}.count,1)
        XCTAssertEqual(try disk.load()?.preferences.wifiLogs,false)
        XCTAssertEqual(try disk.load()?.trips.first?.samples,draft.samples)
        print("OBD_FINISH synthetic_observations=10000 immediate_shell_seconds=\(shell)")
    }
    func testOdometerRegressionAndImplausibleJumpRequireReview() {
        let id=UUID(),start=Date(timeIntervalSince1970:1000)
        let old=FuelOdometerObservation(vehicleID:id,valueKm:1000,observedAt:start,sourceIdentifier:"synthetic.definition",isTrusted:true)
        var next=old;next.observedAt=start.addingTimeInterval(60);next.valueKm=999
        XCTAssertTrue(next.requiresReview(comparedWith:old))
        next.valueKm=2000;XCTAssertTrue(next.requiresReview(comparedWith:old))
        next.valueKm=1001;XCTAssertFalse(next.requiresReview(comparedWith:old))
    }
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
    func testOutOfOrderObservationRepairsOnlyAdjacentIntegralsAndPreservesRawOrder() throws {
        let start=Date(timeIntervalSince1970:1000)
        var draft=RecordingDraft(source:.scanner,startedAt:start,updatedAt:start)
        let samples=[(0.0,0.0),(10.0,100.0),(5.0,100.0)].map {
            OBDSample(timestamp:start.addingTimeInterval($0.0),signals:["speedKph":$0.1,"fuelRateLph":6],command:"010D",reply:"SYNTHETIC")
        }
        for sample in samples { draft.accept(sample) }
        XCTAssertEqual(draft.samples,samples)
        XCTAssertEqual(draft.distanceKM,draft.trip(endedAt:start.addingTimeInterval(10)).distanceKM,accuracy:0.000001)
        XCTAssertEqual(draft.distanceKM,750/3600.0,accuracy:0.000001)
        XCTAssertEqual(draft.integral("fuelRateLph")?.value,60)
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
        saved.trips=[];try disk.save(saved)
        XCTAssertNil(try disk.load()?.draft,"A completed journal must not resurrect a subsequently removed trip")
    }
}
