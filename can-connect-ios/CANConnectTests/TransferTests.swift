import XCTest
import CryptoKit
import Security
@testable import CANConnect

private final class HTTPFixture: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int,Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code,data) = try Self.handler!(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:"HTTP/1.1",headerFields:nil)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
final class TransferTests: XCTestCase {
    private func client() throws -> MacServerClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HTTPFixture.self]
        return try MacServerClient(address:"http://mac-mini.local:8765",token:"synthetic-test-token",configuration:config)
    }
    private func trip() -> Trip {
        let date = Date(timeIntervalSince1970:1_700_000_000.123456)
        return Trip(name:"Synthetic GPS fixture",startedAt:date,duration:10,distanceKM:0.1,source:.phoneGPS,isSample:false,route:[RoutePoint(latitude:49,longitude:-124,timestamp:date,accuracy:5,speed:10)])
    }
    func testPrivateEndpointsAndNoCredentialURLs() throws {
        for good in ["http://mac.local:8765","https://192.168.1.10:8765","http://127.0.0.1:18765"] { XCTAssertNoThrow(try MacServerClient.endpoint(good)) }
        for bad in ["https://example.com","http://192.168.1.1/path","http://user:secret@mac.local","http://mac.local?token=secret","ftp://mac.local","http://mac.local:0"] { XCTAssertThrowsError(try MacServerClient.endpoint(bad)) }
    }
    func testWireFormatPreservesGPSProvenanceAndPreciseTimestamps() throws {
        let trip = trip(); let bytes = try MacRecording.encode(trip)
        let archive = try DriveLineArchive.decoded(bytes)
        let recording = try XCTUnwrap(archive.recordings.first)
        XCTAssertEqual(recording.recordingID,trip.id)
        XCTAssertEqual(recording.vehicleID,UUID(uuidString:"00000000-0000-0000-0000-000000000000"))
        XCTAssertNil(try TripArchive.decode(bytes).trips.first?.vehicleID)
        XCTAssertEqual(recording.gpsPoints.first?.timestamp,trip.startedAt)
        XCTAssertEqual(recording.gpsPoints.first?.speedMps,10)
        XCTAssertEqual(try MacRecording.encode(trip),bytes)
        var sample = trip; sample.isSample = true; XCTAssertThrowsError(try MacRecording.encode(sample))
        sample = trip; sample.route = []; XCTAssertThrowsError(try MacRecording.encode(sample))
    }
    func testReceiptMustMatchHashBytesVehicleAndProcessedTrip() throws {
        let vehicle = VehicleProfile()
        var item = TransferItem(tripID:UUID(),name:"test",endpoint:"http://mac.local",vehicle:vehicle,payload:Data("fixture".utf8)); item.remoteVehicleID = vehicle.id
        var receipt = MacReceipt(id:UUID(),vehicleID:vehicle.id,contentHash:item.contentHash,status:"processed",byteCount:item.payload.count,tripIDs:[UUID()])
        XCTAssertNoThrow(try receipt.validate(item:item))
        receipt.contentHash = "wrong"; XCTAssertThrowsError(try receipt.validate(item:item)); receipt.contentHash = item.contentHash
        receipt.byteCount += 1; XCTAssertThrowsError(try receipt.validate(item:item)); receipt.byteCount = item.payload.count
        receipt.vehicleID = UUID(); XCTAssertThrowsError(try receipt.validate(item:item)); receipt.vehicleID = vehicle.id
        receipt.tripIDs = []; XCTAssertThrowsError(try receipt.validate(item:item))
        receipt.status = "queued"; XCTAssertNoThrow(try receipt.validate(item:item))
        item.receiptID = UUID(); XCTAssertThrowsError(try receipt.validate(item:item))
    }
    func testHealthAuthenticationAndInvalidResponses() async throws {
        defer { HTTPFixture.handler = nil }
        HTTPFixture.handler = { request in
            XCTAssertEqual(request.url?.path,"/v1/health")
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer synthetic-test-token")
            return (200,Data(#"{"schemaVersion":1,"service":"CAN CONNECT","ingestion":"paused"}"#.utf8))
        }
        let value = try await client().health(); XCTAssertTrue(value.contains("paused"))
        for status in [401,302,422,503] {
            HTTPFixture.handler = { _ in (status,Data()) }
            do { _ = try await client().health(); XCTFail("Expected HTTP failure") } catch {}
        }
        HTTPFixture.handler = { _ in (200,Data(#"{"status":"ok"}"#.utf8)) }
        do { _ = try await client().health(); XCTFail("Wrong server contract accepted") } catch {}
    }
    func testRemoteVINRequiresTheSameStableVehicleIdentity() async throws {
        defer { HTTPFixture.handler = nil }
        var vehicle = VehicleProfile(); vehicle.vin = "1D4GP00R55B123456"
        let remote = RemoteVehicle(id:UUID(),name:"Existing Mac profile",year:"",make:"",model:"",vin:vehicle.vin!,notes:"")
        HTTPFixture.handler = { request in
            XCTAssertEqual(request.httpMethod,"GET"); XCTAssertEqual(request.url?.path,"/v1/vehicles")
            return (200,try JSONEncoder().encode([remote]))
        }
        do { _ = try await client().resolve(vehicle);XCTFail("Conflicting stable vehicleID accepted") } catch {}
        let matching=RemoteVehicle(id:vehicle.id,name:"Matching profile",year:"",make:"",model:"",vin:vehicle.vin!,notes:"")
        HTTPFixture.handler = { _ in (200,try JSONEncoder().encode([matching])) }
        let resolved=try await client().resolve(vehicle)
        XCTAssertEqual(resolved,vehicle.id)
    }
    func testProcessingReceiptPollsWithoutUploadingAgain() async throws {
        defer { HTTPFixture.handler = nil }
        let vehicle = VehicleProfile()
        var item = TransferItem(tripID:UUID(),name:"Synthetic",endpoint:"http://mac-mini.local:8765",vehicle:vehicle,payload:Data("fixture".utf8))
        item.remoteVehicleID = vehicle.id
        let initial = MacReceipt(id:UUID(),vehicleID:vehicle.id,contentHash:item.contentHash,status:"queued",byteCount:item.payload.count,tripIDs:[])
        var requests = 0
        HTTPFixture.handler = { request in
            requests += 1
            XCTAssertEqual(request.httpMethod,"GET")
            XCTAssertEqual(request.url?.path,"/v1/receipts/\(initial.id.uuidString)")
            let data = try JSONSerialization.data(withJSONObject:["id":initial.id.uuidString,"vehicleID":vehicle.id.uuidString,"contentHash":initial.contentHash,"byteCount":initial.byteCount,"status":requests == 1 ? "processing" : "processed","tripIDs":requests == 1 ? [] : [UUID().uuidString]])
            return (200,data)
        }
        let receipt = try await client().waitForProcessing(initial,item:item,pause:{})
        XCTAssertEqual(receipt.status,"processed"); XCTAssertEqual(requests,2)
    }
    func testProcessingReceiptIsBoundedAndRejectsWrongReceipt() async throws {
        defer { HTTPFixture.handler = nil }
        let vehicle = VehicleProfile()
        var item = TransferItem(tripID:UUID(),name:"Synthetic",endpoint:"http://mac-mini.local:8765",vehicle:vehicle,payload:Data("fixture".utf8))
        item.remoteVehicleID = vehicle.id
        let initial = MacReceipt(id:UUID(),vehicleID:vehicle.id,contentHash:item.contentHash,status:"queued",byteCount:item.payload.count,tripIDs:[])
        var requests = 0; var wrongID = false
        HTTPFixture.handler = { request in
            requests += 1; XCTAssertEqual(request.httpMethod,"GET")
            return (200,try JSONSerialization.data(withJSONObject:["id":(wrongID ? UUID() : initial.id).uuidString,"vehicleID":vehicle.id.uuidString,"contentHash":initial.contentHash,"byteCount":initial.byteCount,"status":"queued","tripIDs":[]]))
        }
        let receipt = try await client().waitForProcessing(initial,item:item,attempts:3,pause:{})
        XCTAssertEqual(receipt.status,"queued"); XCTAssertEqual(requests,3)
        wrongID = true
        do { _ = try await client().waitForProcessing(initial,item:item,pause:{}); XCTFail("Mismatched receipt accepted") } catch {}
        let before = requests
        do { _ = try await client().waitForProcessing(initial,item:item,pause:{throw CancellationError()}); XCTFail("Cancellation ignored") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(requests,before)
    }
    @MainActor
    func testQueuePersistsExactPayloadAndPreventsDeletingUnacknowledgedOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk = LocalStore(url:root.appendingPathComponent("state.json")); let store = AppStore(disk:disk)
        var vehicle = VehicleProfile(); vehicle.make = "Test"; vehicle.model = "Fixture"; try store.saveVehicle(vehicle)
        var recording = trip(); recording.vehicleID = vehicle.id
        store.state.trips.append(recording)
        var empty = recording; empty.id = UUID(); empty.route = []; store.state.trips.append(empty)
        store.state.server.address = "http://mac.local:8765"
        XCTAssertEqual(try store.queueRecordings(),1); XCTAssertEqual(try store.queueRecordings(),0)
        let persisted = try XCTUnwrap(disk.load()?.transfers.first)
        XCTAssertEqual(persisted.payload,try MacRecording.encode(recording))
        store.removeTrip(recording.id); XCTAssertTrue(store.state.trips.contains(where:{$0.id == recording.id}))
        let restarted = AppStore(disk:disk)
        XCTAssertEqual(restarted.state.transfers.first?.payload,persisted.payload)
        XCTAssertEqual(restarted.state.transfers.first?.status,.queued)
    }
    @MainActor
    func testFuelOnlyQueueTransfersStableFillWithoutSamplesOrTripMutation() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let disk=LocalStore(url:root.appendingPathComponent("state.json"));let store=AppStore(disk:disk)
        var vehicle=VehicleProfile();vehicle.make="Synthetic";vehicle.model="Fuel transfer";try store.saveVehicle(vehicle)
        let fill=try store.saveFill(litres:42,cost:70,currencyCode:"CAD",odometer:200_000,full:true,date:Date(timeIntervalSince1970:100),stationName:"Fixture",notes:"Sanitized",allowOdometerCorrection:false)
        store.state.fills.append(FuelEntry(vehicleID:vehicle.id,date:Date(timeIntervalSince1970:200),litres:999,costCAD:0,odometerKM:1,full:true,isSample:true))
        let trip=Trip(vehicleID:vehicle.id,name:"Measured",startedAt:Date(timeIntervalSince1970:100),duration:10,distanceKM:1,source:.scanner,isSample:false,economy:6,fuelLitres:0.06,samples:[OBDSample(timestamp:Date(timeIntervalSince1970:100),signals:["fuelRateLph":3],command:"015E",reply:"SYNTHETIC")])
        store.state.trips=[trip];store.state.server.address="http://mac.local:8765";store.save()
        let before=store.state.trips
        XCTAssertEqual(try store.queueRecordings(),1,"The recording payload already covers the current fill, so no duplicate fuel-only item is needed")
        XCTAssertEqual(store.state.trips,before)
        let tripArchive=try TripArchive.decode(try XCTUnwrap(store.state.transfers.first?.payload))
        XCTAssertEqual(tripArchive.fills.map(\.id),[fill.id]);XCTAssertFalse(tripArchive.fills.contains(where:\.isSample))

        let edited=try store.saveFill(id:fill.id,litres:43,cost:72,currencyCode:"USD",odometer:200_000,full:true,date:Date(timeIntervalSince1970:100),stationName:"Fixture",notes:"Corrected",allowOdometerCorrection:true)
        XCTAssertEqual(try store.queueRecordings(),1)
        let fuelItem=try XCTUnwrap(store.state.transfers.last)
        XCTAssertEqual(fuelItem.fuelEntryIDs,[edited.id])
        let fuelArchive=try TripArchive.decode(fuelItem.payload)
        XCTAssertTrue(fuelArchive.trips.isEmpty);XCTAssertEqual(fuelArchive.fills,[edited])
        var acknowledged=fuelItem;acknowledged.remoteVehicleID=vehicle.id
        let receipt=MacReceipt(id:UUID(),vehicleID:vehicle.id,contentHash:acknowledged.contentHash,status:"processed",byteCount:acknowledged.payload.count,tripIDs:[])
        XCTAssertNoThrow(try receipt.validate(item:acknowledged),"A processed fuel-only transfer does not need a recording ID")
        XCTAssertEqual(store.state.trips,before);XCTAssertEqual(store.state.trips.first?.fuelLitres,0.06)
    }
    @MainActor
    func testNativeMacServerQueueWhenLoopbackIntegrationEnabled() async throws {
        guard let address = ProcessInfo.processInfo.environment["CAN_CONNECT_MAC_TEST_URL"], address.hasPrefix("http://127.0.0.1:") else { throw XCTSkip("Opt-in native Mac integration requires a synthetic loopback server. See README.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at:root)
            SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:PairingSecrets.service,kSecAttrAccount as String:address] as CFDictionary)
        }
        let disk = LocalStore(url:root.appendingPathComponent("state.json")); let store = AppStore(disk:disk)
        var vehicle = VehicleProfile(); vehicle.make = "Synthetic"; vehicle.model = "iOS simulator integration"
        try store.saveVehicle(vehicle)
        var recording = trip(); recording.vehicleID = vehicle.id
        store.state.trips.append(recording)
        try await store.configureServer(address:address,token:"synthetic-ios-transfer-test-token")
        XCTAssertTrue(store.serverStatus.contains("Connected"))
        XCTAssertEqual(try store.queueRecordings(),1)
        let payload = try XCTUnwrap(store.state.transfers.first?.payload)
        await store.sendQueued()
        XCTAssertEqual(store.state.transfers.first?.status,.complete,store.state.transfers.first?.message ?? "No queue entry")
        XCTAssertNotNil(store.state.transfers.first?.receiptID)
        XCTAssertTrue(store.state.trips.contains(where:{$0.id == recording.id}))
        XCTAssertEqual(try disk.load()?.transfers.first?.payload,payload)
        XCTAssertEqual(AppStore(disk:disk).state.transfers.first?.status,.complete)
    }

}
