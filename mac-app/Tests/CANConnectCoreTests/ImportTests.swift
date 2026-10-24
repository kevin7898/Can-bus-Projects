import XCTest
@testable import CANConnectCore
#if canImport(CSQLite)
import CSQLite
#else
import SQLite3
#endif

final class ImportTests:XCTestCase {
    let vehicle = UUID()
    func parse(_ text:String) throws -> Trip { try RecordingImporter.parse(data:Data(text.utf8),name:"fixture.csv",vehicleID:vehicle,receiptID:UUID()).trips[0] }
    func testQuotedCSVAndCRLF() throws {
        let rows = try RecordingImporter.csvRows("time,name\r\n\"a,b\",\"say \"\"hi\"\"\"\r\n",delimiter:",")
        XCTAssertEqual(rows,[["time","name"],["a,b","say \"hi\""]])
    }
    func testGPSOnlyNeverFabricatesFuel() throws {
        let trip = try parse("timestamp,latitude,longitude\n2026-10-23T12:00:00Z,49.1,-123.9\n2026-10-23T12:00:01Z,49.1001,-123.9\n")
        XCTAssertGreaterThan(try XCTUnwrap(trip.distanceKm),0)
        XCTAssertNil(trip.economyL100);XCTAssertNil(trip.fuelUsedL);XCTAssertTrue(trip.availableSignals.isEmpty)
    }
    func testSpeedAndFuelIntegrateWithUnits() throws {
        let trip = try parse("timestamp,speedKph,fuelRateLph\n2026-10-23T12:00:00Z,60,3\n2026-10-23T12:00:10Z,60,3\n")
        XCTAssertEqual(try XCTUnwrap(trip.distanceKm),1.0/6,accuracy:0.00001)
        XCTAssertEqual(try XCTUnwrap(trip.economyL100),5,accuracy:0.0001)
    }
    func testSparseFuelAndGPSGapsStayUnknown() throws {
        let trip = try parse("timestamp,speedKph,fuelRateLph\n2026-10-23T12:00:00Z,60,3\n2026-10-23T12:00:30Z,60,3\n")
        XCTAssertNil(trip.distanceKm);XCTAssertNil(trip.fuelUsedL)
    }
    func testChartGapsAndEndpointsSurviveDisplayDownsampling() {
        let start = Date(timeIntervalSince1970:1792756800)
        let samples = (0..<7001).map { i in TelemetrySample(timestamp:start.addingTimeInterval(Double(i)+(i>3500 ? 60:0)),signals:["rpm":Double(i)]) }
        let trip = Trip(vehicleID:vehicle,name:"Synthetic",source:"test",samples:samples)
        let trace = trip.trace(.rpm,limit:3000)
        XCTAssertLessThanOrEqual(trace.count,3000)
        XCTAssertEqual(trace.first?.sample,samples.first);XCTAssertEqual(trace.last?.sample,samples.last)
        XCTAssertEqual(Set(trace.map(\.segment)),[0,1])
        XCTAssertTrue(trip.trace(.fuelRateLph).isEmpty)
        XCTAssertEqual(trip.samples,samples,"Display downsampling must not change imported data")
    }
    func testWebCANIsRawOnly() throws {
        let trip = try parse("TimestampEpoch;BusChannel;ID;IDE;DLC;DataLength;Dir;EDL;BRS;ESI;RTR;DataBytes\n1792756800;0;7E8;0;3;3;0;0;0;0;0;410D3C\n")
        XCTAssertEqual(trip.rawFrameCount,1);XCTAssertEqual(trip.arbitrationIDs["7E8"],1);XCTAssertTrue(trip.availableSignals.isEmpty);XCTAssertNil(trip.distanceKm)
    }
    func testRelativeTimestampsAndUnsupportedColumnsFail() {
        XCTAssertThrowsError(try parse("timestamp,speedKph\n12.5,60\n"))
        XCTAssertThrowsError(try parse("timestamp,unknown\n2026-10-23T12:00:00Z,9\n"))
    }
    func testCanonicalJSONAndInvalidCoordinate() throws {
        let trip = try parse(#"{"schemaVersion":1,"source":"iPhone GPS","samples":[{"timestamp":"2026-10-23T12:00:00.125Z","latitude":1000,"longitude":0,"signals":{"rpm":1500}}]}"#)
        XCTAssertEqual(trip.source,"iPhone GPS");XCTAssertFalse(trip.samples[0].hasCoordinate);XCTAssertEqual(trip.samples[0].value(.rpm),1500)
    }
    func testStandardOBDDecodeAndUnknownProprietary() {
        XCTAssertEqual(PelicanImporter.decode(command:"010C",response:"7E804410C0CFA\r")["rpm"],830.5)
        XCTAssertEqual(PelicanImporter.decode(command:"0105",response:"7E803410563\r")["coolantC"],59)
        XCTAssertTrue(PelicanImporter.decode(command:"2200A0",response:"62FFFF").isEmpty)
    }
    func testPelicanSQLiteImport() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite")
        defer { try? FileManager.default.removeItem(at:url) }
        var db:OpaquePointer?;XCTAssertEqual(sqlite3_open(url.path,&db),SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db,"CREATE TABLE ZCOMMANDRESPONSE (ZSESSION INTEGER,ZTIMESTAMP DOUBLE,ZCOMMAND TEXT,ZRESPONSE BLOB); INSERT INTO ZCOMMANDRESPONSE VALUES (1,814622400.125,'010D',CAST('7E803410D3C' AS BLOB));",nil,nil,nil),SQLITE_OK)
        sqlite3_close(db)
        let result = try PelicanImporter.parse(database:url,vehicleID:vehicle,receiptID:UUID())
        XCTAssertEqual(result.trips[0].diagnosticResponseCount,1);XCTAssertEqual(result.trips[0].samples[0].value(.speedKph),60)
        XCTAssertEqual(result.trips[0].samples[0].timestamp.timeIntervalSinceReferenceDate,814622400.125,accuracy:0.00001)
    }
    func testSQLiteSelectionPreservesWALAndOriginalBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".scanlogs")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("db.sqlite")
        var db:OpaquePointer?;XCTAssertEqual(sqlite3_open(url.path,&db),SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db,"PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE ZCOMMANDRESPONSE (ZSESSION INTEGER,ZTIMESTAMP DOUBLE,ZCOMMAND TEXT,ZRESPONSE BLOB); INSERT INTO ZCOMMANDRESPONSE VALUES (1,814622400.125,'010D',CAST('7E803410D3C' AS BLOB));",nil,nil,nil),SQLITE_OK)
        XCTAssertGreaterThan(try FilePreparation.byteCount(URL(fileURLWithPath:url.path+"-wal")),0)
        let input = try FilePreparation.archiveInput(url)
        defer { if let cleanup = input.cleanup { try? FileManager.default.removeItem(at:cleanup) } }
        let hash = try FilePreparation.hash(input.url)
        let prepared = try FilePreparation.prepare(input.url)
        defer { if let cleanup = prepared.cleanup { try? FileManager.default.removeItem(at:cleanup) } }
        let result = try RecordingImporter.parse(url:prepared.url,vehicleID:vehicle,receiptID:UUID())
        XCTAssertEqual(result.trips[0].diagnosticResponseCount,1)
        XCTAssertEqual(result.trips[0].samples[0].value(.speedKph),60)
        XCTAssertEqual(try FilePreparation.hash(input.url),hash,"Parsing must not mutate the preserved SQLite bundle, including SHM.")
        let repeated = try FilePreparation.archiveInput(url)
        defer { if let cleanup = repeated.cleanup { try? FileManager.default.removeItem(at:cleanup) } }
        XCTAssertEqual(try FilePreparation.hash(repeated.url),hash)
    }
    func testZIPPreservesDatabaseSidecarsAndOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let folder = root.appendingPathComponent("sessions.scanlogs")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let database = folder.appendingPathComponent("db.sqlite")
        var db:OpaquePointer?;XCTAssertEqual(sqlite3_open(database.path,&db),SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db,"PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE ZCOMMANDRESPONSE (ZSESSION INTEGER,ZTIMESTAMP DOUBLE,ZCOMMAND TEXT,ZRESPONSE BLOB); INSERT INTO ZCOMMANDRESPONSE VALUES (1,814622400.125,'010C',CAST('7E804410C0CFA' AS BLOB));",nil,nil,nil),SQLITE_OK)
        let zip = root.appendingPathComponent("archive.zip"), process = Process()
        process.executableURL = URL(fileURLWithPath:"/usr/bin/ditto");process.arguments = ["-c","-k","--keepParent",folder.path,zip.path]
        try process.run();process.waitUntilExit();XCTAssertEqual(process.terminationStatus,0)
        let hash = try FilePreparation.hash(zip),prepared = try FilePreparation.prepare(zip)
        defer { if let cleanup = prepared.cleanup { try? FileManager.default.removeItem(at:cleanup) } }
        let result = try RecordingImporter.parse(url:prepared.url,vehicleID:vehicle,receiptID:UUID())
        XCTAssertEqual(result.trips[0].samples[0].value(.rpm),830.5)
        XCTAssertEqual(try FilePreparation.hash(zip),hash)
    }
    func testAtomicLibraryRoundtripPreservesFractionalTime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let repo = try LibraryRepository(root:root);var state = LibraryState();state.vehicles = [Vehicle(id:vehicle,name:"Synthetic")]
        state.trips = [Trip(vehicleID:vehicle,name:"Synthetic",source:"test",samples:[TelemetrySample(timestamp:Date(timeIntervalSince1970:1792756800.123456),signals:["rpm":1000])])]
        try repo.save(state);let saved = try repo.load()
        XCTAssertEqual(saved.trips[0].start.timeIntervalSince1970,state.trips[0].start.timeIntervalSince1970,accuracy:0.000001)
        try Data("invalid".utf8).write(to:repo.manifest);XCTAssertThrowsError(try repo.load())
    }
    func testDemoCleanupRetainsProfilesWithRealReceipts() {
        var state = LibraryState()
        let removable = Vehicle(name:"Only demo"),retained = Vehicle(name:"Demo with a real import")
        state.vehicles = [removable,retained];state.selectedVehicleID = removable.id
        state.trips = [removable,retained].map { Trip(vehicleID:$0.id,name:"Demo",source:"Synthetic",samples:[],isDemo:true) }
        state.preferences[removable.id.uuidString] = VehiclePreferences()
        var receipt = ImportReceipt(vehicleID:retained.id,originalName:"real.csv",archiveName:"original.csv",contentHash:"hash",byteCount:10)
        receipt.status = .failed;state.receipts = [receipt]
        state.removeDemoData()
        XCTAssertEqual(state.vehicles.map(\.id),[retained.id])
        XCTAssertEqual(state.receipts.map(\.id),[receipt.id])
        XCTAssertEqual(state.selectedVehicleID,retained.id)
        XCTAssertTrue(state.trips.isEmpty);XCTAssertNil(state.preferences[removable.id.uuidString])
    }
    func testHTTPRequestFragmentationAuthenticationAndFraming() throws {
        let body = Data("{}".utf8)
        let wire = Data("POST /v1/recordings?vehicleID=test HTTP/1.1\r\nAuthorization: Bearer test-token\r\nContent-Length: 2\r\n\r\n".utf8)+body
        XCTAssertNil(try HTTPRequest.parse(wire.dropLast()))
        let request = try XCTUnwrap(HTTPRequest.parse(wire));XCTAssertTrue(request.isAuthorized(token:"test-token"));XCTAssertFalse(request.isAuthorized(token:"test-tokem"));XCTAssertEqual(request.path,"/v1/recordings");XCTAssertEqual(request.query["vehicleID"],"test")
        XCTAssertThrowsError(try HTTPRequest.parse(Data("POST / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n{}".utf8)))
        XCTAssertThrowsError(try HTTPRequest.parse(Data("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)))
    }
    func testCSVExportJSONRoundtrip() throws {
        let original = try parse("timestamp,speedKph,rpm\n2026-10-23T12:00:00.125Z,60,1500\n2026-10-23T12:00:01.125Z,61,1520\n")
        let data = try TripExport.json(original);let imported = try RecordingImporter.parse(data:data,name:"roundtrip.json",vehicleID:vehicle,receiptID:UUID()).trips[0]
        XCTAssertEqual(imported.samples,original.samples)
        XCTAssertTrue(String(data:TripExport.csv(original),encoding:.utf8)!.contains("speedKph"))
    }
}
