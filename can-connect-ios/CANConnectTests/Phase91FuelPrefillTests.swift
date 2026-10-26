import XCTest
@testable import CANConnect

@MainActor
private final class FuelLocationFixture:FuelLocationProviding {
    var result:Result<FuelStationSuggestion,FuelLocationFailure>
    init(_ result:Result<FuelStationSuggestion,FuelLocationFailure>) { self.result=result }
    func currentStation() async throws ->FuelStationSuggestion { try result.get() }
}

final class Phase91FuelPrefillTests:XCTestCase {
    private let now=Date(timeIntervalSince1970:2_000_000)
    private let vehicle=UUID(uuidString:"10000000-0000-0000-0000-000000000001")!
    private let other=UUID(uuidString:"10000000-0000-0000-0000-000000000002")!

    func testCurrentTrustedScanWinsOverOlderStoredScanAndFuelEntry() {
        let fill=FuelEntry(vehicleID:vehicle,date:now.addingTimeInterval(-60),litres:40,costCAD:70,odometerKM:1000,full:true)
        let stored=FuelOdometerObservation(vehicleID:vehicle,valueKm:1199,observedAt:now.addingTimeInterval(-120),sourceIdentifier:"verified.fixture",recordingID:UUID(),isTrusted:true)
        let current=FuelOdometerObservation(vehicleID:vehicle,valueKm:1200,observedAt:now.addingTimeInterval(-10),sourceIdentifier:"verified.fixture",recordingID:UUID(),isTrusted:true)
        let result=FuelOdometerPrefillPolicy.choose(vehicleID:vehicle,current:current,stored:[stored],fills:[fill],now:now)
        XCTAssertEqual(result?.valueKm,1200);XCTAssertEqual(result?.sourceType,.scanned)
    }
    func testLatestFuelEntryFallbackAndUnknownRemainsBlank() {
        let old=FuelEntry(vehicleID:vehicle,date:now.addingTimeInterval(-100),litres:20,costCAD:30,odometerKM:900,full:false)
        let latest=FuelEntry(vehicleID:vehicle,date:now.addingTimeInterval(-10),litres:40,costCAD:70,odometerKM:1000,full:true)
        let result=FuelOdometerPrefillPolicy.choose(vehicleID:vehicle,current:nil,stored:[],fills:[latest,old],now:now)
        XCTAssertEqual(result?.valueKm,1000);XCTAssertEqual(result?.sourceType,.fuelEntry)
        var blank=FuelFormDraft();blank.applyOdometer(FuelOdometerPrefillPolicy.choose(vehicleID:other,current:nil,stored:[],fills:[latest],now:now))
        XCTAssertEqual(blank.odometerText,"");XCTAssertNil(blank.odometerProvenance)
    }
    func testWrongVehicleStaleAndUntrustedScansAreRejected() {
        let wrong=FuelOdometerObservation(vehicleID:other,valueKm:9000,observedAt:now,sourceIdentifier:"verified.fixture",recordingID:nil,isTrusted:true)
        let stale=FuelOdometerObservation(vehicleID:vehicle,valueKm:8000,observedAt:now.addingTimeInterval(-FuelOdometerPrefillPolicy.storedMaximumAge-1),sourceIdentifier:"verified.fixture",recordingID:nil,isTrusted:true)
        let untrusted=FuelOdometerObservation(vehicleID:vehicle,valueKm:7000,observedAt:now,sourceIdentifier:"unknown",recordingID:nil,isTrusted:false)
        XCTAssertNil(FuelOdometerPrefillPolicy.choose(vehicleID:vehicle,current:wrong,stored:[stale,untrusted],fills:[],now:now))
    }
    func testTypedOrExplicitlyClearedOdometerIsNeverOverwritten() {
        let evidence=DriveLineOdometerProvenance(valueKm:1234,observedAt:now,sourceIdentifier:"verified.fixture",sourceType:.scanned)
        var typed=FuelFormDraft();typed.userChangedOdometer("88");typed.applyOdometer(evidence)
        XCTAssertEqual(typed.odometerText,"88");XCTAssertNil(typed.odometerProvenance)
        var cleared=FuelFormDraft();cleared.userChangedOdometer("");cleared.applyOdometer(evidence)
        XCTAssertEqual(cleared.odometerText,"")
    }
    @MainActor func testAutomaticGeocodeSuccessAndTypedStationProtection() async throws {
        let suggestion=FuelStationSuggestion(stationName:"Synthetic Fuel",stationAddress:"100 Fixture Road, Testville",observedAt:now)
        let result=await FuelStationPrefillPolicy.resolve(using:FuelLocationFixture(.success(suggestion)))
        var draft=FuelFormDraft();draft.applyStation(try result.get())
        XCTAssertEqual(draft.stationName,"Synthetic Fuel");XCTAssertEqual(draft.stationAddress,"100 Fixture Road, Testville")
        XCTAssertEqual(draft.stationProvenance?.sourceType,.currentLocation)
        var typed=FuelFormDraft();typed.userChangedStationName("My station");typed.applyStation(suggestion)
        XCTAssertEqual(typed.stationName,"My station");XCTAssertTrue(typed.stationAddress.isEmpty)
    }
    @MainActor func testPermissionTimeoutOfflineAndNoResultRemainRecoverable() async {
        for failure in [FuelLocationFailure.permissionDenied,.timeout,.offline,.noResult] {
            let result=await FuelStationPrefillPolicy.resolve(using:FuelLocationFixture(.failure(failure)))
            XCTAssertEqual(try? result.get(),nil);XCTAssertFalse(failure.message.isEmpty)
        }
    }
    func testClearAndRefreshBehaviorIsExplicit() {
        let suggestion=FuelStationSuggestion(stationName:nil,stationAddress:"100 Fixture Road",observedAt:now)
        var draft=FuelFormDraft();draft.applyStation(suggestion);draft.clearStation()
        XCTAssertTrue(draft.stationName.isEmpty);XCTAssertTrue(draft.stationAddress.isEmpty);XCTAssertFalse(draft.stationIsPristine)
        draft.prepareForLocationRefresh();draft.applyStation(suggestion)
        XCTAssertEqual(draft.stationAddress,"100 Fixture Road")
    }
}
