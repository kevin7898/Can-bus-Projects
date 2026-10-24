import Foundation

public enum Signal: String, Codable, CaseIterable, Identifiable {
    case speedKph, rpm, coolantC, boostKpa, mapKpa, barometricKpa, fuelRateLph, fuelPercent, voltage, intakeC, oilC, engineLoad
    case mafGps, outsideC, boostAbsoluteKpa, boostCommandedKpa, boostBAbsoluteKpa, boostBCommandedKpa
    case egt1C, egt2C, egt3C, egt4C, dpfDifferentialKpa, dpfInletKpa, dpfOutletKpa
    case dpfRegenActive, dpfRegenType, dpfRegenTrigger, dpfAverageRegenMinutes, dpfAverageRegenKM
    case dpfAshML, dsgFluidC
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .speedKph: return "Vehicle speed"
        case .rpm: return "Engine speed"
        case .coolantC: return "Coolant"
        case .boostKpa: return "Boost pressure"
        case .mapKpa: return "Manifold pressure"
        case .barometricKpa: return "Barometric pressure"
        case .fuelRateLph: return "Fuel rate"
        case .fuelPercent: return "Fuel level"
        case .voltage: return "Battery voltage"
        case .intakeC: return "Intake temperature"
        case .oilC: return "Oil temperature"
        case .engineLoad: return "Engine load"
        case .mafGps: return "Mass airflow"
        case .outsideC: return "Outside temperature"
        case .boostAbsoluteKpa: return "Boost pressure A"
        case .boostCommandedKpa: return "Commanded boost A"
        case .boostBAbsoluteKpa: return "Boost pressure B"
        case .boostBCommandedKpa: return "Commanded boost B"
        case .egt1C: return "Exhaust temperature 1"
        case .egt2C: return "Exhaust temperature 2"
        case .egt3C: return "Exhaust temperature 3"
        case .egt4C: return "Exhaust temperature 4"
        case .dpfDifferentialKpa: return "DPF differential pressure"
        case .dpfInletKpa: return "DPF inlet pressure"
        case .dpfOutletKpa: return "DPF outlet pressure"
        case .dpfRegenActive: return "DPF regeneration"
        case .dpfRegenType: return "DPF active regeneration type"
        case .dpfRegenTrigger: return "DPF regeneration trigger"
        case .dpfAverageRegenMinutes: return "Average regeneration interval"
        case .dpfAverageRegenKM: return "Average regeneration distance"
        case .dpfAshML: return "DPF ash volume"
        case .dsgFluidC: return "DSG fluid temperature"
        }
    }
    public var unit: String {
        switch self {
        case .speedKph: return "km/h"
        case .rpm: return "rpm"
        case .coolantC, .intakeC, .oilC, .outsideC, .egt1C, .egt2C, .egt3C, .egt4C, .dsgFluidC: return "°C"
        case .boostKpa: return "kPa gauge"
        case .mapKpa, .barometricKpa, .boostAbsoluteKpa, .boostCommandedKpa, .boostBAbsoluteKpa, .boostBCommandedKpa: return "kPa absolute"
        case .fuelRateLph: return "L/h"
        case .fuelPercent, .engineLoad, .dpfRegenTrigger: return "%"
        case .voltage: return "V"
        case .mafGps: return "g/s"
        case .dpfDifferentialKpa, .dpfInletKpa, .dpfOutletKpa: return "kPa"
        case .dpfRegenActive, .dpfRegenType: return "state"
        case .dpfAverageRegenMinutes: return "min"
        case .dpfAverageRegenKM: return "km"
        case .dpfAshML: return "mL"
        }
    }
}

public struct Vehicle: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var year: String
    public var make: String
    public var model: String
    public var vin: String
    public var notes: String
    public init(id: UUID = UUID(), name: String, year: String = "", make: String = "", model: String = "", vin: String = "", notes: String = "") {
        self.id = id; self.name = name; self.year = year; self.make = make; self.model = model; self.vin = vin; self.notes = notes
    }
}

