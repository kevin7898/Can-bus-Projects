import Foundation
import DriveLineShared

// v1.0: approved CAN / CONNECT design, native iOS implementation.
enum TripSource: String, Codable, CaseIterable { case demo, phoneGPS, scanner, imported
    var title: String { switch self { case .demo: return "Sample CAN feed"; case .phoneGPS: return "iPhone GPS"; case .scanner: return "OBD scanner"; case .imported: return "Imported recording" } }
}
enum Signal: String, Codable, CaseIterable, Identifiable {
    case rpm, coolant, boost, fuel, economy, outside, voltage
    case fuelRate, boostAbsolute, boostCommanded, intake, oil, load, airflow, fuelLevel
    case egt1, egt2, egt3, egt4, dpfPressure, dpfInlet, dpfOutlet, regenActive, regenType, regenTrigger, regenMinutes, regenKM
    case ashVolume, sootMass, dsgTemperature
    var readingKey: String? {
        switch self {
        case .fuelRate: return "fuelRateLph"
        case .boostAbsolute: return "boostAbsoluteKpa"
        case .boostCommanded: return "boostCommandedKpa"
        case .intake: return "intakeC"
        case .oil: return "oilC"
        case .load: return "engineLoad"
        case .airflow: return "mafGps"
        case .fuelLevel: return "fuelPercent"
        case .egt1: return "egt1C"
        case .egt2: return "egt2C"
        case .egt3: return "egt3C"
        case .egt4: return "egt4C"
        case .dpfPressure: return "dpfDifferentialKpa"
        case .dpfInlet: return "dpfInletKpa"
        case .dpfOutlet: return "dpfOutletKpa"
        case .regenActive: return "dpfRegenActive"
        case .regenType: return "dpfRegenType"
        case .regenTrigger: return "dpfRegenTrigger"
        case .regenMinutes: return "dpfAverageRegenMinutes"
        case .regenKM: return "dpfAverageRegenKM"
        case .ashVolume: return "dpfAshML"
        case .sootMass: return "dpfSootG"
        case .dsgTemperature: return "dsgFluidC"
        default: return nil
        }
    }
    var id: String { rawValue }
    var title: String { switch self { case .rpm: return "Engine speed"; case .coolant: return "Coolant"; case .boost: return "Boost"; case .fuel: return "Fuel use"; case .economy: return "Average fuel"; case .outside: return "Outside temp"; case .voltage: return "System voltage"; default: return OBDDecoder.labels[readingKey ?? ""]?.title ?? "Signal" } }
    var unit: String { switch self { case .rpm: return "rpm"; case .coolant, .outside: return "°C"; case .boost: return "bar"; case .fuel, .economy: return "L/100 km"; case .voltage: return "V"; default: return OBDDecoder.labels[readingKey ?? ""]?.unit ?? "" } }
    var sample: String { switch self { case .rpm: return "1840"; case .coolant: return "89"; case .boost: return "0.42"; case .fuel: return "4.8"; case .economy: return "5.4"; case .outside: return "12"; case .voltage: return "13.9"; default: return "—" } }
}
struct RoutePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var accuracy: Double
    var speed: Double? // metres per second; nil when unavailable
    // Render only consecutive observed segments, never a straight line over
    // missing coverage. Match the distance integration's 30-second boundary.
    static func segments(_ points: [RoutePoint]) -> [[RoutePoint]] {
        DriveLineMetricPolicy.routeSegments(points.map(\.shared)).map { segment in
            segment.map { RoutePoint(latitude:$0.latitude,longitude:$0.longitude,timestamp:$0.timestamp,
                                     accuracy:$0.horizontalAccuracyM ?? 0,speed:$0.speedMps) }
        }
    }
    func distance(to other: RoutePoint) -> Double {
        let p1 = latitude * .pi / 180, p2 = other.latitude * .pi / 180
        let dp = (other.latitude - latitude) * .pi / 180
        let dl = (other.longitude - longitude) * .pi / 180
        let a = pow(sin(dp / 2), 2) + cos(p1) * cos(p2) * pow(sin(dl / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
    var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 && accuracy.isFinite && accuracy >= 0 && (speed == nil || (speed!.isFinite && speed! >= 0)) }
    var shared: DriveLineGPSPoint { DriveLineGPSPoint(timestamp:timestamp,latitude:latitude,longitude:longitude,horizontalAccuracyM:accuracy,speedMps:speed,sourceID:"gps") }
}
struct Trip: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var vehicleID: UUID?
    var name: String
    var startedAt: Date
    var duration: Double
    var distanceKM: Double
    var source: TripSource
    var isSample: Bool
    var economy: Double?
    var fuelLitres: Double?
    var route: [RoutePoint] = []
    var samples: [OBDSample]? = nil
    var scannerTransport: ScannerConnectionKind? = nil
    var durationText: String { "\(max(0, Int(duration / 60))) min" }
}
extension Trip {
    var sharedRecording: DriveLineRecording {
        let readings = (samples ?? []).map { DriveLineSignalSample(timestamp:$0.timestamp,values:$0.signals,sourceID:"obd") }
        return DriveLineRecording(recordingID:id,vehicleID:vehicleID ?? UUID(uuidString:"00000000-0000-0000-0000-000000000000")!,name:name,startedAt:startedAt,
                                  endedAt:startedAt.addingTimeInterval(duration),
                                  sourceIDs:Array(Set((route.isEmpty ? [] : ["gps"])+(readings.isEmpty ? [] : ["obd"]))).sorted(),
                                  gpsPoints:route.map(\.shared),signalSamples:readings,tripFuelLitres:fuelLitres,isSample:isSample)
    }
}
struct FuelEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var vehicleID: UUID?
    var date: Date
    var litres: Double
    var costCAD: Double
    var odometerKM: Double
    var full: Bool
    var isSample: Bool = false
}
struct Preferences: Codable, Equatable {
    var signals: [String: Signal] = ["drive.0": .coolant, "drive.1": .boost, "engine.0": .rpm, "engine.1": .coolant, "engine.2": .boost, "engine.3": .fuel, "economy.0": .fuel, "economy.1": .economy, "economy.2": .outside, "economy.3": .voltage]
    var summaryOrder: [String] = ["week", "fuel", "trip"]
    var wifiLogs = true
    var cellularSummaries = true
}
struct RecordingDraft: Codable {
    var id = UUID()
    var vehicleID: UUID?
    var source: TripSource
    var startedAt: Date
    var updatedAt: Date
    var distanceKM: Double = 0
    var route: [RoutePoint] = []
    var samples: [OBDSample]? = nil
    var scannerTransport: ScannerConnectionKind? = nil
    var scannerReconnectDeadline: Date? = nil
    mutating func accept(_ point: RoutePoint) {
        guard point.isValid, point.accuracy <= 50, point.timestamp >= startedAt else { return }
        if let last = route.last {
            let seconds = point.timestamp.timeIntervalSince(last.timestamp)
            guard seconds > 0 else { return }
            let metres = last.distance(to: point)
            guard metres / seconds * 3.6 <= DriveLineMetricPolicy.maximumPlausibleSpeedKph else { return }
            if seconds <= DriveLineMetricPolicy.maximumGPSGap && metres < DriveLineMetricPolicy.minimumGPSMovementM { return }
        }
        route.append(point)
        if let measured = DriveLineMetricPolicy.distanceFromGPS(route.map(\.shared)) { distanceKM = measured }
        updatedAt = max(updatedAt, point.timestamp)
    }
    func trip(endedAt: Date, recovered: Bool = false) -> Trip {
        let duration = max(0,endedAt.timeIntervalSince(startedAt))
        let recording = DriveLineRecording(recordingID:id,vehicleID:vehicleID ?? UUID(uuidString:"00000000-0000-0000-0000-000000000000")!,name:"Recording",startedAt:startedAt,endedAt:endedAt,
            sourceIDs:Array(Set((route.isEmpty ? [] : ["gps"])+((samples?.isEmpty == false) ? ["obd"] : []))).sorted(),
            gpsPoints:route.map(\.shared),signalSamples:(samples ?? []).map { DriveLineSignalSample(timestamp:$0.timestamp,values:$0.signals,sourceID:"obd") },isSample:source == .demo)
        let metrics = DriveLineMetricPolicy.metrics(for:recording)
        let km = metrics.distanceKm ?? 0
        return Trip(id:id,vehicleID:vehicleID,name:recovered ? "Recovered recording" : (source == .demo ? "Sample drive" : source == .scanner ? "Scanner drive" : "iPhone GPS drive"),startedAt:startedAt,duration:duration,distanceKM:km,source:source,isSample:source == .demo,economy:metrics.economyL100Km,fuelLitres:metrics.tripFuelLitres,route:route,samples:samples,scannerTransport:scannerTransport)
    }
}
struct StoredState: Codable {
    var schemaVersion = 3
    var regenTrackingStartedAt: Date? = nil
    var vehicles: [VehicleProfile] = []
    var selectedVehicleID: UUID?
    var onboardingCompleted = false
    var trips: [Trip] = []
    var fills: [FuelEntry] = []
    var preferences = Preferences()
    var draft: RecordingDraft?
    var scanner = ScannerSettings()
    var server = ServerSettings()
    var transfers: [TransferItem] = []
}
struct TripArchive: Codable {
    var schemaVersion = 1
    var vehicles: [VehicleProfile]?
    var trips: [Trip]
    static func decode(_ data: Data) throws -> TripArchive {
        guard data.count <= 20_000_000 else { throw AppFailure("Choose a JSON recording under 20 MB.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            if let date = formatter.date(from:text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from:text) else { throw AppFailure("Invalid recording timestamp.") }; return date
        }
        let archive = try decoder.decode(TripArchive.self, from: data)
        guard archive.schemaVersion == 1, archive.trips.count <= 500 else { throw AppFailure("Unsupported archive version or too many recordings.") }
        guard Set(archive.trips.map(\.id)).count == archive.trips.count else { throw AppFailure("The archive contains duplicate recording IDs.") }
        if let vehicles = archive.vehicles {
            guard vehicles.count <= 500, Set(vehicles.map(\.id)).count == vehicles.count else { throw AppFailure("Invalid vehicle list in archive.") }
            for vehicle in vehicles { _ = try vehicle.validated(requireIdentity:false) }
        }
        for trip in archive.trips {
            guard !trip.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  trip.name.count <= 200, trip.duration.isFinite, trip.duration >= 0,
                  trip.distanceKM.isFinite, trip.distanceKM >= 0,
                  trip.route.count <= 100_000, trip.route.allSatisfy(\.isValid),
                  (trip.samples?.count ?? 0) <= 200_000, trip.samples?.allSatisfy(\.isValid) ?? true,
                  trip.economy.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  trip.fuelLitres.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  trip.source != .phoneGPS || (trip.economy == nil && trip.fuelLitres == nil),
                  trip.scannerTransport == nil || trip.source == .scanner,
                  trip.source != .demo || trip.isSample else { throw AppFailure("The recording contains invalid values.") }
        }
        return archive
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            var container = encoder.singleValueContainer(); try container.encode(formatter.string(from:date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
struct AppFailure: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
enum FuelMath {
    // Include partial fills between two full fills. Never mix demo and real entries.
    static func latestEconomy(_ entries: [FuelEntry], sample: Bool = false) -> Double? {
        let shared = entries.filter { $0.isSample == sample }.compactMap { entry -> DriveLineFuelEntry? in
            guard let vehicleID = entry.vehicleID else { return nil }
            return DriveLineFuelEntry(id:entry.id,vehicleID:vehicleID,date:entry.date,litresPurchased:entry.litres,totalCost:entry.costCAD,odometerKm:entry.odometerKM,isFullFill:entry.full,isSample:entry.isSample)
        }
        return DriveLineMetricPolicy.tankToTankEconomy(shared,includeSamples:sample)
    }
}
extension Double {
    func text(_ decimals: Int = 1) -> String { String(format: "%.*f", decimals, self) }
}
