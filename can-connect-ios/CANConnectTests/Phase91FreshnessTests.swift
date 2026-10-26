import XCTest
@testable import CANConnect

final class Phase91FreshnessTests:XCTestCase {
    func testNoDataRetainsLastKnownValueWithoutCallingItLive() {
        let now=Date(timeIntervalSince1970:1000)
        var draft=RecordingDraft(source:.scanner,startedAt:now.addingTimeInterval(-60),updatedAt:now)
        draft.accept(OBDSample(timestamp:now.addingTimeInterval(-1),signals:["rpm":1800],command:"010C",reply:"SYNTHETIC"))
        let value=PhoneRecordingPresentation.make(state:StoredState(draft:draft),selectedSource:.scanner,pendingGPS:false,
            scannerConnected:true,scannerConnecting:false,scannerStatus:"Connected",gpsStatus:"Waiting",gpsSpeedKMH:nil,gpsLastFix:nil,
            now:now,scannerSupportedKeys:["rpm"],requestOutcomes:["rpm":.noData])
        XCTAssertEqual(value.metrics.first?.value,1800)
        XCTAssertEqual(value.metrics.first?.state,.stale)
        XCTAssertEqual(value.metrics.first?.observedAt,now.addingTimeInterval(-1))
    }
    func testFutureObservationCannotBeLiveEvenWithReadySemanticState() {
        let now=Date(timeIntervalSince1970:1000)
        let value=ObservationFreshnessDisplay.resolve(observedAt:now.addingTimeInterval(1),now:now,staleAfter:10,semanticState:.ready)
        XCTAssertEqual(value.state,.unavailable)
        XCTAssertNotEqual(value.label,"Live")
    }
    private let now=Date(timeIntervalSince1970:10_000)

    func testFreshnessBoundaryUsesActualObservationTimestamp() {
        let fresh=ObservationFreshnessDisplay.resolve(observedAt:now.addingTimeInterval(-10),now:now,staleAfter:10)
        let stale=ObservationFreshnessDisplay.resolve(observedAt:now.addingTimeInterval(-10.001),now:now,staleAfter:10)
        XCTAssertEqual(fresh.state,.ready);XCTAssertEqual(fresh.label,"Observed 10 seconds ago")
        XCTAssertEqual(stale.state,.stale);XCTAssertTrue(stale.label.hasPrefix("Stale"))
    }
    func testSemanticStateKeepsHeadingAndFooterLanguageConsistent() {
        let stale=ObservationFreshnessDisplay.resolve(observedAt:now.addingTimeInterval(-90),now:now,staleAfter:10,semanticState:.stale)
        let never=ObservationFreshnessDisplay.resolve(observedAt:nil,now:now,staleAfter:10,semanticState:.unavailable,statusText:"Not observed")
        let unsupported=ObservationFreshnessDisplay.resolve(observedAt:nil,now:now,staleAfter:10,semanticState:.unavailable,statusText:"Unsupported")
        let disconnected=ObservationFreshnessDisplay.resolve(observedAt:nil,now:now,staleAfter:10,semanticState:.offline)
        XCTAssertEqual(stale.state,.stale);XCTAssertEqual(stale.label,"Stale · 1m ago")
        XCTAssertEqual(never.label,"Not observed");XCTAssertEqual(unsupported.label,"Unsupported")
        XCTAssertEqual(disconnected.state,.offline);XCTAssertEqual(disconnected.label,"Scanner disconnected")
    }
    func testLivePresentationRetainsStaleValueAndItsRealTimestamp() {
        let old=now.addingTimeInterval(-11)
        var state=StoredState();state.draft=RecordingDraft(source:.scanner,startedAt:now.addingTimeInterval(-60),updatedAt:now)
        state.draft?.samples=[OBDSample(timestamp:old,signals:["rpm":1800],command:"010C",reply:"410C1C20",requestHeader:"7E0",responseHeader:"7E8")]
        let result=PhoneRecordingPresentation.make(state:state,selectedSource:.scanner,pendingGPS:false,
            scannerConnected:true,scannerConnecting:false,scannerStatus:"Connected",gpsStatus:"Waiting for a GPS fix",
            gpsSpeedKMH:nil,gpsLastFix:nil,now:now,scannerSupportedKeys:["rpm"])
        let rpm=result.metrics.first(where:{$0.key=="rpm"})
        XCTAssertEqual(rpm?.value,1800);XCTAssertEqual(rpm?.observedAt,old);XCTAssertEqual(rpm?.state,.stale)
    }
    func testNeverObservedUnsupportedAndDisconnectedAreDistinct() {
        let state=StoredState(draft:RecordingDraft(source:.scanner,startedAt:now.addingTimeInterval(-10),updatedAt:now))
        let connected=PhoneRecordingPresentation.make(state:state,selectedSource:.scanner,pendingGPS:false,
            scannerConnected:true,scannerConnecting:false,scannerStatus:"Connected",gpsStatus:"Waiting",
            gpsSpeedKMH:nil,gpsLastFix:nil,now:now,scannerSupportedKeys:["rpm"],scannerUnsupportedKeys:["coolantC"])
        XCTAssertEqual(connected.metrics.first(where:{$0.key=="rpm"})?.statusText,"Not observed")
        XCTAssertEqual(connected.metrics.first(where:{$0.key=="coolantC"})?.statusText,"Unsupported")
        let disconnected=PhoneRecordingPresentation.make(state:state,selectedSource:.scanner,pendingGPS:false,
            scannerConnected:false,scannerConnecting:false,scannerStatus:"Disconnected",gpsStatus:"Waiting",
            gpsSpeedKMH:nil,gpsLastFix:nil,now:now)
        XCTAssertEqual(disconnected.metrics.first(where:{$0.key=="rpm"})?.state,.offline)
    }
}