public struct TelemetrySample: Codable, Identifiable, Equatable {
    public var timestamp: Date
    public var latitude: Double?
    public var longitude: Double?
    public var signals: [String: Double]
    public var id: Date { timestamp }
    public init(timestamp: Date, latitude: Double? = nil, longitude: Double? = nil, signals: [String: Double] = [:]) {
        self.timestamp = timestamp; self.latitude = latitude; self.longitude = longitude; self.signals = signals
    }
    public var hasCoordinate: Bool {
        guard let lat = latitude, let lon = longitude else { return false }
        return lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
    }
    public func value(_ signal: Signal) -> Double? { signals[signal.rawValue] }
}

public struct Trip: Codable, Identifiable {
    public var id: UUID
    public var vehicleID: UUID
    public var receiptID: UUID
    public var name: String
    public var source: String
    public var samples: [TelemetrySample]
    public var rawFrameCount: Int
    public var arbitrationIDs: [String: Int]
    public var diagnosticResponseCount: Int
    public var isDemo: Bool
    public init(id: UUID = UUID(), vehicleID: UUID, receiptID: UUID = UUID(), name: String, source: String, samples: [TelemetrySample], rawFrameCount: Int = 0, arbitrationIDs: [String: Int] = [:], diagnosticResponseCount: Int = 0, isDemo: Bool = false) {
        self.id = id; self.vehicleID = vehicleID; self.receiptID = receiptID; self.name = name; self.source = source
        self.samples = Self.merge(samples); self.rawFrameCount = rawFrameCount; self.arbitrationIDs = arbitrationIDs
        self.diagnosticResponseCount = diagnosticResponseCount; self.isDemo = isDemo
    }
    public var start: Date { samples.first?.timestamp ?? Date(timeIntervalSince1970: 0) }
    public var end: Date { samples.last?.timestamp ?? start }
    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    public var coordinates: [TelemetrySample] { samples.filter(\.hasCoordinate) }
    public var availableSignals: [Signal] { Signal.allCases.filter { key in samples.contains { $0.value(key) != nil } } }
    // Segment before display downsampling so a chart cannot bridge an unrecorded gap.
    public func trace(_ signal:Signal,limit:Int = 3000) -> [SignalTracePoint] {
        var points:[SignalTracePoint] = [],segment = 0
        var previous:Date?
        for sample in samples where sample.value(signal) != nil {
            if let previous = previous,sample.timestamp.timeIntervalSince(previous)>10 { segment += 1 }
            points.append(SignalTracePoint(sample:sample,segment:segment));previous = sample.timestamp
        }
        guard points.count>max(2,limit) else { return points }
        let step = Int(ceil(Double(points.count-1)/Double(max(2,limit)-1)))
        var selected = stride(from:0,to:points.count,by:step).map { points[$0] }
        if selected.last?.id != points.last?.id,let last = points.last { selected.append(last) }
        return selected
    }
    public var distanceKm: Double? {
        let gps = coordinates
        if gps.count > 1 {
            var sum = 0.0; var intervals = 0
            for (a,b) in zip(gps, gps.dropFirst()) {
                let dt = b.timestamp.timeIntervalSince(a.timestamp)
                guard dt > 0, dt <= 30 else { continue }
                let distance = Self.haversine(a, b)
                guard distance / dt * 3600 <= 300 else { continue }
                sum += distance; intervals += 1
            }
            if intervals > 0 { return sum }
        }
        return integrate(.speedKph).map { $0.value / 3600 }
    }
    public var fuelUsedL: Double? {
        guard let result = integrate(.fuelRateLph), duration > 0, result.coverage / duration >= 0.8 else { return nil }
        return result.value / 3600
    }
    public var economyL100: Double? {
        guard let km = distanceKm, km > 0.1, let fuel = fuelUsedL else { return nil }
        return fuel / km * 100
    }
    public func integrate(_ key: Signal) -> (value: Double, coverage: Double)? {
        let points = samples.compactMap { s -> (Date,Double)? in s.value(key).map { (s.timestamp, $0) } }
        var sum = 0.0; var coverage = 0.0
        for (a,b) in zip(points, points.dropFirst()) {
            let dt = b.0.timeIntervalSince(a.0)
            guard dt > 0, dt <= 10, a.1 >= 0, b.1 >= 0 else { continue }
            sum += (a.1 + b.1) / 2 * dt; coverage += dt
        }
        return coverage > 0 ? (sum,coverage) : nil
    }
    public static func haversine(_ a: TelemetrySample, _ b: TelemetrySample) -> Double {
        guard a.hasCoordinate, b.hasCoordinate else { return 0 }
        let r = Double.pi / 180
        let lat1 = a.latitude! * r, lat2 = b.latitude! * r
        let dlat = lat2-lat1, dlon = (b.longitude!-a.longitude!) * r
        let h = pow(sin(dlat/2),2) + cos(lat1)*cos(lat2)*pow(sin(dlon/2),2)
        return 6371 * 2 * atan2(sqrt(h), sqrt(max(0,1-h)))
    }
    private static func merge(_ input: [TelemetrySample]) -> [TelemetrySample] {
        var merged: [Date: TelemetrySample] = [:]
        for s in input {
            guard s.timestamp.timeIntervalSince1970.isFinite else { continue }
            var target = merged[s.timestamp] ?? TelemetrySample(timestamp: s.timestamp)
            if s.hasCoordinate { target.latitude = s.latitude; target.longitude = s.longitude }
            for (k,v) in s.signals where v.isFinite { target.signals[k] = v }
            merged[s.timestamp] = target
        }
        return merged.values.sorted { $0.timestamp < $1.timestamp }
    }
}

