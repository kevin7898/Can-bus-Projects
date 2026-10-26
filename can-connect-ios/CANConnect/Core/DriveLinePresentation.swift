import Foundation

struct PhoneTodayPresentation: Equatable {
    enum Readiness: Equatable { case ready, needsVehicle, sampleVehicle }

    var date: Date
    var vehicleTitle: String?
    var readiness: Readiness
    var gpsStatus: String
    var scannerStatus: String
    var scannerConnected: Bool
    var scannerConnecting: Bool
    var queuedTransfers: Int
    var todayDriveCount: Int
    var todayDistanceKM: Double
    var todayDuration: TimeInterval
    var todayFuelLitres: Double?
    var todayFuelDriveCount: Int
    var latestTrip: Trip?
    var latestFill: FuelEntry?

    static func make(state: StoredState, now: Date, calendar: Calendar = .current,
                     gpsStatus: String, scannerStatus: String,
                     scannerConnected: Bool, scannerConnecting: Bool) -> Self {
        let vehicle = state.vehicles.first { $0.id == state.selectedVehicleID }
        let realTrips = state.trips.filter { $0.vehicleID == state.selectedVehicleID && !$0.isSample }.sorted { $0.startedAt > $1.startedAt }
        let todayTrips = realTrips.filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
        let measuredFuel = todayTrips.compactMap(\.fuelLitres)
        let latestFill = state.fills.filter { $0.vehicleID == state.selectedVehicleID && !$0.isSample }.max { $0.date < $1.date }
        let queued = state.transfers.filter { $0.status == .queued || $0.status == .awaitingReceipt }.count
        let readiness: Readiness = vehicle == nil ? .needsVehicle : (vehicle?.isSample == true ? .sampleVehicle : .ready)
        return Self(date:now, vehicleTitle:vehicle?.title, readiness:readiness,
                    gpsStatus:gpsStatus, scannerStatus:scannerStatus,
                    scannerConnected:scannerConnected, scannerConnecting:scannerConnecting,
                    queuedTransfers:queued, todayDriveCount:todayTrips.count,
                    todayDistanceKM:todayTrips.reduce(0) { $0 + $1.distanceKM },
                    todayDuration:todayTrips.reduce(0) { $0 + $1.duration },
                    todayFuelLitres:measuredFuel.isEmpty ? nil : measuredFuel.reduce(0,+),
                    todayFuelDriveCount:measuredFuel.count, latestTrip:realTrips.first, latestFill:latestFill)
    }
}

enum PhoneRecordingPhase: String, Equatable, CaseIterable {
    case idle, starting, active, degraded, stopping, recovered
}

struct PhoneSignalPresentation: Equatable, Identifiable {
    var id: String { key }
    var key: String
    var title: String
    var value: Double?
    var unit: String
    var observedAt: Date?
    var state: DriveLineSemanticState
    var source: String
    var statusText:String? = nil
}

struct PhoneRecordingPresentation: Equatable {
    var phase: PhoneRecordingPhase
    var sourceTitle: String
    var statusTitle: String
    var statusMessage: String
    var elapsed: TimeInterval
    var distanceKM: Double
    var speed: PhoneSignalPresentation
    var metrics: [PhoneSignalPresentation]
    var route: [RoutePoint]
    var gpsState: DriveLineSemanticState
    var scannerState: DriveLineSemanticState
    var localState: DriveLineSemanticState
    var queuedTransfers: Int
    var recoveryTitle: String?
    var recoveryMessage: String?

    var queuedStatusTitle:String? {
        queuedTransfers > 0 ? "Upload queued · \(queuedTransfers)" : nil
    }

    static let metricKeys = ["rpm","coolantC","boostGaugeKpa","dsgFluidC","dpfSootG","dpfRegenTrigger"]

