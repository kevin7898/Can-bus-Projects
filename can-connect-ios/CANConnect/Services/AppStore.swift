import Foundation
import SwiftUI
import Combine
import UIKit
import ExternalAccessory

@MainActor
final class AppStore: ObservableObject {
    @Published var state: StoredState
    @Published var source: TripSource = .demo
    @Published var selectedTab: AppTab = .overview
    @Published var overviewPage = 0
    @Published var livePage = 0
    @Published var vehiclePage = 0
    @Published var connectPage = 0
    @Published var tripFilter = 0
    @Published var tripPage = 0
    @Published var now = Date()
    @Published var error: String?
    @Published var toast: String?
    @Published var pendingGPS = false
    @Published var vehicleSetupPresented = false
    @Published var garagePresented = false
    let gps: any GPSRecording
    let scanner: ScannerRecorder
    @Published var serverStatus = "Not connected"
    @Published var transferring = false
    private var scannerChanges: AnyCancellable?
    private var backgroundChanges: AnyCancellable?
    private var lifecycleChanges: [AnyCancellable] = []
    private let scannerAvailable: @MainActor (ScannerSettings) -> Bool
    private var automaticConnectionSuppressed = false
    private var automaticRecordingSuppressed = false
    private var accessoryWasAvailable = false
    private var reconnectFailures = 0
    private var nextReconnect = Date.distantPast
    private var lastCheckpoint = Date.distantPast
    private var scannerBoundary = ScannerTripBoundary()
    private var scannerGapDeadline: Date? {
        get { state.draft?.scannerReconnectDeadline }
        set { state.draft?.scannerReconnectDeadline = newValue }
    }
    private var pendingRecordingEnd: Date?
    private var awaitingEngineRestart = false
    private var recordingSaveFailed = false
    private let activity: RecordingActivityManaging
    private let disk: LocalStore
    private var ticker: AnyCancellable?
    private var gpsChanges: AnyCancellable?
    private var toastTask: Task<Void, Never>?
    private var canWrite = true
    init(disk: LocalStore = LocalStore(), scanner: ScannerRecorder? = nil,
         activity: RecordingActivityManaging? = nil, gps: (any GPSRecording)? = nil,
         scannerAvailable: @escaping @MainActor (ScannerSettings) -> Bool = { (try? MXPlusAccessory.select(serial:$0.accessorySerial)) != nil }) {
        self.activity = activity ?? RecordingLiveActivity()
        self.gps = gps ?? GPSRecorder()
        self.disk = disk
        self.scannerAvailable = scannerAvailable
        self.scanner = scanner ?? ScannerRecorder()
        do {
            state = try disk.load() ?? SampleData.state()
            if state.regenTrackingStartedAt == nil { state.regenTrackingStartedAt = Date() }
            if var draft = state.draft {
                let end = draft.scannerReconnectDeadline == nil ? draft.updatedAt : (draft.samples?.last?.timestamp ?? draft.startedAt)
                draft.route.removeAll { $0.timestamp > end }
                if !state.trips.contains(where: { $0.id == draft.id }) { state.trips.insert(draft.trip(endedAt:end, recovered:true), at:0) }
                state.draft = nil
            }
            try disk.save(state)
        } catch {
            state = StoredState(); canWrite = false
            self.error = "Could not open saved data. The original file is preserved. \(error.localizedDescription)"
        }
        updateLiveActivity()
        source = activeVehicle?.isSample == true ? .demo : .phoneGPS
        self.scanner.onConnected = { [weak self] in
            guard let self else { return }
            if !self.awaitingEngineRestart { self.automaticRecordingSuppressed = false }
            self.scannerBoundary.reset()
            self.reconnectFailures = 0; self.nextReconnect = .distantPast
        }
        self.scanner.onSample = { [weak self] sample in
            guard let self, sample.isValid else { return }
            self.expireScannerGap(at:sample.timestamp)
            if self.awaitingEngineRestart, ScannerTripBoundary.engineRunning(sample) {
                self.awaitingEngineRestart = false
                self.automaticRecordingSuppressed = false
            }
            // Start only after identity validation and a decoded response. A paired
            // adapter with the ignition off must not create empty recordings.
            if !self.recording, !self.pendingGPS, !self.automaticRecordingSuppressed,
               self.canWrite, self.scanner.connected, self.activeVehicle?.isSample == false,
               self.scanner.vehicleID == self.state.selectedVehicleID, ScannerTripBoundary.engineRunning(sample) {
                self.source = .scanner
                self.state.draft = RecordingDraft(vehicleID:self.state.selectedVehicleID, source:.scanner,
                    startedAt:sample.timestamp, updatedAt:sample.timestamp,
                    scannerTransport:(self.activeVehicle?.scannerConnection ?? self.state.scanner).kind)
                self.lastCheckpoint = .distantPast
                self.scannerGapDeadline = nil; self.scannerBoundary.reset()
                self.gps.start()
            }
            guard self.state.draft?.source == .scanner,
                  self.state.draft?.vehicleID == self.scanner.vehicleID,
                  !self.recordingSaveFailed else { return }
            self.scannerGapDeadline = nil
            self.state.draft?.accept(sample)
            if self.scannerBoundary.engineOff(after:sample) {
                self.finishRecording(endedAt:sample.timestamp)
                self.awaitingEngineRestart = true
                return
            }
            self.checkpoint(at:Date())
            if (self.state.draft?.samples?.count ?? 0) >= 100_000 {
                self.finishRecording()
                if self.recording { self.disconnectScanner(); self.error = "Recording reached the 100,000-response limit. Free storage and retry Finish to save the draft." }
                else { self.error = "Recording saved at the 100,000-response limit. Start a new recording to continue." }
            }
        }
        self.scanner.onDisconnect = { [weak self] message in
            guard let self else { return }
            self.scannerBoundary.reset()
            if self.state.draft?.source == .scanner {
                // Keep GPS and the draft alive through a temporary transport loss.
                // Repeated failed opens must not extend the same grace period.
                if self.scannerGapDeadline == nil {
                    let last = self.state.draft?.samples?.last?.timestamp ?? Date()
                    self.scannerGapDeadline = last.addingTimeInterval(ScannerTripBoundary.reconnectGrace)
                }
                self.checkpoint(at:Date(),force:true)
            }
            if self.scanner.failureRequiresAttention { self.error = message }
            self.reconnectFailures = min(self.reconnectFailures + 1, 6)
            self.nextReconnect = Date().addingTimeInterval(min(60, pow(2, Double(self.reconnectFailures))))
        }
        scannerChanges = self.scanner.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        backgroundChanges = NotificationCenter.default.publisher(for:UIApplication.didEnterBackgroundNotification).sink { [weak self] _ in
            // ExternalAccessory owns background execution for the MX+. Closing
            // its streams here used to terminate every trip on an app switch.
            self?.checkpoint(at:Date(), force:true)
            UIApplication.shared.isIdleTimerDisabled = false
        }
        EAAccessoryManager.shared().registerForLocalNotifications()
        for name in [UIApplication.didBecomeActiveNotification, .EAAccessoryDidConnect, .EAAccessoryDidDisconnect] {
            lifecycleChanges.append(NotificationCenter.default.publisher(for:name).sink { [weak self] _ in
                self?.reconcileScannerConnection(at:Date())
                self?.updateLiveActivity()
            })
        }
        self.gps.onReady = { [weak self] in
            guard let self, self.pendingGPS else { return }
            self.pendingGPS = false
            self.state.draft = RecordingDraft(vehicleID:self.state.selectedVehicleID, source:.phoneGPS, startedAt:Date(), updatedAt:Date())
            self.save()
        }
        self.gps.onPoint = { [weak self] point in
            guard let self else { return }
            self.expireScannerGap(at:Date())
            guard let source = self.state.draft?.source, source != .demo, !self.recordingSaveFailed else { return }
            self.state.draft?.accept(point)
            self.checkpoint(at:Date())
        }
        self.gps.onFailure = { [weak self] message in
            guard let self else { return }
            self.pendingGPS = false
            // Location is optional for scanner telemetry. Losing GPS must never
            // finish the MX+ session or discard its measurements.
            if self.state.draft?.source == .scanner {
                self.notify("Scanner recording continues without GPS. " + message)
            } else {
                if self.state.draft != nil { self.finishRecording() }
                else { self.gps.stop() } // A failed GPS-only warm-up must not restart later.
                self.error = message
            }
        }
        gpsChanges = self.gps.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        Task { [weak self] in self?.reconcileScannerConnection(at:Date()) }
        ticker = Timer.publish(every:1, on:.main, in:.common).autoconnect().sink { [weak self] date in self?.tick(date) }
    }
    var recording: Bool { state.draft != nil }
    var elapsed: Double { state.draft.map { max(0, now.timeIntervalSince($0.startedAt)) } ?? 0 }
    var timerText: String { let n = Int(elapsed); return n >= 3600 ? String(format:"%d:%02d:%02d",n/3600,(n%3600)/60,n%60) : String(format:"%02d:%02d",n/60,n%60) }
    var speedText: String {
        if source == .demo { return "78" }
        if source == .scanner { return scanner.value("speedKph",at:Date())?.text(0) ?? "—" }
        guard let fix = gps.lastFix, now.timeIntervalSince(fix) <= 10 else { return "—" }
        return gps.speedKMH.map { $0.text(0) } ?? "—"
    }
    var activeVehicle: VehicleProfile? { state.vehicles.first { $0.id == state.selectedVehicleID } }
    var vehicleFills: [FuelEntry] { state.fills.filter { $0.vehicleID == state.selectedVehicleID } }
    var dashboard: Preferences {
        get { activeVehicle?.dashboard ?? state.preferences }
        set { if let i = state.vehicles.firstIndex(where:{$0.id == state.selectedVehicleID}) { state.vehicles[i].dashboard = newValue } else { state.preferences = newValue } }
    }
    var sortedTrips: [Trip] { state.trips.filter { $0.vehicleID == state.selectedVehicleID }.sorted { $0.startedAt > $1.startedAt } }
    var latest: Trip? { sortedTrips.first }
    var weekTrips: [Trip] { let interval = Calendar.current.dateInterval(of:.weekOfYear, for:now); return sortedTrips.filter { interval?.contains($0.startedAt) ?? false } }
    var weekKM: Double { weekTrips.reduce(0) { $0 + $1.distanceKM } }
    var weekEconomy: Double? {
        let measured = weekTrips.filter { $0.economy != nil && $0.distanceKM > 0 }
        let distance = measured.reduce(0) { $0 + $1.distanceKM }
        return distance > 0 ? measured.reduce(0) { $0 + $1.distanceKM * ($1.economy ?? 0) } / distance : nil
    }
    func tick(_ date: Date) {
        expireScannerGap(at:date)
        // Keep setup forms and native menus stable while idle. Live freshness and
        // recording timers still update every second; history refreshes each minute.
        if recording || pendingGPS || selectedTab == .live || abs(date.timeIntervalSince(now)) >= 60 { now = date }
        if state.draft?.source == .demo {
            state.draft?.distanceKM = elapsed * 78 / 3600
            state.draft?.updatedAt = date
        }
        checkpoint(at:date)
        reconcileScannerConnection(at:date)
    }
    private func checkpoint(at date: Date, force: Bool = false) {
        guard recording, force || date.timeIntervalSince(lastCheckpoint) >= 5 else { return }
        save(); lastCheckpoint = date
        updateLiveActivity()
    }
    private func updateLiveActivity() {
        activity.sync(state.draft.map { RecordingActivitySnapshot(draft:$0,scannerConnected:scanner.connected) },
                      foreground:UIApplication.shared.applicationState == .active)
    }
    // No background keep-alive trick: retries run while iOS schedules the app or
    // delivers accessory events. Force-quitting the app cannot be overridden.
    func reconcileScannerConnection(at date: Date) {
        expireScannerGap(at:date)
        guard !recordingSaveFailed, canWrite, let vehicle = activeVehicle, !vehicle.isSample,
              let settings = vehicle.scannerConnection, settings.kind == .obdLinkMXPlus,
              settings.accessorySerial?.isEmpty == false else { return }
        let available = scannerAvailable(settings)
        if accessoryWasAvailable && !available {
            automaticConnectionSuppressed = false
            nextReconnect = .distantPast; reconnectFailures = 0
        }
        accessoryWasAvailable = available
        guard available, !automaticConnectionSuppressed, !scanner.connected, !scanner.connecting,
              (!recording || (state.draft?.source == .scanner && state.draft?.vehicleID == vehicle.id && scannerGapDeadline != nil)),
              !pendingGPS, date >= nextReconnect else { return }
        source = .scanner
        scanner.connect(settings:settings,vehicle:vehicle)
    }
    private func expireScannerGap(at date: Date) {
        guard let deadline = scannerGapDeadline, date >= deadline,
              state.draft?.source == .scanner, !recordingSaveFailed else { return }
        // Until the ECU returns, route points are provisional. An expired gap
        // must not append a walk or a ride in another vehicle to this trip.
        let end = state.draft?.samples?.last?.timestamp ?? state.draft!.startedAt
        finishRecording(endedAt:end)
        if !recording { awaitingEngineRestart = true }
    }
    func disconnectScanner() {
        if state.draft?.source == .scanner { finishRecording() }
        awaitingEngineRestart = false
        automaticConnectionSuppressed = true
        automaticRecordingSuppressed = true
        scanner.disconnect()
    }
    private func resetScannerAutomation() {
        scannerGapDeadline = nil; scannerBoundary.reset(); awaitingEngineRestart = false
        scanner.disconnect()
        automaticConnectionSuppressed = false; automaticRecordingSuppressed = false
        accessoryWasAvailable = false; reconnectFailures = 0; nextReconnect = .distantPast
    }
    func startRecording() {
        guard canWrite, !recording, !pendingGPS else { return }
        guard activeVehicle != nil else { vehicleSetupPresented = true; return }
        now = Date()
        if source == .phoneGPS { pendingGPS = true; gps.start() }
        else if source == .scanner {
            guard scanner.connected, scanner.vehicleID == state.selectedVehicleID else { error = "Connect the scanner to the selected vehicle first."; return }
            state.draft = RecordingDraft(vehicleID:state.selectedVehicleID, source:.scanner, startedAt:now, updatedAt:now, scannerTransport:(activeVehicle?.scannerConnection ?? state.scanner).kind)
            UIApplication.shared.isIdleTimerDisabled = true
            save()
            gps.start()
        }
        else { state.draft = RecordingDraft(vehicleID:state.selectedVehicleID, source:.demo, startedAt:now, updatedAt:now); save() }
    }
    func cancelGPS() { pendingGPS = false; gps.stop() }
    func finishRecording(endedAt requestedEnd: Date? = nil) {
        guard var draft = state.draft else { return }
        if draft.source == .scanner { automaticRecordingSuppressed = true }
        let endedAt = pendingRecordingEnd ?? requestedEnd ?? Date()
        pendingRecordingEnd = endedAt
        // An explicit ECU boundary may precede the latest GPS callback.
        if requestedEnd != nil || recordingSaveFailed {
            draft.route.removeAll { $0.timestamp > endedAt }
            draft.samples?.removeAll { $0.timestamp > endedAt }
            draft.updatedAt = endedAt
        }
        if draft.source == .demo {
            draft.distanceKM = max(0, endedAt.timeIntervalSince(draft.startedAt)) * 78 / 3600
            draft.route = SampleData.route(date:draft.startedAt)
        }
        var next = state
        next.trips.insert(draft.trip(endedAt:endedAt), at:0)
        next.draft = nil
        do {
            try disk.save(next)
            gps.stop(); scannerGapDeadline = nil; scannerBoundary.reset(); recordingSaveFailed = false; pendingRecordingEnd = nil
            UIApplication.shared.isIdleTimerDisabled = false; state = next; updateLiveActivity(); notify("Recording saved on this iPhone")
        } catch { recordingSaveFailed = true; gps.stop(); scanner.disconnect(); self.error = "Could not save the recording. Keep the app open and retry Finish. \(error.localizedDescription)" }
    }
    func signal(_ slot: String) -> Signal { dashboard.signals[slot] ?? .rpm }
    func setSignal(_ signal: Signal, slot: String) { dashboard.signals[slot] = signal; save() }
    func save() {
        guard canWrite else { return }
        do { try disk.save(state); updateLiveActivity() }
        catch { self.error = "Could not save on this iPhone: \(error.localizedDescription)" }
    }
    func addFill(litres: Double, cost: Double, odometer: Double, full: Bool, date: Date) throws {
        guard canWrite else { throw AppFailure("Saved data is unavailable. Restart after recovering the original data file.") }
        guard litres.isFinite, litres > 0, litres <= 150, cost.isFinite, cost >= 0, odometer.isFinite, odometer >= 0 else { throw AppFailure("Check litres, cost and odometer.") }
        let realFills = vehicleFills.filter { !$0.isSample }
        guard !realFills.contains(where: { $0.date < date && $0.odometerKM > odometer || $0.date > date && $0.odometerKM < odometer }) else { throw AppFailure("The odometer must follow the order of your other fills.") }
        var next = state
        next.fills.append(FuelEntry(vehicleID:state.selectedVehicleID, date:date, litres:litres, costCAD:cost, odometerKM:odometer, full:full))
        try disk.save(next); state = next; notify("Fill-up saved")
    }
    func archive(_ trips: [Trip]) -> TripArchive {
        let ids = Set(trips.compactMap(\.vehicleID))
        return TripArchive(vehicles:state.vehicles.filter {ids.contains($0.id)},trips:trips)
    }
    func importTrips(_ data: Data) throws {
        guard canWrite else { throw AppFailure("Saved data is unavailable.") }
        guard !recording, !pendingGPS else { throw AppFailure("Finish recording before importing vehicle history.") }
        guard activeVehicle != nil else { throw AppFailure("Choose a vehicle before importing recordings.") }
        let archive = try TripArchive.decode(data)
        var next = state; var mapping: [UUID:UUID] = [:]
        for foreign in archive.vehicles ?? [] {
            let incoming = try foreign.validated(requireIdentity:false)
            if let match = next.vehicles.first(where: { $0.id == incoming.id || (incoming.vin != nil && $0.vin == incoming.vin) }) { mapping[incoming.id] = match.id }
            else { next.vehicles.append(incoming); mapping[incoming.id] = incoming.id }
        }
        let known = Set(next.trips.map(\.id))
        var additions: [Trip] = []
        for original in archive.trips where !known.contains(original.id) {
            var trip = original
            if let vehicleID = trip.vehicleID {
                guard let localID = mapping[vehicleID] ?? next.vehicles.first(where:{$0.id == vehicleID})?.id else { throw AppFailure("This archive has no profile for its vehicle. Export it again with the current app, or import an older archive without a vehicle ID into the selected profile.") }
                trip.vehicleID = localID
            } else { trip.vehicleID = next.selectedVehicleID }
            if !trip.isSample && trip.source != .phoneGPS && trip.source != .scanner { trip.source = .imported }
            additions.append(trip)
        }
        next.trips += additions
        let importedIDs = Set(additions.compactMap(\.vehicleID))
        if importedIDs.count == 1 { next.selectedVehicleID = importedIDs.first }
        try disk.save(next); state = next; tripPage = 0
        notify("Imported \(additions.count) recording\(additions.count == 1 ? "" : "s")")
    }
    func addSample() { state.trips.insert(Trip(vehicleID:state.selectedVehicleID, name:"Sample imported drive", startedAt:Date(), duration:1260, distanceKM:15.2, source:.imported, isSample:true, economy:5.3, fuelLitres:0.81, route:SampleData.route()), at:0); save(); notify("Sample recording added") }
    func removeTrip(_ id: UUID) {
        guard canWrite else { error = "Saved data is unavailable."; return }
        guard !state.transfers.contains(where:{$0.tripID == id && $0.status != .complete}) else { error = "Complete this recording's queued transfer before deleting it."; return }
        var next = state; next.trips.removeAll { $0.id == id }
        do { try disk.save(next); state = next } catch { self.error = error.localizedDescription }
    }
    func removeSamples() { state.trips.removeAll( where: \.isSample); state.fills.removeAll(where: \.isSample); save(); notify("Sample history removed") }
    func chooseVehicle(_ id: UUID) throws {
        guard canWrite else { throw AppFailure("Saved data is unavailable.") }
        guard !recording && !pendingGPS else { throw AppFailure("Finish the current recording before switching vehicles.") }
        guard state.vehicles.contains(where:{$0.id == id}) else { throw AppFailure("Vehicle not found.") }
        var next = state; next.selectedVehicleID = id; next.onboardingCompleted = true
        try disk.save(next); state = next; tripPage = 0
        resetScannerAutomation(); source = activeVehicle?.isSample == true ? .demo : .phoneGPS
    }
    func saveVehicle(_ vehicle: VehicleProfile) throws {
        guard canWrite, !recording, !pendingGPS else { throw AppFailure("Finish recording before setting up a vehicle.") }
        let value = try vehicle.validated()
        if let vin = value.vin, state.vehicles.contains(where:{$0.id != value.id && $0.vin == vin}) { throw AppFailure("This VIN is already in your garage. Choose that vehicle instead.") }
        if let old = state.vehicles.first(where:{$0.id == value.id}), let oldVIN = old.vin, let newVIN = value.vin, oldVIN != newVIN,
           state.trips.contains(where:{$0.vehicleID == old.id}) || state.fills.contains(where:{$0.vehicleID == old.id}) { throw AppFailure("This VIN belongs to a different vehicle. Add it as a new vehicle to keep the existing history separate.") }
        var next = state
        if let i = next.vehicles.firstIndex(where:{$0.id == value.id}) { next.vehicles[i] = value } else { next.vehicles.append(value) }
        next.selectedVehicleID = value.id; next.onboardingCompleted = true
        if let connection = value.scannerConnection { next.scanner = connection }
        try disk.save(next); state = next; tripPage = 0; vehicleSetupPresented = false
        resetScannerAutomation(); source = .phoneGPS
        notify("Vehicle ready: \(value.title)")
    }
    func useSampleVehicle() throws {
        guard canWrite, !recording, !pendingGPS else { throw AppFailure("Finish recording before switching vehicles.") }
        var next = state
        if let existing = next.vehicles.first(where:\.isSample) { next.selectedVehicleID = existing.id }
        else { let sample = VehicleProfile.sample; next.vehicles.append(sample); next.selectedVehicleID = sample.id }
        next.onboardingCompleted = true
        try disk.save(next); state = next; vehicleSetupPresented = false
        resetScannerAutomation(); source = .demo
    }
    func reading(_ key: String) -> Double? { source == .scanner ? scanner.value(key,at:Date()) : nil }
    // User-facing fullness is the ECU's normalized regeneration trigger, not a
    // guessed grams-to-capacity conversion. Retain the actual value, no UI clamp.
    var sootFullnessText: String { reading("dpfRegenTrigger")?.text(0) ?? "—" }
    func signalText(_ signal: Signal) -> String {
        if source == .demo { return signal.sample }
        switch signal {
        case .rpm: return reading("rpm")?.text(0) ?? "—"
        case .coolant: return reading("coolantC")?.text(0) ?? "—"
        case .outside: return reading("outsideC")?.text(0) ?? "—"
        case .voltage: return reading("voltage")?.text(1) ?? "—"
        case .boost:
            guard let map = reading("boostAbsoluteKpa") ?? reading("mapKpa"), let baro = reading("barometricKpa") else { return "—" }
            return ((map-baro)/100).text(2)
        case .fuel:
            guard let rate = reading("fuelRateLph"), let speed = reading("speedKph"), speed > 5 else { return "—" }
            return (rate*100/speed).text(1)
        case .economy: return "—"
        case .regenActive:
            return reading("dpfRegenActive").map { $0 == 1 ? "Active" : "Inactive" } ?? "—"
        case .regenType:
            return reading("dpfRegenType").map { $0 == 1 ? "Active" : "Passive" } ?? "—"
        default: return signal.readingKey.flatMap { reading($0) }?.text(1) ?? "—"
        }
    }
    var scannerTitle: String { (activeVehicle?.scannerConnection ?? state.scanner).kind.shortTitle }
    func connectScanner(host: String, port: UInt16) throws {
        try connectScanner(settings:ScannerSettings(host:host.trimmingCharacters(in:.whitespacesAndNewlines),port:port))
    }
    func connectScanner(settings: ScannerSettings) throws {
        guard canWrite, !recording, !pendingGPS else { throw AppFailure("Finish recording before changing scanner connections.") }
        guard let vehicle = activeVehicle, !vehicle.isSample else { throw AppFailure("Choose or add your real vehicle before connecting a scanner.") }
        if settings.kind == .wifi {
            guard ELMWiFiSession.isLocalHost(settings.host), settings.port > 0 else { throw AppFailure("Enter a private scanner address and valid TCP port.") }
        }
        var next = state; next.scanner = settings
        if let i = next.vehicles.firstIndex(where:{$0.id == vehicle.id}) { next.vehicles[i].scannerConnection = settings }
        try disk.save(next); state = next
        automaticConnectionSuppressed = false; automaticRecordingSuppressed = false
        reconnectFailures = 0; nextReconnect = .distantPast
        source = .scanner; scanner.connect(settings:settings,vehicle:vehicle)
    }
    func configureServer(address: String, token: String) async throws {
        guard canWrite, !transferring else { throw AppFailure("Wait for the current transfer to finish.") }
        let endpoint = try MacServerClient.endpoint(address).absoluteString
        let secret = token.trimmingCharacters(in:.whitespacesAndNewlines)
        let credential = try secret.isEmpty ? PairingSecrets.read(endpoint:endpoint) : secret
        let client = try MacServerClient(address:endpoint,token:credential)
        let status = try await client.health()
        try PairingSecrets.save(credential,endpoint:endpoint)
        var next = state; next.server.address = endpoint; try disk.save(next); state = next
        serverStatus = status
    }
    @discardableResult func queueRecordings() throws -> Int {
        guard canWrite else { throw AppFailure("Saved data is unavailable.") }
        let endpoint = try MacServerClient.endpoint(state.server.address).absoluteString
        var next = state; var count = 0
        for trip in state.trips where !trip.isSample && !state.transfers.contains(where:{$0.tripID == trip.id && $0.endpoint == endpoint}) {
            guard let vehicle = state.vehicles.first(where:{$0.id == trip.vehicleID}), !vehicle.isSample,
                  !trip.route.isEmpty || trip.samples?.isEmpty == false else { continue }
            let payload = try MacRecording.encode(trip)
            next.transfers.append(TransferItem(tripID:trip.id,name:trip.name,endpoint:endpoint,vehicle:vehicle,payload:payload)); count += 1
        }
        try disk.save(next); state = next
        return count
    }
    private func updateTransfer(_ item: TransferItem) throws {
        guard canWrite, let i = state.transfers.firstIndex(where:{$0.id == item.id}) else { throw AppFailure("Transfer queue is unavailable.") }
        var next = state; next.transfers[i] = item; try disk.save(next); state = next
    }
    func sendQueued() async {
        guard !transferring, canWrite else { return }
        transferring = true; defer { transferring = false }
        for original in state.transfers where original.status != .complete {
            var item = original
            do {
                let token = try PairingSecrets.read(endpoint:item.endpoint)
                let client = try MacServerClient(address:item.endpoint,token:token,cellular:!state.preferences.wifiLogs && state.preferences.cellularSummaries)
                serverStatus = try await client.health()
                if item.remoteVehicleID == nil { item.remoteVehicleID = try await client.resolve(item.vehicle); try updateTransfer(item) }
                var receipt = try await client.receipt(for:item)
                item.receiptID = receipt.id
                if receipt.status == "queued" || receipt.status == "processing" {
                    item.status = .awaitingReceipt
                    item.message = "Mac stored original · checking processing receipt"
                    try updateTransfer(item)
                    receipt = try await client.waitForProcessing(receipt,item:item)
                }
                if receipt.status == "processed" {
                    item.status = .complete; item.message = "Mac processed recording · original kept on iPhone"
                } else if receipt.status == "failed" {
                    item.status = .failed; item.message = "Mac could not process the preserved original. Retry the import on the Mac, then check receipt."
                } else {
                    item.status = .awaitingReceipt; item.message = "Mac stored original · awaiting processing. Check again."
                }
                try updateTransfer(item)
            } catch {
                item.status = .failed; item.message = error.localizedDescription
                do { try updateTransfer(item) } catch { self.error = "Could not save transfer status. Original and queue preserved for retry."; break }
                serverStatus = "Transfer needs attention"
            }
        }
    }
    func notify(_ message: String) {
        toastTask?.cancel(); toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds:3_000_000_000)
            guard !Task.isCancelled else { return }; self?.toast = nil
        }
    }
}
