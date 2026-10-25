import XCTest
@testable import CANConnectCore

final class JettaSignalImportTests: XCTestCase {
    func testMixedScannerAndGPSRouteSurvivesImportExportAndReload() throws {
        let first = 1700000000.125, second = 1700000005.125
        let rows: [[String:Any]] = [
            ["timestamp":first,"signals":["rpm":832,"speedKph":36],"command":"010C","reply":"SYNTHETIC"],
            ["timestamp":first,"latitude":49.0,"longitude":-124.0,"accuracy":5,"gpsSpeedMps":10],
            ["timestamp":second,"signals":["rpm":840,"speedKph":36],"command":"010C","reply":"SYNTHETIC"],
            ["timestamp":second,"latitude":49.0004,"longitude":-124.0,"accuracy":5,"gpsSpeedMps":10]]
        let payload = try JSONSerialization.data(withJSONObject:["schemaVersion":1,"source":"OBDLink MX+ · Bluetooth","samples":rows])
        let vehicle = UUID(), receipt = UUID()
        let result = try RecordingImporter.parse(data:payload,name:"Synthetic scanner GPS.json",vehicleID:vehicle,receiptID:receipt)
        let trip = try XCTUnwrap(result.trips.first)
        XCTAssertEqual(trip.coordinates.count,2)
        XCTAssertEqual(trip.coordinates.map(\.latitude),[49.0,49.0004])
        XCTAssertEqual(trip.coordinates.map(\.longitude),[-124.0,-124.0])
        XCTAssertEqual(trip.coordinates.map { $0.timestamp.timeIntervalSince1970 },[first,second])
        XCTAssertEqual(trip.samples.compactMap { $0.signals["rpm"] },[832,840])
        XCTAssertEqual(trip.samples.compactMap(\.command),["010C","010C"])
        let restored = try LibraryRepository.decoder().decode(Trip.self,from:LibraryRepository.encoder().encode(trip))
        XCTAssertEqual(restored.coordinates,trip.coordinates)
        let exported = try RecordingImporter.parse(data:TripExport.json(trip),name:"Round trip.json",vehicleID:vehicle,receiptID:receipt)
        XCTAssertEqual(exported.trips.first?.coordinates,trip.coordinates)
        XCTAssertEqual(exported.trips.first?.samples.compactMap(\.reply),["SYNTHETIC","SYNTHETIC"])
    }
    func testExtendedIPhoneFieldsSurviveImportExportAndReload() throws {
        let fields: [String:Double] = ["rpm":831.5,"outsideC":10,"mafGps":7.19,"boostAbsoluteKpa":100.5,"boostCommandedKpa":101.2,
            "egt1C":170.4,"egt2C":144.4,"egt3C":135.6,"egt4C":120.1,"dpfDifferentialKpa":-0.01,
            "dpfRegenActive":0,"dpfRegenType":0,"dpfRegenTrigger":43.13725490196079,"dpfAverageRegenKM":205,
            "dpfAshML":13,"dpfSootG":8.6,"dsgFluidC":80]
        let timestamp = 1700000000.123
        let payload = try JSONSerialization.data(withJSONObject:["schemaVersion":1,"source":"OBDLink MX+ · Bluetooth","samples":[["timestamp":timestamp,"signals":fields,"command":"0178","reply":"SYNTHETIC FIXTURE","obdResponseHeader":"7E8"]]])
        let vehicle=UUID(),receipt=UUID()
        let result=try RecordingImporter.parse(data:payload,name:"synthetic.json",vehicleID:vehicle,receiptID:receipt)
        let trip=try XCTUnwrap(result.trips.first)
        XCTAssertEqual(trip.samples.first?.signals,fields)
        XCTAssertEqual(trip.samples.first?.command,"0178");XCTAssertEqual(trip.samples.first?.responseHeader,"7E8")
        XCTAssertEqual(trip.samples.first?.timestamp.timeIntervalSince1970 ?? 0,timestamp,accuracy:0.000001)
        XCTAssertEqual(trip.vehicleID,vehicle);XCTAssertEqual(trip.receiptID,receipt)
        XCTAssertEqual(Set(trip.availableSignals.map(\.rawValue)),Set(fields.keys))
        let exported=try TripExport.json(trip)
        let roundTrip=try RecordingImporter.parse(data:exported,name:"roundtrip.json",vehicleID:vehicle,receiptID:receipt)
        XCTAssertEqual(roundTrip.trips.first?.samples.first?.signals,fields)
        XCTAssertEqual(roundTrip.trips.first?.samples.first?.reply,"SYNTHETIC FIXTURE")
        let stored=try LibraryRepository.encoder().encode(trip)
        XCTAssertEqual(try LibraryRepository.decoder().decode(Trip.self,from:stored).samples.first?.signals,fields)
        let csv=String(decoding:TripExport.csv(trip),as:UTF8.self)
        XCTAssertTrue(csv.contains("dpfDifferentialKpa"));XCTAssertTrue(csv.contains("mafGps"))
    }
}
