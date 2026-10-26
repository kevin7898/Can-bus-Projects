import Foundation
#if canImport(DriveLineShared)
import DriveLineShared
#endif

public enum Signal: String, Codable, CaseIterable, Identifiable {
    case speedKph, rpm, coolantC, boostKpa, mapKpa, barometricKpa, fuelRateLph, fuelPercent, voltage, intakeC, oilC, engineLoad
    case mafGps, outsideC, boostAbsoluteKpa, boostCommandedKpa, boostBAbsoluteKpa, boostBCommandedKpa
    case egt1C, egt2C, egt3C, egt4C, dpfDifferentialKpa, dpfInletKpa, dpfOutletKpa
    case dpfRegenActive, dpfRegenType, dpfRegenTrigger, dpfAverageRegenMinutes, dpfAverageRegenKM
    case dpfAshML, dpfSootG, dsgFluidC
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
        case .dpfSootG: return "DPF soot mass"
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
        case .dpfSootG: return "g"
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
    public var vehicleClass: DriveLineVehicleClass
    public var fuelType: String
    public var preferredUnits: DriveLineUnitSystem
    public var preferredGPS: DriveLineGPSPreference
    public var configuredSources: [DriveLineVehicleSource]
    public var scannerHost: String?
    public var scannerPort: UInt16?
    public var identification: DriveLineVehicleIdentityObservation?
    public var isArchived: Bool
    public var archivedAt: Date?
    public init(id: UUID = UUID(), name: String, year: String = "", make: String = "", model: String = "", vin: String = "", notes: String = "",
                vehicleClass: DriveLineVehicleClass = .passengerCar, fuelType: String = "Unknown",
                preferredUnits: DriveLineUnitSystem = .metric, preferredGPS: DriveLineGPSPreference = .automatic,
                configuredSources: [DriveLineVehicleSource] = [.manual, .phoneGPS], scannerHost: String? = nil,
                scannerPort: UInt16? = nil, identification: DriveLineVehicleIdentityObservation? = nil,
                isArchived: Bool = false, archivedAt: Date? = nil) {
        self.id = id; self.name = name; self.year = year; self.make = make; self.model = model; self.vin = vin; self.notes = notes
        self.vehicleClass=vehicleClass;self.fuelType=fuelType;self.preferredUnits=preferredUnits;self.preferredGPS=preferredGPS
        self.configuredSources=configuredSources;self.scannerHost=scannerHost;self.scannerPort=scannerPort
        self.identification=identification;self.isArchived=isArchived;self.archivedAt=archivedAt
    }
    private enum CodingKeys:String,CodingKey {
        case id,name,year,make,model,vin,notes,vehicleClass,fuelType,preferredUnits,preferredGPS
        case configuredSources,scannerHost,scannerPort,identification,isArchived,archivedAt
    }
    public init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        id=try values.decodeIfPresent(UUID.self,forKey:.id) ?? UUID()
        name=try values.decodeIfPresent(String.self,forKey:.name) ?? "Vehicle"
        year=try values.decodeIfPresent(String.self,forKey:.year) ?? ""
        make=try values.decodeIfPresent(String.self,forKey:.make) ?? ""
        model=try values.decodeIfPresent(String.self,forKey:.model) ?? ""
        vin=try values.decodeIfPresent(String.self,forKey:.vin) ?? ""
        notes=try values.decodeIfPresent(String.self,forKey:.notes) ?? ""
        vehicleClass=try values.decodeIfPresent(DriveLineVehicleClass.self,forKey:.vehicleClass) ?? .passengerCar
        fuelType=try values.decodeIfPresent(String.self,forKey:.fuelType) ?? "Unknown"
        preferredUnits=try values.decodeIfPresent(DriveLineUnitSystem.self,forKey:.preferredUnits) ?? .metric
        preferredGPS=try values.decodeIfPresent(DriveLineGPSPreference.self,forKey:.preferredGPS) ?? .automatic
        configuredSources=try values.decodeIfPresent([DriveLineVehicleSource].self,forKey:.configuredSources) ?? [.manual,.phoneGPS]
        scannerHost=try values.decodeIfPresent(String.self,forKey:.scannerHost)
        scannerPort=try values.decodeIfPresent(UInt16.self,forKey:.scannerPort)
        identification=try values.decodeIfPresent(DriveLineVehicleIdentityObservation.self,forKey:.identification)
        isArchived=try values.decodeIfPresent(Bool.self,forKey:.isArchived) ?? false
        archivedAt=try values.decodeIfPresent(Date.self,forKey:.archivedAt)
    }
}

