import XCTest
@testable import CANConnect

final class VehicleTests: XCTestCase {
    func testVINAndELMFormattedAndLegacyReplies() throws {
        let formatted = "0902\r014\r0: 49 02 01 31 44 34\r1: 47 50 30 30 52 35 35\r2: 42 31 32 33 34 35 36\r>"
        XCTAssertEqual(try ELMIdentityParser.vin(formatted),"1D4GP00R55B123456")
        let legacy = "49 02 01 00 31 44 34\r49 02 02 47 50 30 30\r49 02 03 52 35 35 42\r49 02 04 31 32 33 34\r49 02 05 35 36 00 00"
        XCTAssertEqual(try ELMIdentityParser.vin(legacy),"1D4GP00R55B123456")
        XCTAssertNil(try ELMIdentityParser.vin("SEARCHING...\rNO DATA\r>"))
        XCTAssertThrowsError(try VIN.normalized("INVALID"))
        XCTAssertEqual(try VIN.normalized(" 1d4gp00r55b123456 "),"1D4GP00R55B123456")
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
        XCTAssertEqual(decoded.schemaVersion,2); XCTAssertEqual(decoded.trips.count,1)
        XCTAssertEqual(decoded.vehicles.first?.title,"Previous vehicle"); XCTAssertEqual(decoded.vehicles.first?.make,"")
        XCTAssertEqual(decoded.trips[0].vehicleID,decoded.selectedVehicleID)
        XCTAssertFalse(decoded.onboardingCompleted)
    }
    @MainActor
    func testVehicleIsolationAndRecordingCannotSwitch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = AppStore(disk:LocalStore(url:directory.appendingPathComponent("state.json")))
        var a = VehicleProfile(); a.make = "Honda"; a.model = "CB500X"; a.kind = .motorcycle
        var b = VehicleProfile(); b.make = "Ford"; b.model = "F-150"; b.kind = .pickup
        try store.saveVehicle(a); store.setSignal(.voltage,slot:"drive.0")
        store.startRecording(); XCTAssertEqual(store.state.draft?.vehicleID,a.id)
        XCTAssertThrowsError(try store.chooseVehicle(b.id))
        store.finishRecording()
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
}
