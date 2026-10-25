import Foundation

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
        var sourceIDs=Array(Set((route.isEmpty ? [] : ["gps"])+(readings.isEmpty ? [] : ["obd"]))).sorted()
        if source == .imported { sourceIDs.append("imported") }
        if isSample { sourceIDs.append("synthetic") }
        return DriveLineRecording(recordingID:id,vehicleID:vehicleID ?? UUID(uuidString:"00000000-0000-0000-0000-000000000000")!,name:name,startedAt:startedAt,
                                  endedAt:startedAt.addingTimeInterval(duration),
                                  sourceIDs:Array(Set(sourceIDs)).sorted(),
                                  gpsPoints:route.map(\.shared),signalSamples:readings,recordedDistanceKm:distanceKM,tripFuelLitres:fuelLitres,isSample:isSample)
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
    var currencyCode: String = "CAD"
    var stationName: String? = nil
    var notes: String? = nil
    var receipt: DriveLineReceiptMetadata? = nil
    var litresPurchased: Double { litres }

    private enum CodingKeys: String, CodingKey {
        case id, vehicleID, date, litres, costCAD, odometerKM, full, isSample
        case currencyCode, stationName, notes, receipt
    }
    init(id:UUID = UUID(),vehicleID:UUID? = nil,date:Date,litres:Double,costCAD:Double,odometerKM:Double,full:Bool,
         isSample:Bool = false,currencyCode:String = "CAD",stationName:String? = nil,notes:String? = nil,
         receipt:DriveLineReceiptMetadata? = nil) {
        self.id=id;self.vehicleID=vehicleID;self.date=date;self.litres=litres;self.costCAD=costCAD
        self.odometerKM=odometerKM;self.full=full;self.isSample=isSample;self.currencyCode=currencyCode
        self.stationName=stationName;self.notes=notes;self.receipt=receipt
    }
    init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        id=try values.decodeIfPresent(UUID.self,forKey:.id) ?? UUID()
        vehicleID=try values.decodeIfPresent(UUID.self,forKey:.vehicleID)
        date=try values.decode(Date.self,forKey:.date)
        litres=try values.decode(Double.self,forKey:.litres)
        costCAD=try values.decode(Double.self,forKey:.costCAD)
        odometerKM=try values.decode(Double.self,forKey:.odometerKM)
        full=try values.decode(Bool.self,forKey:.full)
        isSample=try values.decodeIfPresent(Bool.self,forKey:.isSample) ?? false
        currencyCode=try values.decodeIfPresent(String.self,forKey:.currencyCode) ?? "CAD"
        stationName=try values.decodeIfPresent(String.self,forKey:.stationName)
        notes=try values.decodeIfPresent(String.self,forKey:.notes)
        receipt=try values.decodeIfPresent(DriveLineReceiptMetadata.self,forKey:.receipt)
    }
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
    var schemaVersion = 4
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
    /// User-authored metadata lives beside recordings so preserved archive bytes
    /// and frozen transfer payloads never change when a drive is classified.
    var journeyAnnotations: [String: DriveLineJourneyAnnotation] = [:]
}
struct TripArchive: Codable {
    var schemaVersion = 2
    var vehicles: [VehicleProfile]?
    var trips: [Trip]
    var fills: [FuelEntry]
    var receiptFiles: [String:Data]?
    init(schemaVersion:Int = 2,vehicles:[VehicleProfile]? = nil,trips:[Trip],fills:[FuelEntry] = [],receiptFiles:[String:Data] = [:]) {
        self.schemaVersion=schemaVersion;self.vehicles=vehicles;self.trips=trips;self.fills=fills;self.receiptFiles=receiptFiles.isEmpty ? nil:receiptFiles
    }
    static func decode(_ data: Data) throws -> TripArchive {
        guard data.count <= 100 * 1024 * 1024 else { throw AppFailure("Choose a DriveLine archive no larger than 100 MB.") }
        let object = try JSONSerialization.jsonObject(with:data) as? [String:Any]
        let version = (object?["schemaVersion"] as? NSNumber)?.intValue ?? 1
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            if let date = formatter.date(from:text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from:text) else { throw AppFailure("Invalid recording timestamp.") }; return date
        }
        if version == 1 {
            struct Legacy:Codable { var schemaVersion:Int;var vehicles:[VehicleProfile]?;var trips:[Trip] }
            let legacy=try decoder.decode(Legacy.self,from:data)
            let archive=TripArchive(vehicles:legacy.vehicles,trips:legacy.trips)
            try validate(archive)
            return archive
        }
        guard version == 2 else { throw AppFailure("Unsupported archive version.") }
        let shared:DriveLineArchive
        do { shared=try DriveLineArchive.decoded(data) }
        catch { throw AppFailure(error.localizedDescription) }
        let missingVehicle=UUID(uuidString:"00000000-0000-0000-0000-000000000000")!
        let detailedProfiles=shared.extensionData["com.canconnect.ios.vehicleProfiles"].flatMap { try? JSONDecoder().decode([VehicleProfile].self,from:$0) } ?? []
        let profiles:[VehicleProfile]
        if !detailedProfiles.isEmpty { profiles=detailedProfiles }
        else {
            profiles=shared.vehicles.filter { $0.id != missingVehicle }.map { vehicle in
                var profile=VehicleProfile();profile.id=vehicle.id;profile.nickname=vehicle.name
                profile.year=vehicle.year.flatMap(Int.init);profile.make=vehicle.make ?? "";profile.model=vehicle.model ?? ""
                profile.vin=vehicle.vin;profile.fuel=vehicle.fuelType.flatMap { FuelKind(rawValue:$0.lowercased()) } ?? .unknown
                profile.kind=vehicle.vehicleClass.map { value in switch value { case .passengerCar:return .car;case .lightTruck:return .pickup;case .motorcycle:return .motorcycle;case .heavyTruck:return .heavyTruck;case .van:return .van;case .other:return .other } } ?? .car
                profile.preferredUnits=vehicle.preferredUnits ?? .metric;profile.preferredGPS=vehicle.preferredGPS ?? .automatic
                profile.configuredSources=vehicle.configuredSources;profile.isArchived=vehicle.isArchived
                profile.identificationSource="DriveLine archive";return profile
            }
        }
        let trips=shared.recordings.map { recording -> Trip in
            let route=recording.gpsPoints.map { RoutePoint(latitude:$0.latitude,longitude:$0.longitude,timestamp:$0.timestamp,accuracy:$0.horizontalAccuracyM ?? 0,speed:$0.speedMps) }
            let samples=recording.signalSamples.map { OBDSample(timestamp:$0.timestamp,signals:$0.values,command:$0.command ?? "ARCHIVE",reply:$0.reply ?? "Canonical DriveLine sample",requestHeader:$0.requestHeader,responseHeader:$0.responseHeader) }
            let metrics=DriveLineMetricPolicy.metrics(for:recording)
            let source=recording.metadata["tripSource"].flatMap(TripSource.init(rawValue:)) ?? (!samples.isEmpty ? .scanner : !route.isEmpty ? .phoneGPS : .imported)
            let transport=recording.metadata["scannerTransport"].flatMap(ScannerConnectionKind.init(rawValue:))
            let vehicleID=recording.metadata["legacyVehicleID"] == "missing" ? nil : recording.vehicleID
            return Trip(id:recording.recordingID,vehicleID:vehicleID,name:recording.name,startedAt:recording.startedAt,
                        duration:metrics.durationSeconds,distanceKM:metrics.distanceKm ?? 0,source:source,isSample:recording.isSample,
                        economy:metrics.economyL100Km,fuelLitres:metrics.tripFuelLitres,route:route,samples:samples.isEmpty ? nil : samples,scannerTransport:transport)
        }
        let fills=shared.fuelEntries.map { fill in
            FuelEntry(id:fill.id,vehicleID:fill.vehicleID == missingVehicle ? nil : fill.vehicleID,date:fill.date,litres:fill.litresPurchased,costCAD:fill.totalCost,
                      odometerKM:fill.odometerKm,full:fill.isFullFill,isSample:fill.isSample,currencyCode:fill.currencyCode,
                      stationName:fill.stationName,notes:fill.notes,receipt:fill.receipt)
        }
        let archive=TripArchive(vehicles:profiles,trips:trips,fills:fills,receiptFiles:shared.receiptFiles)
        try validate(archive)
        return archive
    }
    private static func validate(_ archive:TripArchive) throws {
        guard archive.trips.count <= 500,archive.fills.count <= 5_000 else { throw AppFailure("Unsupported archive version or too many records.") }
        guard Set(archive.trips.map(\.id)).count == archive.trips.count else { throw AppFailure("The archive contains duplicate recording IDs.") }
        guard Set(archive.fills.map(\.id)).count == archive.fills.count else { throw AppFailure("The archive contains duplicate fuel entry IDs.") }
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
        for fill in archive.fills {
            guard fill.litres.isFinite,fill.litres > 0,fill.costCAD.isFinite,fill.costCAD >= 0,
                  fill.odometerKM.isFinite,fill.odometerKM >= 0,fill.currencyCode.count == 3,
                  fill.currencyCode.allSatisfy({$0.isASCII && $0.isLetter}) else { throw AppFailure("The archive contains invalid fuel values.") }
        }
    }
    func encoded() throws -> Data {
        guard schemaVersion == 2 else { throw AppFailure("Only DriveLine archive schema version 2 can be encoded.") }
        let missingVehicle=UUID(uuidString:"00000000-0000-0000-0000-000000000000")!
        let recordings=trips.map { trip -> DriveLineRecording in
            var recording=trip.sharedRecording
            recording.vehicleID=trip.vehicleID ?? missingVehicle
            recording.metadata["tripSource"]=trip.source.rawValue
            if trip.vehicleID == nil { recording.metadata["legacyVehicleID"]="missing" }
            if let scannerTransport=trip.scannerTransport { recording.metadata["scannerTransport"]=scannerTransport.rawValue }
            recording.signalSamples=(trip.samples ?? []).map { sample in
                DriveLineSignalSample(timestamp:sample.timestamp,values:sample.signals,sourceID:"obd",command:sample.command,reply:sample.reply,
                                      requestHeader:sample.requestHeader,responseHeader:sample.responseHeader)
            }
            recording.coverage=DriveLineMetricPolicy.coverageSummaries(recording)
            return recording
        }
        let sharedVehicles=(vehicles ?? []).map {
            DriveLineVehicle(id:$0.id,name:$0.title,year:$0.year.map(String.init),make:$0.make,model:$0.model,
                vehicleClass:$0.kind.shared,fuelType:$0.fuel.title,vin:$0.vin,preferredUnits:$0.preferredUnits,
                preferredGPS:$0.preferredGPS,configuredSources:$0.configuredSources,isArchived:$0.isArchived)
        }
        var allVehicles=sharedVehicles
        let referencedVehicleIDs=Set(recordings.map(\.vehicleID)).union(fills.map { $0.vehicleID ?? missingVehicle })
        for id in referencedVehicleIDs where !allVehicles.contains(where:{$0.id == id}) {
            allVehicles.append(DriveLineVehicle(id:id,name:id == missingVehicle ? "Unassigned legacy vehicle" : "Vehicle \(id.uuidString.prefix(8))"))
        }
        let sharedFills=fills.map { fill -> DriveLineFuelEntry in
            let vehicleID=fill.vehicleID ?? missingVehicle
            return DriveLineFuelEntry(id:fill.id,vehicleID:vehicleID,date:fill.date,litresPurchased:fill.litres,totalCost:fill.costCAD,
                                      currencyCode:fill.currencyCode,odometerKm:fill.odometerKM,isFullFill:fill.full,stationName:fill.stationName,
                                      notes:fill.notes,receipt:fill.receipt,isSample:fill.isSample)
        }
        let sourceIDs=Set(recordings.flatMap(\.sourceIDs))
        let sources=sourceIDs.sorted().map { id -> DriveLineSourceDescriptor in
            switch id {
            case "gps": return DriveLineSourceDescriptor(id:id,kind:.gps,name:"iPhone GPS")
            case "obd": return DriveLineSourceDescriptor(id:id,kind:.obd,name:"OBD scanner")
            case "synthetic": return DriveLineSourceDescriptor(id:id,kind:.synthetic,name:"Labelled sample data")
            default: return DriveLineSourceDescriptor(id:id,kind:.imported,name:"Imported recording")
            }
        }
        let profileData=try JSONEncoder().encode(vehicles ?? [])
        let producerVersion=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
        return try DriveLineArchive(producer:DriveLineProducer(app:"DriveLine iPhone",version:producerVersion,platform:"iOS"),sources:sources,
                                    vehicles:allVehicles,recordings:recordings,fuelEntries:sharedFills,
                                    receiptFiles:receiptFiles ?? [:],
                                    extensionData:["com.canconnect.ios.vehicleProfiles":profileData]).encoded()
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
        let unassigned=UUID(uuidString:"00000000-0000-0000-0000-000000000000")!
        let shared = entries.filter { $0.isSample == sample }.map { entry -> DriveLineFuelEntry in
            let vehicleID = entry.vehicleID ?? unassigned
            return DriveLineFuelEntry(id:entry.id,vehicleID:vehicleID,date:entry.date,litresPurchased:entry.litres,totalCost:entry.costCAD,odometerKm:entry.odometerKM,isFullFill:entry.full,isSample:entry.isSample)
        }
        return DriveLineMetricPolicy.tankToTankEconomy(shared,includeSamples:sample)
    }
}
extension Double {
    func text(_ decimals: Int = 1) -> String { String(format: "%.*f", decimals, self) }
}
