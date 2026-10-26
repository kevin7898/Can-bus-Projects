import XCTest
@testable import CANConnect

final class VehicleTests: XCTestCase {
    func testProfileEditsWithTheSameIDAreDistinctValues() throws {
        var original = VehicleProfile(); original.make = "Honda"; original.model = "CB500X"
        var edited = original; edited.make = "Ford"; edited.model = "F-150"
        XCTAssertEqual(edited.id,original.id)
        XCTAssertNotEqual(edited,original,"SwiftUI State must observe field edits even when the vehicle identity is unchanged.")
        XCTAssertEqual(edited.title,"Ford F-150")
        edited = original; edited.dashboard.signals["drive.0"] = .voltage
        XCTAssertNotEqual(edited,original)
        edited = original; edited.scannerConnection = ScannerSettings(host:"192.168.0.10",port:35000)
        XCTAssertNotEqual(edited,original)
        XCTAssertEqual(try JSONDecoder().decode(VehicleProfile.self,from:JSONEncoder().encode(edited)),edited)
    }

    func testVINAndELMFormattedAndLegacyReplies() throws {
        let formatted = "0902\r014\r0: 49 02 01 31 44 34\r1: 47 50 30 30 52 35 35\r2: 42 31 32 33 34 35 36\r>"
        XCTAssertEqual(try ELMIdentityParser.vin(formatted),"1D4GP00R55B123456")
        let legacy = "49 02 01 00 31 44 34\r49 02 02 47 50 30 30\r49 02 03 52 35 35 42\r49 02 04 31 32 33 34\r49 02 05 35 36 00 00"
        XCTAssertEqual(try ELMIdentityParser.vin(legacy),"1D4GP00R55B123456")
        XCTAssertNil(try ELMIdentityParser.vin("SEARCHING...\rNO DATA\r>"))
        XCTAssertThrowsError(try VIN.normalized("INVALID"))
        XCTAssertEqual(try VIN.normalized(" 1d4gp00r55b123456 "),"1D4GP00R55B123456")
        let headed="7E8 10 14 49 02 01 33 56 57\r7E8 21 41 41 41 41 41 30 45\r7E8 22 4D 30 30 30 30 30 31\r>"
        XCTAssertEqual(try ELMIdentityParser.vin(headed),"3VWAAAAA0EM000001")
        XCTAssertEqual(ELMIdentityParser.respondingAddress(headed),"7E8")
        XCTAssertNil(try ELMIdentityParser.vin("49 02 01 33 56 57"),"A partial Mode 09 VIN must stay unavailable")
    }
    func testFictional2013JettaReviewRequiresExplicit2014DecisionAndKeepsStableUUID() throws {
        var profile=VehicleProfile();profile.nickname="Fictional Jetta";profile.year=2013;profile.make="Volkswagen";profile.model="Jetta";profile.engine="TDI";profile.fuel = .diesel
        let id=profile.id
        let identity=ScannerIdentity(vin:"3VWAAAAA0EM000001",adapter:"SANITIZED FIXTURE",vehicleProtocol:"ISO 15765-4 CAN",supportedPIDs:[12,13],respondingAddress:"7E8",observedAt:Date(timeIntervalSince1970:1_700_000_000))
        var review=VehicleOnboardingReview(profile)
        try review.receive(vin:try XCTUnwrap(identity.vin),identity:identity)
        XCTAssertEqual(review.draft.year,2013,"Detection must not silently replace the manual year")
        XCTAssertEqual(review.detected?.suggestedModelYear,2014)
        XCTAssertEqual(review.detected?.manufacturer,"Volkswagen")
        XCTAssertEqual(review.draft.identification?.respondingAddress,"7E8")
        review.acceptSuggestedYear()
        XCTAssertEqual(review.completedProfile().year,2014)
        XCTAssertEqual(review.completedProfile().id,id)
    }
    func testFictionalJettaCanRetainEnteredYearAndCancelWithoutMutation() throws {
        var profile=VehicleProfile();profile.year=2013;profile.make="Volkswagen";profile.model="Jetta"
        var review=VehicleOnboardingReview(profile)
        try review.receive(vin:"3VWAAAAA0EM000001",identity:nil)
        review.retainEnteredYear()
        XCTAssertEqual(review.completedProfile().year,2013)
        XCTAssertEqual(review.cancelledProfile(),profile)
    }
    func testLegacyGlobalScannerMigratesOnceToSelectedVehicleWithoutOverwritingOthers() throws {
        var a=VehicleProfile();a.make="Volkswagen";a.model="Jetta"
        var b=VehicleProfile();b.make="Honda";b.model="CB500X";b.scannerConnection=ScannerSettings(host:"192.168.1.22",port:35000)
        var state=StoredState();state.vehicles=[a,b];state.selectedVehicleID=a.id;state.scanner=ScannerSettings(host:"192.168.1.10",port:35000)
        state.migrateVehicles()
        XCTAssertEqual(state.vehicles.first(where:{$0.id==a.id})?.scannerConnection?.host,"192.168.1.10")
        XCTAssertEqual(state.vehicles.first(where:{$0.id==b.id})?.scannerConnection?.host,"192.168.1.22")
    }
    func testOnlyConfirmedPIDBitsAreRecorded() {
        XCTAssertEqual(ELMIdentityParser.supportedPIDs("41 00 00 10 00 00",base:0),[12])
        XCTAssertEqual(ELMIdentityParser.supportedPIDs("41 20 00 00 00 01",base:32),[64])
        XCTAssertTrue(ELMIdentityParser.supportedPIDs("NO DATA",base:0).isEmpty)
    }
    func testPartialVINLookupKeepsUnknownFieldsUnknown() throws {
        let data = Data(#"{"Results":[{"Make":"FORD","Model":"F-150","ModelYear":"2021","FuelTypePrimary":"Gasoline","BodyClass":"Pickup","ErrorCode":"6","TransmissionStyle":null}]}"#.utf8)
        let result = try VINLookup.parse(data,vin:"1D4GP00R55B123456")
        XCTAssertEqual(result.vehicle.kind,.pickup); XCTAssertEqual(result.vehicle.fuel,.gasoline)
        XCTAssertEqual(result.vehicle.transmission,""); XCTAssertNil(result.vehicle.odometerKM); XCTAssertTrue(result.partial)
    }
    func testLegacyDataMigrationKeepsHistoryAndDoesNotGuessMake() throws {
        var legacy = StoredState(); legacy.schemaVersion = 1
        legacy.trips = [Trip(name:"Existing drive",startedAt:Date(),duration:600,distanceKM:5,source:.phoneGPS,isSample:false)]
        let json = try JSONEncoder().encode(legacy)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:json) as? [String:Any])
        object.removeValue(forKey:"vehicles"); object.removeValue(forKey:"selectedVehicleID"); object.removeValue(forKey:"onboardingCompleted")
        var decoded = try JSONDecoder().decode(StoredState.self,from:JSONSerialization.data(withJSONObject:object))
        decoded.migrateVehicles()
        XCTAssertEqual(decoded.schemaVersion,4); XCTAssertEqual(decoded.trips.count,1)
        XCTAssertEqual(decoded.vehicles.first?.title,"Previous vehicle"); XCTAssertEqual(decoded.vehicles.first?.make,"")
        XCTAssertEqual(decoded.trips[0].vehicleID,decoded.selectedVehicleID)
        XCTAssertFalse(decoded.onboardingCompleted)
    }
    @MainActor
    func testVehicleIsolationAndRecordingCannotSwitch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = AppStore(disk:LocalStore(url:directory.appendingPathComponent("state.json")))
        var a = VehicleProfile(); a.make = "Honda"; a.model = "CB500X"; a.kind = .motorcycle
        var b = VehicleProfile(); b.make = "Ford"; b.model = "F-150"; b.kind = .pickup
        try store.saveVehicle(a); store.setSignal(.voltage,slot:"drive.0")
        store.source = .demo // Explicit synthetic recording, independent of Core Location permission.
        store.startRecording(); XCTAssertEqual(store.state.draft?.vehicleID,a.id)
        XCTAssertThrowsError(try store.chooseVehicle(b.id))
        store.finishRecording()
        await store.waitForFinish()
        try store.saveVehicle(b)
        XCTAssertTrue(store.sortedTrips.isEmpty); XCTAssertEqual(store.signal("drive.0"),.coolant)
        try store.chooseVehicle(a.id)
        XCTAssertEqual(store.sortedTrips.count,1); XCTAssertEqual(store.signal("drive.0"),.voltage)
    }
    @MainActor
    func testFuelHistoryDoesNotMixVehiclesAndDuplicateVINIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = AppStore(disk:LocalStore(url:directory.appendingPathComponent("state.json")))
        var a = VehicleProfile(); a.make = "A"; a.model = "One"; a.vin = "1D4GP00R55B123456"
        var b = VehicleProfile(); b.make = "B"; b.model = "Two"
        try store.saveVehicle(a)
        try store.addFill(litres:40,cost:60,odometer:1000,full:true,date:Date(timeIntervalSince1970:100))
        try store.addFill(litres:30,cost:45,odometer:1600,full:true,date:Date(timeIntervalSince1970:200))
        try store.saveVehicle(b)
        try store.addFill(litres:100,cost:150,odometer:9000,full:true,date:Date(timeIntervalSince1970:100))
        try store.addFill(litres:100,cost:150,odometer:10000,full:true,date:Date(timeIntervalSince1970:200))
        XCTAssertEqual(FuelMath.latestEconomy(store.vehicleFills) ?? 0,10,accuracy:0.001)
        try store.chooseVehicle(a.id)
        XCTAssertEqual(FuelMath.latestEconomy(store.vehicleFills) ?? 0,5,accuracy:0.001)
        var duplicate = a; duplicate.id = UUID(); XCTAssertThrowsError(try store.saveVehicle(duplicate))
    }
    @MainActor
    func testFourVehicleClassesKeepIndependentHistoryAndArchiveDoesNotCascade() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store=AppStore(disk:LocalStore(url:directory.appendingPathComponent("state.json")))
        var jetta=VehicleProfile();jetta.year=2013;jetta.make="Volkswagen";jetta.model="Jetta";jetta.kind = .car
        var ford=VehicleProfile();ford.year=2021;ford.make="Ford";ford.model="F-150";ford.kind = .pickup
        var honda=VehicleProfile();honda.year=2023;honda.make="Honda";honda.model="CB500X ABS";honda.kind = .motorcycle
        var kenworth=VehicleProfile();kenworth.year=2025;kenworth.make="Kenworth";kenworth.model="T880";kenworth.kind = .heavyTruck
        for vehicle in [jetta,ford,honda,kenworth] { try store.saveVehicle(vehicle) }
        try store.chooseVehicle(ford.id);try store.addFill(litres:80,cost:140,odometer:20_000,full:true,date:Date())
        try store.setVehicleArchived(ford.id,archived:true)
        XCTAssertEqual(store.state.fills.first(where:{$0.vehicleID==ford.id})?.vehicleID,ford.id)
        XCTAssertTrue(store.state.vehicles.first(where:{$0.id==ford.id})?.isArchived == true)
        XCTAssertThrowsError(try store.deleteEmptyVehicle(ford.id))
        try store.deleteEmptyVehicle(kenworth.id)
        XCTAssertFalse(store.state.vehicles.contains(where:{$0.id==kenworth.id}))
        XCTAssertTrue(store.state.vehicles.contains(where:{$0.id==jetta.id}))
        XCTAssertTrue(store.state.vehicles.contains(where:{$0.id==honda.id}))
    }
}
