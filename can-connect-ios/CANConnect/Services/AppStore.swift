import Foundation
import SwiftUI
import Combine

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
    let gps = GPSRecorder()
    private let disk: LocalStore
    private var ticker: AnyCancellable?
    private var gpsChanges: AnyCancellable?
    private var toastTask: Task<Void, Never>?
    private var canWrite = true
    init(disk: LocalStore = LocalStore()) {
        self.disk = disk
        do {
            state = try disk.load() ?? SampleData.state()
            if let draft = state.draft {
                if !state.trips.contains(where: { $0.id == draft.id }) { state.trips.insert(draft.trip(endedAt:draft.updatedAt, recovered:true), at:0) }
                state.draft = nil
            }
            try disk.save(state)
        } catch {
            state = StoredState(); canWrite = false
            self.error = "Could not open saved data. The original file is preserved. \(error.localizedDescription)"
        }
        gps.onReady = { [weak self] in
            guard let self, self.pendingGPS else { return }
            self.pendingGPS = false
            self.state.draft = RecordingDraft(source:.phoneGPS, startedAt:Date(), updatedAt:Date())
            self.save()
        }
        gps.onPoint = { [weak self] point in
            guard let self, self.state.draft?.source == .phoneGPS else { return }
            self.state.draft?.accept(point); self.save()
        }
        gps.onFailure = { [weak self] message in
            guard let self else { return }
            self.pendingGPS = false
            if self.state.draft != nil { self.finishRecording() }
            self.error = message
        }
        gpsChanges = gps.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        ticker = Timer.publish(every:1, on:.main, in:.common).autoconnect().sink { [weak self] date in self?.tick(date) }
    }
    var recording: Bool { state.draft != nil }
    var elapsed: Double { state.draft.map { max(0, now.timeIntervalSince($0.startedAt)) } ?? 0 }
    var timerText: String { let n = Int(elapsed); return n >= 3600 ? String(format:"%d:%02d:%02d",n/3600,(n%3600)/60,n%60) : String(format:"%02d:%02d",n/60,n%60) }
    var speedText: String {
        if source == .demo { return "78" }
        guard let fix = gps.lastFix, now.timeIntervalSince(fix) <= 10 else { return "—" }
        return gps.speedKMH.map { $0.text(0) } ?? "—"
    }
    var sortedTrips: [Trip] { state.trips.sorted { $0.startedAt > $1.startedAt } }
    var latest: Trip? { sortedTrips.first }
    var weekTrips: [Trip] { let interval = Calendar.current.dateInterval(of:.weekOfYear, for:now); return sortedTrips.filter { interval?.contains($0.startedAt) ?? false } }
    var weekKM: Double { weekTrips.reduce(0) { $0 + $1.distanceKM } }
    var weekEconomy: Double? {
        let measured = weekTrips.filter { $0.economy != nil && $0.distanceKM > 0 }
        let distance = measured.reduce(0) { $0 + $1.distanceKM }
        return distance > 0 ? measured.reduce(0) { $0 + $1.distanceKM * ($1.economy ?? 0) } / distance : nil
    }
    func tick(_ date: Date) {
        now = date
        if state.draft?.source == .demo {
            state.draft?.distanceKM = elapsed * 78 / 3600
            state.draft?.updatedAt = date
            if Int(elapsed) % 5 == 0 { save() }
        }
    }
    func startRecording() {
        guard canWrite, !recording, !pendingGPS else { return }
        now = Date()
        if source == .phoneGPS { pendingGPS = true; gps.start() }
        else { state.draft = RecordingDraft(source:.demo, startedAt:now, updatedAt:now); save() }
    }
    func cancelGPS() { pendingGPS = false; gps.stop() }
    func finishRecording() {
        guard var draft = state.draft else { return }
        let endedAt = Date()
        if draft.source == .demo {
            draft.distanceKM = max(0, endedAt.timeIntervalSince(draft.startedAt)) * 78 / 3600
            draft.route = SampleData.route(date:draft.startedAt)
        }
        var next = state
        next.trips.insert(draft.trip(endedAt:endedAt), at:0)
        next.draft = nil
        do {
            try disk.save(next)
            gps.stop(); state = next; notify("Recording saved on this iPhone")
        } catch { self.error = "Could not save the recording. Keep the app open and retry Finish. \(error.localizedDescription)" }
    }
    func signal(_ slot: String) -> Signal { state.preferences.signals[slot] ?? .rpm }
    func setSignal(_ signal: Signal, slot: String) { state.preferences.signals[slot] = signal; save() }
    func save() {
        guard canWrite else { return }
        do { try disk.save(state) }
        catch { self.error = "Could not save on this iPhone: \(error.localizedDescription)" }
    }
    func addFill(litres: Double, cost: Double, odometer: Double, full: Bool, date: Date) throws {
        guard canWrite else { throw AppFailure("Saved data is unavailable. Restart after recovering the original data file.") }
        guard litres.isFinite, litres > 0, litres <= 150, cost.isFinite, cost >= 0, odometer.isFinite, odometer >= 0 else { throw AppFailure("Check litres, cost and odometer.") }
        let realFills = state.fills.filter { !$0.isSample }
        guard !realFills.contains(where: { $0.date < date && $0.odometerKM > odometer || $0.date > date && $0.odometerKM < odometer }) else { throw AppFailure("The odometer must follow the order of your other fills.") }
        var next = state
        next.fills.append(FuelEntry(date:date, litres:litres, costCAD:cost, odometerKM:odometer, full:full))
        try disk.save(next); state = next; notify("Fill-up saved")
    }
    func importTrips(_ data: Data) throws {
        guard canWrite else { throw AppFailure("Saved data is unavailable.") }
        let archive = try TripArchive.decode(data)
        let known = Set(state.trips.map(\.id))
        let additions = archive.trips.filter { !known.contains($0.id) }.map { original -> Trip in
            var trip = original
            if !trip.isSample && trip.source != .phoneGPS { trip.source = .imported }
            return trip
        }
        var next = state; next.trips += additions
        try disk.save(next); state = next
        notify("Imported \(additions.count) recording\(additions.count == 1 ? "" : "s")")
    }
    func addSample() { state.trips.insert(Trip(name:"Sample imported drive", startedAt:Date(), duration:1260, distanceKM:15.2, source:.imported, isSample:true, economy:5.3, fuelLitres:0.81, route:SampleData.route()), at:0); save(); notify("Sample recording added") }
    func removeTrip(_ id: UUID) { state.trips.removeAll { $0.id == id }; save() }
    func removeSamples() { state.trips.removeAll( where: \.isSample); state.fills.removeAll(where: \.isSample); save(); notify("Sample history removed") }
    func notify(_ message: String) {
        toastTask?.cancel(); toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds:3_000_000_000)
            guard !Task.isCancelled else { return }; self?.toast = nil
        }
    }
}