public struct TelemetrySample: Codable, Identifiable, Equatable, Sendable {
    public var timestamp: Date
    public var latitude: Double?
    public var longitude: Double?
    public var signals: [String: Double]
    public var command:String?
    public var reply:String?
    public var requestHeader:String?
    public var responseHeader:String?
    public var id: Date { timestamp }
    public init(timestamp: Date, latitude: Double? = nil, longitude: Double? = nil, signals: [String: Double] = [:],
                command:String?=nil,reply:String?=nil,requestHeader:String?=nil,responseHeader:String?=nil) {
        self.timestamp = timestamp; self.latitude = latitude; self.longitude = longitude; self.signals = signals
        self.command=command;self.reply=reply;self.requestHeader=requestHeader;self.responseHeader=responseHeader
    }
    public var hasCoordinate: Bool {
        guard let lat = latitude, let lon = longitude else { return false }
        return lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
    }
    public func value(_ signal: Signal) -> Double? { signals[signal.rawValue] }
}

public struct Trip: Codable, Identifiable, Sendable {
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
    public var recordedStartedAt:Date?
    public var recordedEndedAt:Date?
    public var recordedDistanceKm: Double?
    public var tripFuelLitres: Double?
    public init(id: UUID = UUID(), vehicleID: UUID, receiptID: UUID = UUID(), name: String, source: String, samples: [TelemetrySample], rawFrameCount: Int = 0, arbitrationIDs: [String: Int] = [:], diagnosticResponseCount: Int = 0, isDemo: Bool = false, recordedStartedAt:Date?=nil,recordedEndedAt:Date?=nil,recordedDistanceKm:Double? = nil, tripFuelLitres:Double? = nil) {
        self.id = id; self.vehicleID = vehicleID; self.receiptID = receiptID; self.name = name; self.source = source
        self.samples = Self.merge(samples); self.rawFrameCount = rawFrameCount; self.arbitrationIDs = arbitrationIDs
        self.diagnosticResponseCount = diagnosticResponseCount; self.isDemo = isDemo
        self.recordedStartedAt=recordedStartedAt;self.recordedEndedAt=recordedEndedAt
        self.recordedDistanceKm=recordedDistanceKm;self.tripFuelLitres=tripFuelLitres
    }
    public var start: Date { recordedStartedAt ?? samples.first?.timestamp ?? Date(timeIntervalSince1970: 0) }
    public var end: Date { recordedEndedAt ?? samples.last?.timestamp ?? start }
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
        DriveLineMetricPolicy.metrics(for: sharedRecording).distanceKm
    }
    public var fuelUsedL: Double? {
        DriveLineMetricPolicy.metrics(for: sharedRecording).tripFuelLitres
    }
    public var economyL100: Double? {
        guard let km = distanceKm, km > 0.1, let fuel = fuelUsedL else { return nil }
        return fuel / km * 100
    }
    public func integrate(_ key: Signal) -> (value: Double, coverage: Double)? {
        DriveLineMetricPolicy.integral(key.rawValue, samples: sharedRecording.signalSamples)
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
            if s.command != nil { target.command=s.command }
            if s.reply != nil { target.reply=s.reply }
            if s.requestHeader != nil { target.requestHeader=s.requestHeader }
            if s.responseHeader != nil { target.responseHeader=s.responseHeader }
            merged[s.timestamp] = target
        }
        return merged.values.sorted { $0.timestamp < $1.timestamp }
    }
    public var sharedRecording: DriveLineRecording {
        let gps = samples.compactMap { sample -> DriveLineGPSPoint? in
            guard sample.hasCoordinate else { return nil }
            return DriveLineGPSPoint(timestamp:sample.timestamp,latitude:sample.latitude!,longitude:sample.longitude!,sourceID:"gps")
        }
        let readings = samples.compactMap { sample -> DriveLineSignalSample? in
            sample.signals.isEmpty ? nil : DriveLineSignalSample(timestamp:sample.timestamp,values:sample.signals,sourceID:"obd",
                command:sample.command,reply:sample.reply,requestHeader:sample.requestHeader,responseHeader:sample.responseHeader)
        }
        var sourceIDs=Array(Set((gps.isEmpty ? [] : ["gps"])+(readings.isEmpty ? [] : ["obd"]))).sorted()
        sourceIDs.append(isDemo || source.localizedCaseInsensitiveContains("synthetic") ? "synthetic":"imported")
        return DriveLineRecording(recordingID:id,vehicleID:vehicleID,name:name,startedAt:start,endedAt:end,
                                  sourceIDs:Array(Set(sourceIDs)).sorted(),
                                  gpsPoints:gps,signalSamples:readings,recordedDistanceKm:recordedDistanceKm,
                                  tripFuelLitres:tripFuelLitres,isSample:isDemo)
    }
}

public struct SignalTracePoint:Identifiable {
    public var sample:TelemetrySample
    public var segment:Int
    public var id:Date { sample.timestamp }
}