public struct SignalTracePoint:Identifiable {
    public var sample:TelemetrySample
    public var segment:Int
    public var id:Date { sample.timestamp }
}

public enum ReceiptStatus: String, Codable { case queued, processing, processed, failed }
public struct ImportReceipt: Codable, Identifiable {
    public var id = UUID()
    public var vehicleID: UUID
    public var originalName: String
    public var archiveName: String
    public var contentHash: String
    public var status: ReceiptStatus = .queued
    public var createdAt = Date()
    public var completedAt: Date?
    public var message: String = "Original copied; waiting for processing"
    public var tripIDs: [UUID] = []
    public var byteCount: Int
    public init(vehicleID: UUID, originalName: String, archiveName: String, contentHash: String, byteCount: Int) {
        self.vehicleID = vehicleID; self.originalName = originalName; self.archiveName = archiveName; self.contentHash = contentHash; self.byteCount = byteCount
    }
}
public struct MapViewport: Codable, Equatable {
    public var latitude: Double = 49.19
    public var longitude: Double = -123.97
    public var latitudeDelta: Double = 0.13
    public var longitudeDelta: Double = 0.18
    public init() {}
}
public enum SummaryKind: String, Codable, CaseIterable { case distance, economy, drives, duration
    public var title: String {
        switch self { case .distance: return "Distance recorded"; case .economy: return "Average economy"; case .drives: return "Recorded drives"; case .duration: return "Time on the road" }
    }
}
public struct SummaryWidget: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var kind: SummaryKind
    public var columns = 1
    public var rows = 1
    public init(kind: SummaryKind) { self.kind = kind }
}
public struct VehiclePreferences: Codable {
    public var map = MapViewport()
    public var mapStyle = "standard"
    public var periodDays = 30
    public var widgets = SummaryKind.allCases.map { SummaryWidget(kind: $0) }
    public var signals = [Signal.speedKph, .rpm, .coolantC, .boostKpa, .fuelRateLph, .voltage]
    public var mapFirst = true
    public init() {}
}
public struct LibraryState: Codable {
    public var schemaVersion = 1
    public var vehicles: [Vehicle] = []
    public var trips: [Trip] = []
    public var receipts: [ImportReceipt] = []
    public var selectedVehicleID: UUID?
    public var preferences: [String: VehiclePreferences] = [:]
    public var serverPort: UInt16 = 8765
    public var allowLAN = false
    public var autoStartServer = false
    public init() {}
    public mutating func removeDemoData() {
        let demoVehicleIDs = Set(trips.filter(\.isDemo).map(\.vehicleID))
        trips.removeAll { $0.isDemo }
        let retainedIDs = Set(trips.map(\.vehicleID)).union(receipts.map(\.vehicleID))
        let removedIDs = demoVehicleIDs.subtracting(retainedIDs)
        vehicles.removeAll { removedIDs.contains($0.id) }
        for id in removedIDs { preferences.removeValue(forKey:id.uuidString) }
        if !vehicles.contains(where:{$0.id==selectedVehicleID}) { selectedVehicleID = vehicles.first?.id }
    }
}
public enum CANError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let s): return s } }
}
