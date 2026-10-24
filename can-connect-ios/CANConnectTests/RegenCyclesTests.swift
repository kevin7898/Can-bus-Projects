import XCTest
@testable import CANConnect

final class RegenCyclesTests: XCTestCase {
    let base = Date(timeIntervalSince1970:1_800_000_000)
    let vehicle = UUID()
    func sample(_ seconds: Double, _ signals: [String:Double]) -> OBDSample {
        OBDSample(timestamp:base.addingTimeInterval(seconds),signals:signals,command:"018B",reply:"fixture")
    }
    func trip(_ statuses: [(Double,Double)], extra: [OBDSample] = []) -> Trip {
        Trip(vehicleID:vehicle,name:"Synthetic regen fixture",startedAt:base,duration:1000,distanceKM:0,source:.scanner,isSample:false,
             samples:statuses.map { sample($0.0,["dpfRegenActive":$0.1]) } + extra)
    }
    func analyze(_ trip: Trip) -> [RegenCycle] { RegenAnalyzer.cycles(in:trip,since:base) }
    func testCompleteObservationPreservesActualBoundarySamplesAndUncappedPercentage() throws {
        let t = trip([(0,0),(3,1),(6,1),(9,0),(12,0)],extra:[sample(2,["dpfSootG":24,"dpfRegenTrigger":110]),sample(8,["dpfSootG":8,"egt1C":650])])
        let cycle = try XCTUnwrap(analyze(t).first)
        XCTAssertEqual(cycle.outcome,.completed); XCTAssertEqual(cycle.observedDuration,6)
        XCTAssertEqual(cycle.previousInactiveAt,base)
        XCTAssertEqual(cycle.startReadings["dpfRegenTrigger"]?.value,110)
        XCTAssertEqual(cycle.startReadings["dpfSootG"]?.timestamp,base.addingTimeInterval(2))
        XCTAssertEqual(cycle.endReadings["dpfSootG"]?.value,8); XCTAssertEqual(cycle.peakExhaustC,650)
        let archive = try JSONDecoder().decode(Trip.self,from:JSONEncoder().encode(t))
        XCTAssertEqual(analyze(archive),analyze(t))
    }
    func testStartMidCycleAndSingleActiveResponseAreNotComplete() {
        XCTAssertEqual(analyze(trip([(0,1),(3,1),(6,0),(9,0)])).first?.outcome,.partial)
        XCTAssertEqual(analyze(trip([(0,0),(3,1),(6,0),(9,0)])).first?.outcome,.unconfirmed)
    }
    func testRecordingEndIgnitionLossAndUnconfirmedEndRemainInterrupted() {
        for statuses: [(Double,Double)] in [[(0,0),(3,1),(6,1)],[(0,0),(3,1),(6,1),(9,0)]] {
            XCTAssertEqual(analyze(trip(statuses)).first?.outcome,.interrupted)
        }
    }
    func testGapSeparatesCyclesAndDoesNotBorrowReadingsAcrossGap() {
        let cycles = analyze(trip([(0,0),(3,1),(6,1),(40,1),(43,1),(46,0),(49,0)],extra:[sample(5,["dpfSootG":22])]))
        XCTAssertEqual(cycles.map(\.outcome),[.interrupted,.partial])
        XCTAssertNil(cycles[1].startReadings["dpfSootG"])
    }
    func testDuplicateResponsesDoNotConfirmTransitionsAndShortFalseInactiveIsIgnored() {
        XCTAssertEqual(analyze(trip([(0,0),(3,1),(3,1),(6,0),(6,0)])).first?.outcome,.interrupted)
        let cycles = analyze(trip([(0,0),(3,1),(6,1),(9,0),(12,1),(15,0),(18,0)]))
        XCTAssertEqual(cycles.count,1); XCTAssertEqual(cycles.first?.outcome,.completed)
        XCTAssertEqual(cycles.first?.endedAt,base.addingTimeInterval(15))
    }
    func testSlowReadingsExpireAndUnsupportedStatusCannotInventCycle() {
        let statuses: [(Double,Double)] = [(0,0),(100,0),(103,1),(106,1),(109,0),(112,0)]
        let cycles = analyze(trip(statuses,extra:[sample(0,["dpfSootG":20,"rpm":2000])]))
        XCTAssertNil(cycles.first?.startReadings["dpfSootG"])
        XCTAssertNil(cycles.first?.startReadings["rpm"])
        XCTAssertTrue(analyze(trip([],extra:[sample(0,["egt1C":650,"dpfSootG":20])])).isEmpty)
        XCTAssertTrue(analyze(trip([(0,2),(3,2)])).isEmpty)
    }
    func testBaselineVehicleIsolationAndDuplicateTripImports() {
        let t = trip([(0,0),(3,1),(6,1),(9,0),(12,0)])
        XCTAssertEqual(RegenAnalyzer.history(trips:[t,t],vehicleID:vehicle,since:base).count,1)
        XCTAssertTrue(RegenAnalyzer.history(trips:[t],vehicleID:UUID(),since:base).isEmpty)
        XCTAssertTrue(RegenAnalyzer.cycles(in:t,since:base.addingTimeInterval(100)).isEmpty)
        var demo = t; demo.isSample = true
        XCTAssertTrue(analyze(demo).isEmpty)
        var gps = t; gps.source = .phoneGPS
        XCTAssertTrue(analyze(gps).isEmpty)
    }
    func testLiveDraftBecomesInterruptedAfterStatusLossAndRecovery() {
        let t = trip([(0,0),(3,1),(6,1)])
        let draft = RecordingDraft(id:t.id,vehicleID:vehicle,source:.scanner,startedAt:base,updatedAt:base.addingTimeInterval(6),samples:t.samples)
        XCTAssertEqual(RegenAnalyzer.history(trips:[],vehicleID:vehicle,since:base,draft:draft,now:base.addingTimeInterval(10)).first?.outcome,.recording)
        XCTAssertEqual(RegenAnalyzer.history(trips:[],vehicleID:vehicle,since:base,draft:draft,now:base.addingTimeInterval(30)).first?.outcome,.interrupted)
        XCTAssertEqual(analyze(draft.trip(endedAt:draft.updatedAt,recovered:true)).first?.outcome,.interrupted)
        XCTAssertEqual(RegenAnalyzer.history(trips:[t],vehicleID:vehicle,since:base,draft:draft).count,1)
    }
    func testEngineStopAtInactiveTransitionIsInterruptedButStaleZeroRPMIsNotReused() {
        let statuses: [(Double,Double)] = [(0,0),(3,1),(6,1),(9,0),(12,0)]
        XCTAssertEqual(analyze(trip(statuses,extra:[sample(8,["rpm":0])])).first?.outcome,.interrupted)
        XCTAssertEqual(analyze(trip(statuses,extra:[sample(0,["rpm":0]),sample(8,["rpm":1800])])).first?.outcome,.completed)
        let later: [(Double,Double)] = [(0,0),(20,0),(23,1),(26,1),(29,0),(32,0)]
        XCTAssertEqual(analyze(trip(later,extra:[sample(0,["rpm":0])])).first?.outcome,.completed)
    }
    func testTrackingBaselineAndCyclesSurviveStateRoundTrip() throws {
        var state = StoredState(); state.regenTrackingStartedAt = base
        state.trips = [trip([(0,0),(3,1),(6,1),(9,0),(12,0)])]
        for _ in 0..<3 {
            state = try JSONDecoder().decode(StoredState.self,from:JSONEncoder().encode(state))
            let since = try XCTUnwrap(state.regenTrackingStartedAt)
            XCTAssertEqual(since,base)
            XCTAssertEqual(RegenAnalyzer.history(trips:state.trips,vehicleID:vehicle,since:since).first?.outcome,.completed)
        }
    }
    @MainActor
    func testRelaunchKeepsTheOriginalTrackingStartAndObservedCycles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let disk = LocalStore(url:directory.appendingPathComponent("state.json"))
        var state = StoredState(); state.regenTrackingStartedAt = base
        state.trips = [trip([(0,0),(3,1),(6,1),(9,0),(12,0)])]
        try disk.save(state)
        for _ in 0..<3 {
            let store = AppStore(disk:disk,scannerAvailable:{_ in false})
            XCTAssertEqual(store.state.regenTrackingStartedAt,base)
            XCTAssertEqual(RegenAnalyzer.history(trips:store.state.trips,vehicleID:vehicle,since:try XCTUnwrap(store.state.regenTrackingStartedAt)).count,1)
        }
    }
    func testOldStateLoadsWithoutBaseline() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(StoredState())) as? [String:Any])
        object.removeValue(forKey:"regenTrackingStartedAt")
        XCTAssertNil(try JSONDecoder().decode(StoredState.self,from:JSONSerialization.data(withJSONObject:object)).regenTrackingStartedAt)
    }
}