    static func make(state: StoredState, selectedSource: TripSource, pendingGPS: Bool,
                     scannerConnected: Bool, scannerConnecting: Bool, scannerStatus: String,
                     gpsStatus: String, gpsSpeedKMH: Double?, gpsLastFix: Date?, now: Date,
                     scannerSupportedKeys:Set<String> = [],scannerUnsupportedKeys:Set<String> = [],
                     isStopping: Bool = false, recovered: Bool = false) -> Self {
        let draft=state.draft
        let elapsed=draft.map { max(0,now.timeIntervalSince($0.startedAt)) } ?? 0
        let observations=latestObservations(draft:draft)
        let gpsStatusLower=gpsStatus.lowercased()
        let gpsFresh=gpsLastFix.map { (0...10).contains(now.timeIntervalSince($0)) } ?? false
        let gpsSessionActive=gpsLastFix != nil && gpsStatusLower.hasPrefix("gps active")
        let gpsMissing=draft != nil && draft?.source != .demo && elapsed>15 && !gpsFresh && !gpsSessionActive
        let gpsAcquiring=gpsStatusLower.contains("waiting") || gpsStatusLower.contains("fix") || gpsStatusLower.contains("weak")
        let scannerMissing=draft?.source == .scanner && !scannerConnected
        let phase:PhoneRecordingPhase
        if recovered { phase = .recovered }
        else if isStopping { phase = .stopping }
        else if pendingGPS || (scannerConnecting && draft == nil) { phase = .starting }
        else if draft != nil { phase = (scannerMissing || gpsMissing) ? .degraded:.active }
        else { phase = .idle }

        let speedObservation:PhoneSignalPresentation
        if let obd=observations["speedKph"],draft?.source == .scanner {
            speedObservation=signal(key:"speedKph",title:"Speed",unit:"km/h",observation:obd,now:now,
                scannerConnected:scannerConnected,supportedKeys:scannerSupportedKeys,unsupportedKeys:scannerUnsupportedKeys)
        } else if gpsFresh,let speed=gpsSpeedKMH {
            speedObservation=PhoneSignalPresentation(key:"speedKph",title:"Speed",value:speed,unit:"km/h",observedAt:gpsLastFix,state:.ready,source:"iPhone GPS")
        } else {
            speedObservation=PhoneSignalPresentation(key:"speedKph",title:"Speed",value:nil,unit:"km/h",observedAt:gpsLastFix,state:gpsLastFix == nil ? .unavailable:.stale,source:"iPhone GPS",statusText:gpsLastFix == nil ? "Not observed":nil)
        }

        var display=observations
        if let boost=DriveLineMetricPolicy.boostGaugeKpa(observations:observations,at:now) { display["boostGaugeKpa"]=boost }
        let definitions:[(String,String,String)]=[
            ("rpm","Engine RPM","rpm"),("coolantC","Coolant","°C"),("boostGaugeKpa","Boost","kPa"),
            ("dsgFluidC","DSG temp","°C"),("dpfSootG","DPF soot","g"),("dpfRegenTrigger","Regen trigger","%")
        ]
        let metrics=definitions.map { key,title,unit -> PhoneSignalPresentation in
            var item=signal(key:key,title:title,unit:unit,observation:display[key],now:now,
                scannerConnected:scannerConnected,supportedKeys:scannerSupportedKeys,unsupportedKeys:scannerUnsupportedKeys)
            if key == "dpfRegenTrigger",let value=item.value { item.value=DriveLineMetricPolicy.normalizedDPFRegenTrigger(value) }
            return item
        }
        let queue=state.transfers.filter { $0.status == .queued || $0.status == .awaitingReceipt }.count
        let recovery:(String?,String?)
        if scannerMissing { recovery=("Scanner disconnected","GPS recording continues locally during the two-minute reconnect window.") }
        else if gpsMissing && draft?.source == .scanner { recovery=(gpsAcquiring ? "GPS acquiring":"GPS unavailable",gpsStatus+". Scanner telemetry continues; route coverage will show the location gap.") }
        else if gpsMissing { recovery=(gpsAcquiring ? "GPS acquiring":"GPS unavailable",gpsStatus+". The recording remains local while DriveLine waits for a fresh location.") }
        else { recovery=(nil,nil) }
        let source=draft?.source ?? selectedSource
        return Self(phase:phase,sourceTitle:source.title,statusTitle:title(phase),
                    statusMessage:message(phase,scannerStatus:scannerStatus,gpsStatus:gpsStatus),elapsed:elapsed,
                    distanceKM:draft?.distanceKM ?? 0,speed:speedObservation,metrics:metrics,route:draft?.route ?? [],
                    gpsState:(gpsFresh || gpsSessionActive) ? .ready:((pendingGPS || gpsAcquiring) ? .waiting:(draft == nil ? .stale:.unavailable)),
                    scannerState:scannerConnected ? .ready:(scannerConnecting ? .processing:.unavailable),
                    localState:draft == nil ? .ready:.active,queuedTransfers:queue,
                    recoveryTitle:recovery.0,recoveryMessage:recovery.1)
    }

    private static func latestObservations(draft:RecordingDraft?)->[String:DriveLineObservation] {
        guard let draft else { return [:] }
        var result:[String:DriveLineObservation]=[:]
        for sample in draft.samples ?? [] {
            for (key,value) in sample.signals where result[key].map({$0.timestamp < sample.timestamp}) ?? true {
                result[key]=DriveLineObservation(key:key,value:value,timestamp:sample.timestamp,sourceID:"obd",recordingID:draft.id)
            }
        }
        return result
    }

    private static func signal(key:String,title:String,unit:String,observation:DriveLineObservation?,now:Date,
                               scannerConnected:Bool,supportedKeys:Set<String>,unsupportedKeys:Set<String>)->PhoneSignalPresentation {
        guard let observation else {
            if !scannerConnected { return PhoneSignalPresentation(key:key,title:title,value:nil,unit:unit,observedAt:nil,state:.offline,source:"OBD",statusText:"Scanner disconnected") }
            if unsupportedKeys.contains(key) { return PhoneSignalPresentation(key:key,title:title,value:nil,unit:unit,observedAt:nil,state:.unavailable,source:"OBD",statusText:"Unsupported") }
            let status=supportedKeys.contains(key) ? "Not observed":"Support unknown"
            return PhoneSignalPresentation(key:key,title:title,value:nil,unit:unit,observedAt:nil,state:.unavailable,source:"OBD",statusText:status)
        }
        let freshness=key == "boostGaugeKpa" ? 10:max(OBDDecoder.freshness(for:key),VWMeasurementDecoder.freshness(for:key))
        let age=now.timeIntervalSince(observation.timestamp)
        return PhoneSignalPresentation(key:key,title:title,value:observation.value,unit:unit,observedAt:observation.timestamp,
                                       state:(0...freshness).contains(age) ? .ready:.stale,source:"OBD")
    }

    private static func title(_ phase:PhoneRecordingPhase)->String {
        switch phase { case .idle:return "Ready to record";case .starting:return "Starting";case .active:return "Recording";case .degraded:return "Recording with limited coverage";case .stopping:return "Saving recording";case .recovered:return "Recording recovered" }
    }
    private static func message(_ phase:PhoneRecordingPhase,scannerStatus:String,gpsStatus:String)->String {
        switch phase {
        case .idle:return "Choose iPhone GPS or a configured scanner."
        case .starting:return gpsStatus
        case .active:return "Saved locally as observations arrive."
        case .degraded:return "Available sources continue recording locally."
        case .stopping:return "Preserving the original recording."
        case .recovered:return "The interrupted draft was restored once and saved locally."
        }
    }
}
