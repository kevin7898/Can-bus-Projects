import Foundation
import CryptoKit
import Security

struct ServerSettings: Codable {
    var address = ""
}
enum TransferStatus: String, Codable { case queued, awaitingReceipt, complete, failed }
struct TransferItem: Codable, Identifiable {
    var id = UUID()
    var tripID: UUID
    var name: String
    var endpoint: String
    var vehicle: VehicleProfile
    var payload: Data
    var fuelEntryIDs:[UUID]? = nil
    var receiptID: UUID?
    var remoteVehicleID: UUID?
    var status: TransferStatus = .queued
    var message = "Waiting to send"
    var contentHash: String { Self.hash(payload) }
    static func hash(_ payload:Data)->String { SHA256.hash(data:payload).map { String(format:"%02x",$0) }.joined() }
}
extension TransferItem {
    var semanticState:DriveLineSemanticState {
        switch status { case .queued:return .queued;case .awaitingReceipt:return .processing;case .complete:return .complete;case .failed:return .failed }
    }
    var statusTitle:String {
        switch status { case .queued:return "Queued";case .awaitingReceipt:return "Acknowledged · processing";case .complete:return "Transferred · processed";case .failed:return "Failed" }
    }
}

// Stable source payload: retry sends the identical bytes, allowing Mac content-hash deduplication.
enum MacRecording {
    static func encode(_ trip: Trip, fills: [FuelEntry] = [],receiptFiles:[String:Data] = [:]) throws -> Data {
        guard trip.scannerTransport == nil || trip.source == .scanner else { throw AppFailure("Scanner transport metadata requires a scanner recording.") }
        guard !trip.isSample else { throw AppFailure("Sample recordings cannot be uploaded as real vehicle data.") }
        guard !trip.route.isEmpty || trip.samples?.isEmpty == false else { throw AppFailure("This recording has no measured scanner samples or GPS points to transfer.") }
        var compatible=trip
        // Old receivers cannot label matched partial economy. Preserve explicit
        // metadata, but never place it in their unlabeled whole-trip field.
        if compatible.matchedEconomy?.isPartial == true { compatible.economy=nil }
        let bytes = try TripArchive(vehicles:nil,trips:[compatible],fills:fills.filter { !$0.isSample && $0.vehicleID == trip.vehicleID },receiptFiles:receiptFiles).encoded()
        guard bytes.count <= 100*1024*1024 else { throw AppFailure("This recording and its receipts exceed the Mac's 100 MB transfer limit. Export it for manual handling.") }
        return bytes
    }
    static func encodeFills(vehicle:VehicleProfile,fills:[FuelEntry],receiptFiles:[String:Data] = [:]) throws ->Data {
        let real=fills.filter { !$0.isSample && $0.vehicleID==vehicle.id }
        guard !real.isEmpty else { throw AppFailure("There are no real fuel entries to transfer.") }
        let bytes=try TripArchive(vehicles:[vehicle],trips:[],fills:real,receiptFiles:receiptFiles).encoded()
        guard bytes.count<=100*1024*1024 else { throw AppFailure("Fuel entries and receipts exceed the Mac's 100 MB transfer limit.") }
        return bytes
    }
}

enum PairingSecrets {
    static let service = "com.canconnect.companion.mac"
    static func read(endpoint: String) throws -> String {
        var result: CFTypeRef?
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:endpoint,kSecReturnData as String:true]
        let status = SecItemCopyMatching(query as CFDictionary,&result)
        guard status == errSecSuccess, let data = result as? Data, let token = String(data:data,encoding:.utf8) else {
            throw AppFailure("Enter this Mac's pairing token in server setup.")
        }
        return token
    }
    static func save(_ token: String, endpoint: String) throws {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:endpoint]
        let values: [String:Any] = [kSecValueData as String:Data(token.utf8),kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary,values as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(values,uniquingKeysWith:{$1}) as CFDictionary,nil) == errSecSuccess else { throw AppFailure("Could not save the pairing token in Keychain.") }
        } else if status != errSecSuccess { throw AppFailure("Could not update the pairing token in Keychain (\(status)). Run a normally signed Xcode build and retry.") }
    }
}

struct RemoteVehicle: Codable {
    var id: UUID
    var name: String
    var year: String
    var make: String
    var model: String
    var vin: String
    var notes: String
    var vehicleClass:DriveLineVehicleClass?=nil
    var fuelType:String?=nil
    var preferredUnits:DriveLineUnitSystem?=nil
    var preferredGPS:DriveLineGPSPreference?=nil
    var configuredSources:[DriveLineVehicleSource]?=nil
    var isArchived:Bool?=nil
}
struct MacReceipt: Decodable {
    var id: UUID
    var vehicleID: UUID
    var contentHash: String
    var status: String
    var byteCount: Int
    var tripIDs: [UUID]
    func validate(item: TransferItem) throws {
        guard id == (item.receiptID ?? id), vehicleID == item.remoteVehicleID,
              contentHash.lowercased() == item.contentHash, byteCount == item.payload.count,
              ["queued","processing","processed","failed"].contains(status),
              status != "processed" || item.fuelEntryIDs != nil || !tripIDs.isEmpty else { throw AppFailure("The Mac receipt does not match this recording. The original remains on this iPhone.") }
    }
}

