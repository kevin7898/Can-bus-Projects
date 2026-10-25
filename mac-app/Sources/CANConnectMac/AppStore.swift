import Foundation
import SwiftUI
import AppKit
import CryptoKit
#if canImport(DriveLineShared)
import DriveLineShared
#endif

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var state = LibraryState()
    @Published var error: String?
    @Published var notice: String?
    @Published var page: Workspace = .overview
    @Published var selectedTripID: UUID?
    @Published var serverStatus = "Stopped"
    @Published var ingestionPaused = false
    @Published private(set) var processing = false
    @Published private(set) var readOnly = false
    let repository: LibraryRepository?
    let server = LocalServer()
    private var saveMapTask: Task<Void,Never>?
    private var apiToken: String?
    var selectedVehicle: Vehicle? { state.vehicles.first { $0.id==state.selectedVehicleID } }
    var vehicleTrips: [Trip] { state.trips.filter { $0.vehicleID==state.selectedVehicleID }.sorted { $0.start>$1.start } }
    var selectedTrip: Trip? { vehicleTrips.first { $0.id==selectedTripID } ?? vehicleTrips.first }
    var preferences: VehiclePreferences { state.preferences[state.selectedVehicleID?.uuidString ?? ""] ?? VehiclePreferences() }
    var filteredTrips: [Trip] {
        guard preferences.periodDays > 0 else { return vehicleTrips }
        let earliest = Date().addingTimeInterval(-Double(preferences.periodDays)*86400)
        return vehicleTrips.filter { $0.end >= earliest }
    }
    var realFilteredTrips: [Trip] { filteredTrips.filter { !$0.isDemo } }
    func latestObservation(_ signal: Signal) -> DriveLineObservation? {
        let observations=DriveLineMetricPolicy.latestObservations(vehicleTrips.map(\.sharedRecording))
        return signal == .boostKpa ? DriveLineMetricPolicy.boostGaugeKpa(observations:observations) : observations[signal.rawValue]
    }
    var libraryURL: URL { repository?.root ?? FileManager.default.homeDirectoryForCurrentUser }
    var receiptList: [ImportReceipt] { state.receipts.sorted { $0.createdAt>$1.createdAt } }
    init(root:URL? = nil) {
        let path = root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CANConnect",isDirectory:true)
        var repo:LibraryRepository?
        var startupError:String?
        do { repo = try LibraryRepository(root:path) } catch { startupError = "Cannot open library: \(error.localizedDescription)" }
        repository = repo
        if let startupError = startupError { self.error = startupError; readOnly = true }
        if let repo = repo {
            do {
                state = try repo.load()
                if state.receipts.contains(where:{$0.status == .processing}) {
                    try commit { state in
                        for i in state.receipts.indices where state.receipts[i].status == .processing { state.receipts[i].status = .queued; state.receipts[i].message = "Recovered interrupted import; original preserved" }
                    }
                }
            } catch { self.error = "Library could not be read. Existing files were kept. \(error.localizedDescription)"; readOnly = true }
        }
        server.onState = { [weak self] value in DispatchQueue.main.async { self?.serverStatus = value } }
        Task { [weak self] in
            guard let self = self else { return }
            if self.state.autoStartServer { self.startServer() }
            await self.processPending()
        }
    }
    private func commit(_ update:(inout LibraryState)->Void) throws {
        guard !readOnly, let repository = repository else { throw CANError.invalid("Library is read-only because startup failed. Resolve the library error before writing.") }
        var next = state; update(&next); try repository.save(next); state = next
    }
    func perform(_ action:() throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
    func selectVehicle(_ id:UUID) { perform { try commit { $0.selectedVehicleID = id } }; selectedTripID = nil }
    func saveVehicle(_ vehicle:Vehicle) throws {
        guard !vehicle.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw CANError.invalid("Give this vehicle a name.") }
        if !vehicle.vin.isEmpty {
            guard vehicle.vin.count==17, vehicle.vin.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber)}), !vehicle.vin.uppercased().contains(where:{"IOQ".contains($0)}) else { throw CANError.invalid("VIN must have 17 valid letters and numbers, excluding I, O, and Q.") }
            guard !state.vehicles.contains(where:{$0.id != vehicle.id && $0.vin.uppercased()==vehicle.vin.uppercased()}) else { throw CANError.invalid("This VIN already has a vehicle profile.") }
        }
        try commit { state in
            if let i = state.vehicles.firstIndex(where:{$0.id==vehicle.id}) { state.vehicles[i] = vehicle }
            else { state.vehicles.append(vehicle) }
            state.selectedVehicleID = vehicle.id
        }
    }
    func changePreferences(_ body:(inout VehiclePreferences)->Void) {
        guard let id = state.selectedVehicleID else { return }
        var p = preferences; body(&p); perform { try commit { $0.preferences[id.uuidString] = p } }
    }
    func setMap(_ viewport:MapViewport) {
        saveMapTask?.cancel()
        guard let id = state.selectedVehicleID,preferences.map != viewport else { return }
        saveMapTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds:400_000_000)
            guard !Task.isCancelled, let self = self else { return }
            self.perform { try self.commit { state in var p = state.preferences[id.uuidString] ?? VehiclePreferences(); p.map = viewport; state.preferences[id.uuidString] = p } }
        }
    }
    func importFiles() {
        guard let vehicleID = state.selectedVehicleID else { page = .garage; notice = "Add or select a vehicle before importing."; return }
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.message = "Choose CSV, JSON, candump, webCAN, a Pelican .scanlogs folder, or its ZIP archive."
        let completion:(NSApplication.ModalResponse)->Void = { [weak self] response in
            guard response == .OK,let self = self else { return }
            for url in panel.urls { self.perform { _ = try self.enqueue(url,vehicleID:vehicleID) } }
            self.page = .imports;Task { await self.processPending() }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for:window,completionHandler:completion) }
        else { panel.begin(completionHandler:completion) }
    }
    @discardableResult func enqueue(_ url:URL, vehicleID:UUID) throws -> ImportReceipt {
        guard state.vehicles.contains(where:{$0.id==vehicleID}), let repo = repository else { throw CANError.invalid("Select an existing vehicle.") }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let input = try FilePreparation.archiveInput(url)
        defer { if let cleanup = input.cleanup { try? FileManager.default.removeItem(at:cleanup) } }
        let bytes = try FilePreparation.byteCount(input.url)
        guard bytes>0,bytes<=RecordingImporter.maxBytes else { throw CANError.invalid("\(url.lastPathComponent) is \(ByteCountFormatter.string(fromByteCount:Int64(bytes),countStyle:.file)). Choose a non-empty recording of at most 50 MB.") }
        let hash = try FilePreparation.hash(input.url)
        if let duplicate = state.receipts.first(where:{$0.vehicleID==vehicleID && $0.contentHash==hash}) { notice = "This recording already has a receipt (\(duplicate.status.rawValue))."; return duplicate }
        var isDirectory:ObjCBool = false; FileManager.default.fileExists(atPath:input.url.path,isDirectory:&isDirectory)
        let suffix = isDirectory.boolValue ? "scanlogs" : url.pathExtension.lowercased()
        let archiveName = UUID().uuidString + (suffix.isEmpty ? "" : "."+suffix)
        let destination = repo.originals.appendingPathComponent(archiveName)
        try FileManager.default.copyItem(at:input.url,to:destination)
        let receipt = ImportReceipt(vehicleID:vehicleID,originalName:url.lastPathComponent,archiveName:archiveName,contentHash:hash,byteCount:bytes)
        do { try commit { $0.receipts.append(receipt) } } catch { try? FileManager.default.removeItem(at:destination); throw error }
        return receipt
    }
    func retry(_ id:UUID) { perform { try commit { state in if let i = state.receipts.firstIndex(where:{$0.id==id}) { state.receipts[i].status = .queued; state.receipts[i].message = "Queued for retry" } } }; Task { await processPending() } }
    func processPending() async {
        guard !processing,!ingestionPaused,!readOnly,let repo = repository else { return }
        processing = true; defer { processing = false }
        while !ingestionPaused, let receipt = state.receipts.first(where:{$0.status == .queued}) {
            do {
                try commit { state in if let i = state.receipts.firstIndex(where:{$0.id==receipt.id}) { state.receipts[i].status = .processing; state.receipts[i].message = "Processing preserved original" } }
                let url = repo.originalURL(receipt)
                let result = try await Task.detached(priority:.userInitiated) {
                    let prepared = try FilePreparation.prepare(url)
                    defer { if let cleanup = prepared.cleanup { try? FileManager.default.removeItem(at:cleanup) } }
                    return try RecordingImporter.parse(url:prepared.url,vehicleID:receipt.vehicleID,receiptID:receipt.id)
                }.value
                try commit { state in
                    let stableIDs = Set(result.trips.map(\.id))
                    state.trips.removeAll { $0.receiptID==receipt.id || stableIDs.contains($0.id) }
                    state.trips.append(contentsOf:result.trips)
                    let incomingFillIDs=Set(result.fuelEntries.map(\.id))
                    state.fuelEntries.removeAll { incomingFillIDs.contains($0.id) }
                    state.fuelEntries.append(contentsOf:result.fuelEntries)
                    if let i = state.receipts.firstIndex(where:{$0.id==receipt.id}) {
                        state.receipts[i].status = .processed; state.receipts[i].message = result.message; state.receipts[i].completedAt = Date(); state.receipts[i].tripIDs = result.trips.map(\.id)
                    }
                }
            } catch {
                do { try commit { state in if let i = state.receipts.firstIndex(where:{$0.id==receipt.id}) { state.receipts[i].status = .failed; state.receipts[i].message = error.localizedDescription } } }
                catch { self.error = "Import status could not be saved. Original preserved: \(error.localizedDescription)"; break }
            }
        }
    }
    func togglePause() { ingestionPaused.toggle(); if !ingestionPaused { Task { await processPending() } } }
    func startServer() {
        perform {
            let token = try apiToken ?? PairingKeychain.token(); apiToken = token
            serverStatus = "Starting"
            try server.start(port:state.serverPort,allowLAN:state.allowLAN,token:token) { [weak self] request in
                guard let self = self else { return HTTPResponse(503,json:["error":"App unavailable"]) }
                return await self.handle(request)
            }
            try commit { $0.autoStartServer = true }
        }
    }
    func startHeadless(port:UInt16,token:String) throws {
        apiToken = token
        try server.start(port:port,allowLAN:false,token:token) { [weak self] request in
            guard let self = self else { return HTTPResponse(503,json:["error":"App unavailable"]) }; return await self.handle(request)
        }
    }
    func stopServer() { server.stop(); serverStatus = "Stopped"; perform { try commit { $0.autoStartServer = false } } }
    func configureServer(port:UInt16,lan:Bool) { perform { try commit { $0.serverPort = port; $0.allowLAN = lan } }; if serverStatus=="Listening" { startServer() } }
    func copyToken() { perform { let token = try apiToken ?? PairingKeychain.token(); apiToken = token; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(token,forType:.string); notice = "Pairing token copied." } }
    func openLibrary() { NSWorkspace.shared.open(libraryURL) }
    func backup() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.message = "Choose a destination for a complete library backup."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { guard let repo = repository else { return }; let backup = try repo.backup(to:url); NSWorkspace.shared.activateFileViewerSelecting([backup]); notice = "Backup completed." }
    }
    func export(_ trip:Trip,asJSON:Bool = true) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "CAN-Connect-"+trip.id.uuidString+(asJSON ? ".json" : ".csv")
        guard panel.runModal() == .OK,let url = panel.url else { return }
        perform { let data = asJSON ? try TripExport.json(trip,fuelEntries:state.fuelEntries) : TripExport.csv(trip); try data.write(to:url,options:.atomic); notice = "Recording exported." }
    }
    func loadDemo() {
        perform {
            let vehicle = Vehicle(name:"Jetta TDI · DEMO",year:"2014",make:"Volkswagen",model:"Jetta",notes:"Synthetic demo recordings. Remove this profile from the library manually if no longer needed.")
            let start = Date().addingTimeInterval(-3600)
            let trips = (0..<3).map { offset -> Trip in
                let samples = (0...360).map { i -> TelemetrySample in
                    let t = Double(i), speed = max(0,55+22*sin(t/28))
                    return TelemetrySample(timestamp:start.addingTimeInterval(Double(-offset*86400)+t),latitude:49.16+t*0.00012,longitude:-123.95-t*0.00008,signals:[Signal.speedKph.rawValue:speed,Signal.rpm.rawValue:1500+speed*10,Signal.coolantC.rawValue:88,Signal.fuelRateLph.rawValue:3.2+sin(t/24),Signal.voltage.rawValue:14.1])
                }
                return Trip(vehicleID:vehicle.id,name:"Demo drive \(offset+1)",source:"Synthetic demo",samples:samples,isDemo:true)
            }
            try commit { $0.vehicles.append(vehicle); $0.trips.append(contentsOf:trips); $0.selectedVehicleID = vehicle.id }
        }
    }
    func removeDemo() {
        perform { try commit { $0.removeDemoData() } }
    }
    private func handle(_ request:HTTPRequest) async -> HTTPResponse {
        do {
            switch (request.method,request.path) {
            case ("GET","/v1/health"):
                return HTTPResponse(200,json:["schemaVersion":1,"service":"CAN CONNECT","ingestion":ingestionPaused ? "paused" : "running","queued":state.receipts.filter{$0.status == .queued}.count])
            case ("GET","/v1/vehicles"): return HTTPResponse(200,data:try LibraryRepository.encoder().encode(state.vehicles))
            case ("POST","/v1/vehicles"):
                let vehicle = try LibraryRepository.decoder().decode(Vehicle.self,from:request.body); try saveVehicle(vehicle)
                return HTTPResponse(201,data:try LibraryRepository.encoder().encode(vehicle))
            case ("GET","/v1/trips"):
                let filter = request.query["vehicleID"].flatMap(UUID.init(uuidString:))
                let trips = state.trips.filter { filter == nil || $0.vehicleID==filter }
                return HTTPResponse(200,json:["trips":trips.map { ["id":$0.id.uuidString,"vehicleID":$0.vehicleID.uuidString,"name":$0.name,"source":$0.source,"sampleCount":$0.samples.count,"rawFrameCount":$0.rawFrameCount,"isDemo":$0.isDemo] as [String:Any] }])
            case ("POST","/v1/recordings"):
                guard !readOnly else { return HTTPResponse(503,json:["error":"Library is read-only"]) }
                let object = try JSONSerialization.jsonObject(with:request.body) as? [String:Any]
                guard let id = UUID(uuidString:request.query["vehicleID"] ?? object?["vehicleID"] as? String ?? ""), state.vehicles.contains(where:{$0.id==id}) else { return HTTPResponse(422,json:["error":"An existing vehicleID is required"]) }
                // Validate syntax/schema before acknowledging an upload; receipt processing remains separate.
                let parsed = try RecordingImporter.parse(data:request.body,name:"companion.json",vehicleID:id,receiptID:UUID())
                let requestHash = SHA256.hash(data:request.body).map { String(format:"%02x",$0) }.joined()
                for stableID in parsed.trips.map(\.id) {
                    if let existing = state.trips.first(where:{$0.id == stableID}),
                       let existingReceipt = state.receipts.first(where:{$0.id == existing.receiptID}) {
                        guard existingReceipt.contentHash == requestHash else {
                            return HTTPResponse(409,json:["error":"recordingID already exists with different content; original preserved"])
                        }
                        return HTTPResponse(200,data:try LibraryRepository.encoder().encode(existingReceipt))
                    }
                }
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
                try request.body.write(to:temp,options:.atomic); defer { try? FileManager.default.removeItem(at:temp) }
                let receipt = try enqueue(temp,vehicleID:id)
                Task { await processPending() }
                return HTTPResponse(receipt.status == .processed ? 200 : 202,data:try LibraryRepository.encoder().encode(receipt))
            default:
                if request.method=="GET",request.path.hasPrefix("/v1/receipts/"),let id = UUID(uuidString:String(request.path.dropFirst("/v1/receipts/".count))),let receipt = state.receipts.first(where:{$0.id==id}) { return HTTPResponse(200,data:try LibraryRepository.encoder().encode(receipt)) }
                if request.method=="GET",request.path.hasPrefix("/v1/trips/"),let id = UUID(uuidString:String(request.path.dropFirst("/v1/trips/".count))),let trip = state.trips.first(where:{$0.id==id}) { return HTTPResponse(200,data:try TripExport.json(trip,fuelEntries:state.fuelEntries)) }
                return HTTPResponse(404,json:["error":"Route not found"])
            }
        } catch { return HTTPResponse(422,json:["error":error.localizedDescription]) }
    }
}