public struct FuelEntry:Codable,Identifiable,Equatable,Sendable {
    public var id:UUID
    public var vehicleID:UUID
    public var date:Date
    public var litresPurchased:Double
    public var totalCost:Double
    public var currencyCode:String
    public var odometerKm:Double
    public var isFullFill:Bool
    public var stationName:String?
    public var notes:String?
    public var receipt:DriveLineReceiptMetadata?
    public var isDemo:Bool
    public init(id:UUID = UUID(),vehicleID:UUID,date:Date,litresPurchased:Double,totalCost:Double,currencyCode:String="CAD",
                odometerKm:Double,isFullFill:Bool,stationName:String?=nil,notes:String?=nil,receipt:DriveLineReceiptMetadata?=nil,isDemo:Bool=false) {
        self.id=id;self.vehicleID=vehicleID;self.date=date;self.litresPurchased=litresPurchased;self.totalCost=totalCost
        self.currencyCode=currencyCode;self.odometerKm=odometerKm;self.isFullFill=isFullFill;self.stationName=stationName
        self.notes=notes;self.receipt=receipt;self.isDemo=isDemo
    }
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
public extension ImportReceipt {
    var semanticState:DriveLineSemanticState {
        switch status { case .queued:return .queued;case .processing:return .processing;case .processed:return .complete;case .failed:return .failed }
    }
    var statusTitle:String {
        switch status { case .queued:return "Queued";case .processing:return "Processing preserved original";case .processed:return "Processed";case .failed:return "Failed · original preserved" }
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
    /// Stable identifiers selected by the Phase 6 recorded-Signals workspace.
    /// `signals` remains encoded for older libraries; a missing value migrates
    /// in memory without rewriting the library until the next ordinary save.
    public var signalKeys: [String]?
    public var mapFirst = true
    public init() {}
    public var resolvedSignalKeys:[String] {
        var values=(signalKeys?.isEmpty == false ? signalKeys!:signals.map(\.rawValue))
        let defaults=signals.map(\.rawValue)
        while values.count<6 { values.append(defaults[values.count % defaults.count]) }
        return Array(values.prefix(max(6,values.count)))
    }
}
public struct LibraryState: Codable {
    public var schemaVersion = 3
    public var vehicles: [Vehicle] = []
    public var trips: [Trip] = []
    public var receipts: [ImportReceipt] = []
    public var fuelEntries:[FuelEntry] = []
    public var selectedVehicleID: UUID?
    public var preferences: [String: VehiclePreferences] = [:]
    public var serverPort: UInt16 = 8765
    public var allowLAN = false
    public var autoStartServer = false
    /// Local sidecar annotations keyed by stable recordingID. They are not
    /// included in archives or preserved import originals.
    public var journeyAnnotations:[String:DriveLineJourneyAnnotation] = [:]
    public init() {}
    private enum CodingKeys:String,CodingKey { case schemaVersion,vehicles,trips,receipts,fuelEntries,selectedVehicleID,preferences,serverPort,allowLAN,autoStartServer,journeyAnnotations }
    public init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        schemaVersion=try values.decodeIfPresent(Int.self,forKey:.schemaVersion) ?? 1
        vehicles=try values.decodeIfPresent([Vehicle].self,forKey:.vehicles) ?? []
        trips=try values.decodeIfPresent([Trip].self,forKey:.trips) ?? []
        receipts=try values.decodeIfPresent([ImportReceipt].self,forKey:.receipts) ?? []
        fuelEntries=try values.decodeIfPresent([FuelEntry].self,forKey:.fuelEntries) ?? []
        selectedVehicleID=try values.decodeIfPresent(UUID.self,forKey:.selectedVehicleID)
        preferences=try values.decodeIfPresent([String:VehiclePreferences].self,forKey:.preferences) ?? [:]
        serverPort=try values.decodeIfPresent(UInt16.self,forKey:.serverPort) ?? 8765
        allowLAN=try values.decodeIfPresent(Bool.self,forKey:.allowLAN) ?? false
        autoStartServer=try values.decodeIfPresent(Bool.self,forKey:.autoStartServer) ?? false
        journeyAnnotations=try values.decodeIfPresent([String:DriveLineJourneyAnnotation].self,forKey:.journeyAnnotations) ?? [:]
        if schemaVersion < 3 { schemaVersion = 3 }
    }
    public mutating func removeDemoData() {
        let demoTrips = trips.filter(\.isDemo)
        let demoVehicleIDs = Set(demoTrips.map(\.vehicleID))
        trips.removeAll { $0.isDemo }
        for id in demoTrips.map(\.id) { journeyAnnotations.removeValue(forKey:id.uuidString) }
        fuelEntries.removeAll { $0.isDemo }
        let retainedIDs = Set(trips.map(\.vehicleID)).union(receipts.map(\.vehicleID)).union(fuelEntries.map(\.vehicleID))
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
