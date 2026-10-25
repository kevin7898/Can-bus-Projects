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
    @Published var page: Workspace = .today
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
    func journeyAnnotation(for recordingID:UUID)->DriveLineJourneyAnnotation {
        state.journeyAnnotations[recordingID.uuidString] ?? DriveLineJourneyAnnotation(recordingID:recordingID)
    }
    func saveJourneyAnnotation(_ annotation:DriveLineJourneyAnnotation) {
        var value=annotation
        value.note=value.note?.trimmingCharacters(in:.whitespacesAndNewlines)
        value.startPlace=value.startPlace?.trimmingCharacters(in:.whitespacesAndNewlines)
        value.finishPlace=value.finishPlace?.trimmingCharacters(in:.whitespacesAndNewlines)
        value.updatedAt=Date()
        perform { try commit { $0.journeyAnnotations[value.recordingID.uuidString]=value } }
    }
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
    func selectVehicle(_ id:UUID) {
        perform {
            guard let vehicle=state.vehicles.first(where:{$0.id==id}),!vehicle.isArchived else { throw CANError.invalid("Restore this archived vehicle before selecting it.") }
            try commit { $0.selectedVehicleID = id }
        }
        selectedTripID = nil
    }
    func saveVehicle(_ vehicle:Vehicle) throws {
        var value=vehicle
        value.name=value.name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.name.isEmpty else { throw CANError.invalid("Give this vehicle a name.") }
        if !value.vin.isEmpty {
            do { value.vin=try DriveLineVINDecoder.normalized(value.vin) }
            catch { throw CANError.invalid(error.localizedDescription) }
            guard !state.vehicles.contains(where:{$0.id != value.id && $0.vin.uppercased()==value.vin.uppercased()}) else { throw CANError.invalid("This VIN already has a vehicle profile.") }
        }
        try commit { state in
            if let i = state.vehicles.firstIndex(where:{$0.id==value.id}) { state.vehicles[i] = value }
            else { state.vehicles.append(value) }
            if !value.isArchived { state.selectedVehicleID = value.id }
        }
    }
    func setVehicleArchived(_ id:UUID, archived:Bool) throws {
        guard state.vehicles.contains(where:{$0.id==id}) else { throw CANError.invalid("Vehicle not found.") }
        try commit { state in
            guard let index=state.vehicles.firstIndex(where:{$0.id==id}) else { return }
            state.vehicles[index].isArchived=archived
            state.vehicles[index].archivedAt=archived ? Date() : nil
            if archived,state.selectedVehicleID==id {
                state.selectedVehicleID=state.vehicles.first(where:{$0.id != id && !$0.isArchived})?.id
            }
        }
        selectedTripID=nil
    }
    func deleteEmptyVehicle(_ id:UUID) throws {
        guard !state.trips.contains(where:{$0.vehicleID==id}),
              !state.receipts.contains(where:{$0.vehicleID==id}),
              !state.fuelEntries.contains(where:{$0.vehicleID==id}) else {
            throw CANError.invalid("Archive this vehicle instead. A profile with recordings, imports, or fuel entries cannot be permanently deleted.")
        }
        try commit { state in
            state.vehicles.removeAll {$0.id==id}
            state.preferences.removeValue(forKey:id.uuidString)
            if state.selectedVehicleID==id { state.selectedVehicleID=state.vehicles.first(where:{!$0.isArchived})?.id }
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
                try repo.storeReceiptFiles(result.receiptFiles,for:result.fuelEntries)
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
        perform { let data = asJSON ? try TripExport.json(trip,fuelEntries:state.fuelEntries,receiptFiles:repository?.archivedReceiptFiles(state.fuelEntries) ?? [:]) : TripExport.csv(trip); try data.write(to:url,options:.atomic); notice = "Recording exported." }
    }
    func receiptURL(_ metadata:DriveLineReceiptMetadata)->URL? { repository.flatMap { $0.receiptData(metadata)==nil ? nil:$0.receiptURL(metadata) } }
    func openReceipt(_ metadata:DriveLineReceiptMetadata) {
        guard let url=receiptURL(metadata) else { error="The receipt file is missing. Its metadata remains preserved.";return }
        NSWorkspace.shared.open(url)
    }
    func loadDemo() {
        perform {
            let vehicle = Vehicle(name:"Fictional Jetta · DEMO",year:"2013",make:"Volkswagen",model:"Jetta",notes:"Sanitized fictional 2013 Volkswagen Jetta TDI sample. Never real vehicle data.",fuelType:"Diesel")
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
    #if DEBUG
    func loadPhase3Fixture() {
        guard state.vehicles.isEmpty else { return }
        perform {
            let vehicle=Vehicle(name:"Fictional Jetta TDI",year:"2013",make:"Volkswagen",model:"Jetta",fuelType:"Diesel")
            let end=Date(),start=end.addingTimeInterval(-2700)
            let samples=(0...18).map { index in
                let fraction=Double(index)/18
                return TelemetrySample(timestamp:start.addingTimeInterval(fraction*2700),latitude:49.16+fraction*0.04,
                    longitude:-123.94-fraction*0.03,signals:["speedKph":84,"rpm":1840,"coolantC":89,"fuelRateLph":4.5])
            }
            let trip=Trip(vehicleID:vehicle.id,name:"Sanitized fixture drive",source:"Synthetic validation fixture",samples:samples,
                          isDemo:false,recordedStartedAt:start,recordedEndedAt:end,recordedDistanceKm:56.8,tripFuelLitres:2.1)
            let fill=FuelEntry(vehicleID:vehicle.id,date:end.addingTimeInterval(-3600),litresPurchased:42,totalCost:68.12,
                               odometerKm:216_274,isFullFill:true,stationName:"Fixture station",isDemo:false)
            try commit { $0.vehicles=[vehicle];$0.selectedVehicleID=vehicle.id;$0.trips=[trip];$0.fuelEntries=[fill] }
        }
    }
    func loadPhase4Fixture() {
        loadPhase3Fixture()
        guard let vehicle=state.vehicles.first,let trip=state.trips.first else { return }
        perform {
            let end=trip.end
            let partial=FuelEntry(vehicleID:vehicle.id,date:end.addingTimeInterval(-1_800),litresPurchased:12,totalCost:21.48,odometerKm:216_500,isFullFill:false,stationName:"Sanitized sample station",isDemo:true)
            let full=FuelEntry(vehicleID:vehicle.id,date:end.addingTimeInterval(600),litresPurchased:24,totalCost:42.96,odometerKm:216_874,isFullFill:true,stationName:"Sanitized sample station",isDemo:true)
            try commit { state in
                for index in state.trips.indices { state.trips[index].isDemo=true }
                for index in state.fuelEntries.indices { state.fuelEntries[index].isDemo=true }
                state.fuelEntries.append(contentsOf:[partial,full])
                state.journeyAnnotations[trip.id.uuidString]=DriveLineJourneyAnnotation(recordingID:trip.id,purpose:.service,reviewed:true,startPlace:"Sample start",finishPlace:"Sample finish")
            }
            selectedTripID=trip.id;page = .drives
        }
    }
    func loadPhase5Fixture() {
        loadPhase3Fixture()
        guard let vehicle=state.vehicles.first,let trip=state.trips.first,let repository else { return }
        perform {
            let bytes=Data("sanitized Phase 5 receipt fixture".utf8)
            let digest=SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
            let metadata=DriveLineReceiptMetadata(fileName:"receipt-fixture.txt",mediaType:"text/plain",byteCount:bytes.count,sha256:digest,capturedAt:Date())
            let partial=FuelEntry(vehicleID:vehicle.id,date:Date().addingTimeInterval(-12*86_400),litresPurchased:12,totalCost:21.48,currencyCode:"CAD",odometerKm:216_500,isFullFill:false,stationName:"Island Fuel",notes:"Sanitized partial fill")
            let full=FuelEntry(vehicleID:vehicle.id,date:Date().addingTimeInterval(-2*86_400),litresPurchased:24,totalCost:42.96,currencyCode:"CAD",odometerKm:216_874,isFullFill:true,stationName:"Harbour Fuel",notes:"Full tank after partial fill",receipt:metadata)
            try repository.storeReceiptFiles([digest:bytes],for:[full])
            try commit { state in
                state.fuelEntries.append(contentsOf:[partial,full])
                state.journeyAnnotations[trip.id.uuidString]=DriveLineJourneyAnnotation(recordingID:trip.id,purpose:.service,reviewed:true,startPlace:"Sample start",finishPlace:"Sample finish")
            }
            selectedTripID=trip.id;page = .fuel
        }
    }
    func loadPhase6Fixture() {
        loadPhase4Fixture()
        guard let vehicle=state.vehicles.first,let primary=state.trips.first else { return }
        perform {
            let base=primary.start.addingTimeInterval(-7_200)
            let primarySamples=(0..<48).compactMap { index -> TelemetrySample? in
                if (20...25).contains(index) { return nil }
                let elapsed=Double(index)*5
                return TelemetrySample(timestamp:base.addingTimeInterval(elapsed),latitude:49.16+Double(index)*0.00018,
                    longitude:-123.94-Double(index)*0.00014,
                    signals:["speedKph":66+Double(index%9)*2,"rpm":1_520+Double(index%12)*38,"coolantC":84+Double(index%5),
                             "fuelRateLph":3.8+Double(index%4)*0.3,"boostAbsoluteKpa":128+Double(index%6),"barometricKpa":101,
                             "dpfRegenTrigger":Double(index%10)*10],command:index == 12 ? "01 0C":nil,reply:index == 12 ? "41 0C 1B 20":nil)
            }
            let comparisonSamples=(0..<15).map { index in
                let elapsed=Double(index)*145
                return TelemetrySample(timestamp:base.addingTimeInterval(elapsed),latitude:49.12+Double(index)*0.0018,
                    longitude:-123.91-Double(index)*0.0012,
                    signals:["speedKph":58+Double(index%5)*7,"rpm":1450+Double(index)*32,"coolantC":82+Double(index%4),
                             "fuelRateLph":3.1+Double(index%3)*0.5,"vendor.syntheticPressure":101.2+Double(index)*0.08])
            }
            let gpsOnlySamples=(0..<10).map { index in
                TelemetrySample(timestamp:base.addingTimeInterval(-4_000+Double(index)*90),latitude:49.07+Double(index)*0.001,
                    longitude:-123.84-Double(index)*0.001,signals:[:])
            }
            var obdOnlySamples:[TelemetrySample]=[]
            for index in 0..<8 {
                let offset=Double(index)
                let signals:[String:Double]=["rpm":1_200+offset*110,"coolantC":76+offset,"dpfRegenTrigger":offset*10]
                obdOnlySamples.append(TelemetrySample(timestamp:base.addingTimeInterval(-7_000+offset*180),signals:signals))
            }
            let comparison=Trip(vehicleID:vehicle.id,name:"Sample comparison drive",source:"Sanitized Phase 6 fixture",
                samples:comparisonSamples,isDemo:true)
            let gpsOnly=Trip(vehicleID:vehicle.id,name:"Sample GPS-only drive",source:"Sanitized Phase 6 fixture",
                samples:gpsOnlySamples,isDemo:true)
            let obdOnly=Trip(vehicleID:vehicle.id,name:"Sample OBD-only drive",source:"Sanitized Phase 6 fixture",
                samples:obdOnlySamples,isDemo:true)
            let empty=Trip(vehicleID:vehicle.id,name:"Sample missing-signal drive",source:"Sanitized Phase 6 fixture",
                samples:[],isDemo:true,recordedStartedAt:base.addingTimeInterval(-9_000),recordedEndedAt:base.addingTimeInterval(-8_400))
            try commit { state in
                for index in state.trips.indices { state.trips[index].isDemo=true }
                for index in state.fuelEntries.indices { state.fuelEntries[index].isDemo=true }
                if let index=state.trips.firstIndex(where:{$0.id == primary.id}) {
                    state.trips[index].samples=primarySamples
                    state.trips[index].recordedStartedAt=base
                    state.trips[index].recordedEndedAt=base.addingTimeInterval(235)
                    state.trips[index].recordedDistanceKm=nil
                    state.trips[index].tripFuelLitres=nil
                }
                state.trips.append(contentsOf:[comparison,gpsOnly,obdOnly,empty])
            }
            changePreferences { $0.signalKeys=["speedKph","rpm","coolantC","fuelRateLph","vendor.syntheticPressure","speedKph"] }
            selectedTripID=primary.id
            page = .signals
        }
    }
    func loadPhase7Fixture() {
        guard state.vehicles.isEmpty else { return }
        perform {
            let jetta=Vehicle(name:"Fictional 2013 Jetta · SAMPLE",year:"2013",make:"Volkswagen",model:"Jetta TDI",notes:"Sanitized debug-only sample; excluded from real totals.",vehicleClass:.passengerCar,fuelType:"Diesel",configuredSources:[.manual,.phoneGPS,.importedArchive])
            let ford=Vehicle(name:"F-150 · SAMPLE",year:"2021",make:"Ford",model:"F-150",notes:"Sanitized debug-only sample; excluded from real totals.",vehicleClass:.lightTruck,fuelType:"Gasoline",configuredSources:[.manual,.phoneGPS,.obdScanner,.importedArchive])
            let honda=Vehicle(name:"CB500X ABS · SAMPLE",year:"2023",make:"Honda",model:"CB500X ABS",notes:"Sanitized debug-only sample; excluded from real totals.",vehicleClass:.motorcycle,fuelType:"Gasoline",configuredSources:[.manual,.phoneGPS])
            let kenworth=Vehicle(name:"T880 · SAMPLE",year:"2025",make:"Kenworth",model:"T880",notes:"Sanitized debug-only sample; excluded from real totals.",vehicleClass:.heavyTruck,fuelType:"Diesel",configuredSources:[.manual,.importedArchive],isArchived:true,archivedAt:Date())
            let start=Date().addingTimeInterval(-3_600)
            let sampleTrip=Trip(vehicleID:jetta.id,name:"Sample Garage history",source:"Sanitized imported historical source",samples:[],isDemo:true,recordedStartedAt:start,recordedEndedAt:start.addingTimeInterval(900))
            try commit { state in state.vehicles=[jetta,ford,honda,kenworth];state.selectedVehicleID=jetta.id;state.trips=[sampleTrip] }
            page = .garage
        }
    }
    #endif
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
            case ("POST","/v1/fuel-entries"):
                guard !readOnly else { return HTTPResponse(503,json:["error":"Library is read-only"]) }
                guard let id=UUID(uuidString:request.query["vehicleID"] ?? ""),state.vehicles.contains(where:{$0.id==id}) else { return HTTPResponse(422,json:["error":"An existing vehicleID is required"]) }
                let parsed=try RecordingImporter.parse(data:request.body,name:"companion-fuel.json",vehicleID:id,receiptID:UUID())
                guard parsed.trips.isEmpty,!parsed.fuelEntries.isEmpty else { return HTTPResponse(422,json:["error":"A fuel update must contain fuel entries only"]) }
                let requestHash=SHA256.hash(data:request.body).map { String(format:"%02x",$0) }.joined()
                if let duplicate=state.receipts.first(where:{$0.vehicleID==id && $0.contentHash==requestHash}) { return HTTPResponse(200,data:try LibraryRepository.encoder().encode(duplicate)) }
                let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
                try request.body.write(to:temp,options:.atomic);defer { try? FileManager.default.removeItem(at:temp) }
                let receipt=try enqueue(temp,vehicleID:id);Task { await processPending() }
                return HTTPResponse(receipt.status == .processed ? 200:202,data:try LibraryRepository.encoder().encode(receipt))
            default:
                if request.method=="GET",request.path.hasPrefix("/v1/receipts/"),let id = UUID(uuidString:String(request.path.dropFirst("/v1/receipts/".count))),let receipt = state.receipts.first(where:{$0.id==id}) { return HTTPResponse(200,data:try LibraryRepository.encoder().encode(receipt)) }
                if request.method=="GET",request.path.hasPrefix("/v1/trips/"),let id = UUID(uuidString:String(request.path.dropFirst("/v1/trips/".count))),let trip = state.trips.first(where:{$0.id==id}) { return HTTPResponse(200,data:try TripExport.json(trip,fuelEntries:state.fuelEntries,receiptFiles:repository?.archivedReceiptFiles(state.fuelEntries) ?? [:])) }
                return HTTPResponse(404,json:["error":"Route not found"])
            }
        } catch { return HTTPResponse(422,json:["error":error.localizedDescription]) }
    }
}