// Redirects are rejected so a bearer token never follows an endpoint to another host.
final class NoServerRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class MacServerClient {
    let endpoint: URL
    private let token: String
    private let session: URLSession
    init(address: String, token: String, cellular: Bool = false, configuration: URLSessionConfiguration? = nil) throws {
        endpoint = try Self.endpoint(address)
        guard !token.isEmpty, token.count < 4096, !token.contains(where:{$0.isWhitespace || $0.isNewline}) else { throw AppFailure("Enter the Mac pairing token exactly as copied.") }
        self.token = token
        let config = configuration ?? .ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
        config.allowsCellularAccess = cellular; config.urlCache = nil
        session = URLSession(configuration:config,delegate:NoServerRedirects(),delegateQueue:nil)
    }
    deinit { session.invalidateAndCancel() }
    static func endpoint(_ address: String) throws -> URL {
        guard var c = URLComponents(string:address.trimmingCharacters(in:.whitespacesAndNewlines)),
              ["http","https"].contains(c.scheme?.lowercased() ?? ""), let host = c.host,
              ELMWiFiSession.isLocalHost(host) || host == "127.0.0.1" || host == "localhost",
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", c.port.map({(1...65535).contains($0)}) ?? true,
              c.url != nil else { throw AppFailure("Use a private Mac server address such as http://mac-mini.local:8765, with no path or credentials.") }
        c.scheme = c.scheme?.lowercased(); c.host = host.lowercased(); c.path = ""
        return c.url!
    }
    func request(_ method: String, path: String, body: Data? = nil, vehicleID: UUID? = nil) async throws -> Data {
        var components = URLComponents(url:endpoint.appendingPathComponent(path),resolvingAgainstBaseURL:false)!
        if let vehicleID { components.queryItems = [URLQueryItem(name:"vehicleID",value:vehicleID.uuidString)] }
        var request = URLRequest(url:components.url!)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let (data,response) = try await DriveLinePerformance.measureAsync("Transfer request") { try await session.data(for:request) }
        guard let http = response as? HTTPURLResponse else { throw AppFailure("No HTTP response from the Mac.") }
        guard (200...202).contains(http.statusCode) else {
            switch http.statusCode {
            case 401,403: throw AppFailure("The Mac rejected the pairing token. Update it in server setup.")
            case 300...399: throw AppFailure("The server redirected the request. Enter its direct local address.")
            default: throw AppFailure("Mac request failed (HTTP \(http.statusCode)). Recording kept for retry.")
            }
        }
        guard data.count <= 2_000_000 else { throw AppFailure("The Mac response is too large.") }
        return data
    }
    func health() async throws -> String {
        let bytes = try await request("GET",path:"v1/health")
        let json = try JSONSerialization.jsonObject(with:bytes) as? [String:Any]
        guard json?["schemaVersion"] as? Int == 1, json?["service"] as? String == "CAN CONNECT",
              let ingestion = json?["ingestion"] as? String, ["running","paused"].contains(ingestion) else { throw AppFailure("This server does not provide CAN CONNECT API v1.") }
        return ingestion == "paused" ? "Connected · Mac ingestion paused" : "Connected · ready for recordings"
    }
    func resolve(_ vehicle: VehicleProfile) async throws -> UUID {
        let data = try await request("GET",path:"v1/vehicles")
        let vehicles = try JSONDecoder().decode([RemoteVehicle].self,from:data)
        if let match = vehicles.first(where: { $0.id == vehicle.id }) {
            guard match.vin.isEmpty || vehicle.vin?.uppercased() == match.vin.uppercased() else { throw AppFailure("The Mac vehicle ID belongs to a different VIN.") }
            return match.id
        }
        if let vin = vehicle.vin, vehicles.contains(where:{$0.vin.uppercased() == vin && $0.id != vehicle.id}) {
            throw AppFailure("The Mac already has this VIN under a different stable vehicleID. Reconcile the vehicle profiles before transferring.")
        }
        let remote = RemoteVehicle(id:vehicle.id,name:vehicle.title,year:vehicle.year.map(String.init) ?? "",make:vehicle.make,model:vehicle.model,vin:vehicle.vin ?? "",notes:"Created by iOS companion",
            vehicleClass:vehicle.kind.shared,fuelType:vehicle.fuel.title,preferredUnits:vehicle.preferredUnits,
            preferredGPS:vehicle.preferredGPS,configuredSources:vehicle.configuredSources,isArchived:vehicle.isArchived)
        let response = try await request("POST",path:"v1/vehicles",body:JSONEncoder().encode(remote))
        let saved = try JSONDecoder().decode(RemoteVehicle.self,from:response)
        guard saved.id == remote.id, saved.vin == remote.vin else { throw AppFailure("The Mac did not acknowledge this vehicle.") }
        return saved.id
    }
    // Poll only an acknowledged receipt, never re-upload while processing.
    // Paused/slow ingestion remains pending after a bounded foreground check.
    func waitForProcessing(_ initial: MacReceipt, item: TransferItem,
                           attempts: Int = 8,
                           pause: () async throws -> Void = { try await Task.sleep(nanoseconds:1_000_000_000) }) async throws -> MacReceipt {
        try initial.validate(item:item)
        var receipt = initial
        var acknowledged = item; acknowledged.receiptID = initial.id
        for _ in 0..<max(0,attempts) {
            guard receipt.status == "queued" || receipt.status == "processing" else { break }
            try await pause()
            try Task.checkCancellation()
            receipt = try await self.receipt(for:acknowledged)
        }
        return receipt
    }
    func receipt(for item: TransferItem) async throws -> MacReceipt {
        let data: Data
        if let id = item.receiptID { data = try await request("GET",path:"v1/receipts/\(id.uuidString)") }
        else {
            guard let id = item.remoteVehicleID else { throw AppFailure("Select the Mac vehicle first.") }
            data = try await request("POST",path:item.fuelEntryIDs == nil ? "v1/recordings":"v1/fuel-entries",body:item.payload,vehicleID:id)
        }
        let receipt = try JSONDecoder().decode(MacReceipt.self,from:data)
        try receipt.validate(item:item)
        return receipt
    }
}
