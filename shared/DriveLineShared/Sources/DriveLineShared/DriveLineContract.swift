import Foundation
import CryptoKit

public enum DriveLineContractError: LocalizedError, Equatable {
    case invalid(String)

    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

public enum DriveLineJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSince1970)
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self), seconds.isFinite {
                return Date(timeIntervalSince1970: seconds)
            }
            let value = try container.decode(String.self)
            guard let date = date(value) else {
                throw DriveLineContractError.invalid("Invalid absolute timestamp: \(value)")
            }
            return date
        }
        return decoder
    }

    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public struct DriveLineProducer: Codable, Equatable, Sendable {
    public var app: String
    public var version: String
    public var platform: String

    public init(app: String, version: String, platform: String) {
        self.app = app
        self.version = version
        self.platform = platform
    }
}

public enum DriveLineSourceKind: String, Codable, Sendable {
    case gps
    case obd
    case imported
    case synthetic
}

public struct DriveLineSourceDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: DriveLineSourceKind
    public var name: String
    public var detail: String?

    public init(id: String, kind: DriveLineSourceKind, name: String, detail: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.detail = detail
    }
}

public struct DriveLineVehicle: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var year: String?
    public var make: String?
    public var model: String?
    public var vehicleClass: DriveLineVehicleClass?
    public var fuelType: String?
    public var vin: String?
    public var preferredUnits: DriveLineUnitSystem?
    public var preferredGPS: DriveLineGPSPreference?
    public var configuredSources: [DriveLineVehicleSource]
    public var isArchived: Bool

    public init(id: UUID, name: String, year: String? = nil, make: String? = nil, model: String? = nil,
                vehicleClass: DriveLineVehicleClass? = nil, fuelType: String? = nil, vin: String? = nil,
                preferredUnits: DriveLineUnitSystem? = nil, preferredGPS: DriveLineGPSPreference? = nil,
                configuredSources: [DriveLineVehicleSource] = [], isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.year = year
        self.make = make
        self.model = model
        self.vehicleClass = vehicleClass
        self.fuelType = fuelType
        self.vin = vin
        self.preferredUnits = preferredUnits
        self.preferredGPS = preferredGPS
        self.configuredSources = configuredSources
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, year, make, model, vehicleClass, fuelType, vin
        case preferredUnits, preferredGPS, configuredSources, isArchived
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        year = try values.decodeIfPresent(String.self, forKey: .year)
        make = try values.decodeIfPresent(String.self, forKey: .make)
        model = try values.decodeIfPresent(String.self, forKey: .model)
        vehicleClass = try values.decodeIfPresent(DriveLineVehicleClass.self, forKey: .vehicleClass)
        fuelType = try values.decodeIfPresent(String.self, forKey: .fuelType)
        vin = try values.decodeIfPresent(String.self, forKey: .vin)
        preferredUnits = try values.decodeIfPresent(DriveLineUnitSystem.self, forKey: .preferredUnits)
        preferredGPS = try values.decodeIfPresent(DriveLineGPSPreference.self, forKey: .preferredGPS)
        configuredSources = try values.decodeIfPresent([DriveLineVehicleSource].self, forKey: .configuredSources) ?? []
        isArchived = try values.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

public enum DriveLineVehicleClass: String, Codable, CaseIterable, Sendable {
    case passengerCar
    case lightTruck
    case motorcycle
    case heavyTruck
    case van
    case other
}

public enum DriveLineUnitSystem: String, Codable, CaseIterable, Sendable {
    case metric
    case usCustomary
    case imperial
}

public enum DriveLineGPSPreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case phone
    case imported
    case unavailable
}

public enum DriveLineVehicleSource: String, Codable, CaseIterable, Sendable {
    case phoneGPS
    case obdScanner
    case importedArchive
    case manual
}

public struct DriveLineVehicleIdentityObservation: Codable, Equatable, Sendable {
    public var source: String
    public var respondingAddress: String?
    public var protocolName: String?
    public var observedAt: Date

    public init(source: String, respondingAddress: String? = nil,
                protocolName: String? = nil, observedAt: Date) {
        self.source = source
        self.respondingAddress = respondingAddress
        self.protocolName = protocolName
        self.observedAt = observedAt
    }
}

public struct DriveLineVINResult: Equatable, Sendable {
    public var normalizedVIN: String
    public var candidateModelYears: [Int]
    public var suggestedModelYear: Int?
    public var manufacturer: String?
    public var checksumValidated: Bool

    public var modelYearIsAmbiguous: Bool { suggestedModelYear == nil && candidateModelYears.count > 1 }

    public init(normalizedVIN: String, candidateModelYears: [Int], suggestedModelYear: Int?,
                manufacturer: String?, checksumValidated: Bool) {
        self.normalizedVIN = normalizedVIN
        self.candidateModelYears = candidateModelYears
        self.suggestedModelYear = suggestedModelYear
        self.manufacturer = manufacturer
        self.checksumValidated = checksumValidated
    }
}

/// Offline VIN evidence only. This decoder intentionally limits itself to facts
/// supported by standardized VIN positions and a small, tested WMI registry.
public enum DriveLineVINDecoder {
    private static let allowed = Set("ABCDEFGHJKLMNPRSTUVWXYZ0123456789")
    private static let yearCodes = Array("ABCDEFGHJKLMNPRSTVWXY123456789")
    private static let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]
    private static let transliteration: [Character: Int] = [
        "A":1,"B":2,"C":3,"D":4,"E":5,"F":6,"G":7,"H":8,
        "J":1,"K":2,"L":3,"M":4,"N":5,"P":7,"R":9,
        "S":2,"T":3,"U":4,"V":5,"W":6,"X":7,"Y":8,"Z":9
    ]
    private static let manufacturers: [String: String] = [
        "1VW":"Volkswagen", "3VW":"Volkswagen", "WVW":"Volkswagen", "9BW":"Volkswagen"
    ]

    public static func normalized(_ input: String) throws -> String {
        let value = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard value.count == 17, value.allSatisfy({ allowed.contains($0) }) else {
            throw DriveLineContractError.invalid("A standard VIN has 17 letters and numbers, without I, O or Q.")
        }
        return value
    }

    public static func decode(_ input: String, enteredModelYear: Int? = nil,
                              currentYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())) throws -> DriveLineVINResult {
        let vin = try normalized(input)
        let characters = Array(vin)
        let checksumRequired = characters.first.map { "12345".contains($0) } ?? false
        if checksumRequired && !checksumIsValid(vin) {
            throw DriveLineContractError.invalid("The VIN checksum is invalid. Keep the entered vehicle details and retry the complete Mode 09 response.")
        }
        let candidates = modelYears(code: characters[9], currentYear: currentYear)
        let suggested: Int?
        if candidates.count == 1 {
            suggested = candidates.first
        } else if let enteredModelYear {
            let distances = candidates.map { (year: $0, distance: abs($0 - enteredModelYear)) }.sorted { $0.distance < $1.distance }
            if let first = distances.first, first.distance <= 5,
               distances.dropFirst().first.map({ $0.distance != first.distance }) ?? true {
                suggested = first.year
            } else {
                suggested = nil
            }
        } else {
            suggested = nil
        }
        let wmi = String(characters.prefix(3))
        return DriveLineVINResult(normalizedVIN: vin, candidateModelYears: candidates,
                                  suggestedModelYear: suggested, manufacturer: manufacturers[wmi],
                                  checksumValidated: checksumRequired)
    }

    public static func checksumIsValid(_ input: String) -> Bool {
        guard let vin = try? normalized(input) else { return false }
        let characters = Array(vin)
        var total = 0
        for (index, character) in characters.enumerated() {
            let value: Int
            if let digit = character.wholeNumberValue { value = digit }
            else if let mapped = transliteration[character] { value = mapped }
            else { return false }
            total += value * weights[index]
        }
        let remainder = total % 11
        let expected: Character = remainder == 10 ? "X" : Character(String(remainder))
        return characters[8] == expected
    }

    public static func modelYears(code: Character, currentYear: Int) -> [Int] {
        guard let offset = yearCodes.firstIndex(of: code) else { return [] }
        var years: [Int] = []
        var year = 1980 + offset
        while year <= currentYear + 2 {
            years.append(year)
            year += 30
        }
        return years
    }
}

public struct DriveLineGPSPoint: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracyM: Double?
    public var speedMps: Double?
    public var sourceID: String

    public init(timestamp: Date, latitude: Double, longitude: Double,
                horizontalAccuracyM: Double? = nil, speedMps: Double? = nil,
                sourceID: String = "gps") {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyM = horizontalAccuracyM
        self.speedMps = speedMps
        self.sourceID = sourceID
    }

    public var isValid: Bool {
        timestamp.timeIntervalSince1970.isFinite && latitude.isFinite && longitude.isFinite &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
        (horizontalAccuracyM.map { $0.isFinite && $0 >= 0 } ?? true) &&
        (speedMps.map { $0.isFinite && $0 >= 0 } ?? true)
    }
}

public struct DriveLineSignalSample: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var values: [String: Double]
    public var sourceID: String
    public var command: String?
    public var reply: String?
    public var requestHeader: String?
    public var responseHeader: String?

    public init(timestamp: Date, values: [String: Double], sourceID: String = "obd",
                command: String? = nil, reply: String? = nil,
                requestHeader: String? = nil, responseHeader: String? = nil) {
        self.timestamp = timestamp
        self.values = values
        self.sourceID = sourceID
        self.command = command
        self.reply = reply
        self.requestHeader = requestHeader
        self.responseHeader = responseHeader
    }
}

public struct DriveLineTripEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var endTimestamp: Date?
    public var kind: String
    public var note: String?
    public var sourceID: String?
    public var severity: DriveLineEventSeverity?
    public var confidence: Double?
    public var algorithmIdentifier: String?
    public var algorithmVersion: String?
    public var evidenceReferences: [String]

    public init(id: UUID = UUID(), timestamp: Date, endTimestamp: Date? = nil,
                kind: String, note: String? = nil, sourceID: String? = nil,
                severity: DriveLineEventSeverity? = nil, confidence: Double? = nil,
                algorithmIdentifier: String? = nil, algorithmVersion: String? = nil,
                evidenceReferences: [String] = []) {
        self.id = id
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.kind = kind
        self.note = note
        self.sourceID = sourceID
        self.severity = severity
        self.confidence = confidence
        self.algorithmIdentifier = algorithmIdentifier
        self.algorithmVersion = algorithmVersion
        self.evidenceReferences = evidenceReferences
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, endTimestamp, kind, note, sourceID, severity, confidence
        case algorithmIdentifier, algorithmVersion, evidenceReferences
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try values.decode(Date.self, forKey: .timestamp)
        endTimestamp = try values.decodeIfPresent(Date.self, forKey: .endTimestamp)
        kind = try values.decode(String.self, forKey: .kind)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        sourceID = try values.decodeIfPresent(String.self, forKey: .sourceID)
        severity = try values.decodeIfPresent(DriveLineEventSeverity.self, forKey: .severity)
        confidence = try values.decodeIfPresent(Double.self, forKey: .confidence)
        algorithmIdentifier = try values.decodeIfPresent(String.self, forKey: .algorithmIdentifier)
        algorithmVersion = try values.decodeIfPresent(String.self, forKey: .algorithmVersion)
        evidenceReferences = try values.decodeIfPresent([String].self, forKey: .evidenceReferences) ?? []
    }
}

public enum DriveLineEventSeverity: String, Codable, CaseIterable, Sendable {
    case information
    case attention
    case fault
}

public struct DriveLineReceiptMetadata: Codable, Equatable, Sendable {
    public var fileName: String
    public var mediaType: String
    public var byteCount: Int
    public var sha256: String
    public var capturedAt: Date?

    public init(fileName: String, mediaType: String, byteCount: Int, sha256: String, capturedAt: Date? = nil) {
        self.fileName = fileName
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.sha256 = sha256
        self.capturedAt = capturedAt
    }
}

public enum DriveLineOdometerSourceType: String, Codable, CaseIterable, Sendable {
    case scanned
    case manual
    case fuelEntry
}

/// Evidence for the odometer value saved with a fuel entry. Older archives do
/// not contain this additive field and continue to decode with nil provenance.
public struct DriveLineOdometerProvenance: Codable, Equatable, Sendable {
    public var valueKm: Double
    public var observedAt: Date
    public var sourceIdentifier: String
    public var recordingID: UUID?
    public var sourceType: DriveLineOdometerSourceType

    public init(valueKm: Double, observedAt: Date, sourceIdentifier: String,
                recordingID: UUID? = nil, sourceType: DriveLineOdometerSourceType) {
        self.valueKm = valueKm
        self.observedAt = observedAt
        self.sourceIdentifier = sourceIdentifier
        self.recordingID = recordingID
        self.sourceType = sourceType
    }
}

public enum DriveLineStationSourceType: String, Codable, CaseIterable, Sendable {
    case currentLocation
    case manual
}

public struct DriveLineStationProvenance: Codable, Equatable, Sendable {
    public var observedAt: Date
    public var sourceIdentifier: String
    public var sourceType: DriveLineStationSourceType

    public init(observedAt: Date, sourceIdentifier: String,
                sourceType: DriveLineStationSourceType) {
        self.observedAt = observedAt
        self.sourceIdentifier = sourceIdentifier
        self.sourceType = sourceType
    }
}

public struct DriveLineFuelEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var vehicleID: UUID
    public var date: Date
    public var litresPurchased: Double
    public var totalCost: Double
    public var currencyCode: String
    public var odometerKm: Double
    public var isFullFill: Bool
    public var stationName: String?
    public var stationAddress: String?
    public var odometerProvenance: DriveLineOdometerProvenance?
    public var stationProvenance: DriveLineStationProvenance?
    public var notes: String?
    public var receipt: DriveLineReceiptMetadata?
    public var isSample: Bool

    public init(id: UUID = UUID(), vehicleID: UUID, date: Date, litresPurchased: Double,
                totalCost: Double, currencyCode: String = "CAD", odometerKm: Double,
                isFullFill: Bool, stationName: String? = nil, stationAddress: String? = nil,
                odometerProvenance: DriveLineOdometerProvenance? = nil,
                stationProvenance: DriveLineStationProvenance? = nil, notes: String? = nil,
                receipt: DriveLineReceiptMetadata? = nil, isSample: Bool = false) {
        self.id = id
        self.vehicleID = vehicleID
        self.date = date
        self.litresPurchased = litresPurchased
        self.totalCost = totalCost
        self.currencyCode = currencyCode
        self.odometerKm = odometerKm
        self.isFullFill = isFullFill
        self.stationName = stationName
        self.stationAddress = stationAddress
        self.odometerProvenance = odometerProvenance
        self.stationProvenance = stationProvenance
        self.notes = notes
        self.receipt = receipt
        self.isSample = isSample
    }
}

public struct DriveLineCoverageSummary: Codable, Equatable, Sendable {
    public var key: String
    public var observedSeconds: Double
    public var recordingSeconds: Double
    public var fraction: Double
    public var firstObservation: Date?
    public var lastObservation: Date?
    public var sourceIDs: [String]

    public init(key: String, observedSeconds: Double, recordingSeconds: Double,
                fraction: Double, firstObservation: Date?, lastObservation: Date?, sourceIDs: [String]) {
        self.key = key
        self.observedSeconds = observedSeconds
        self.recordingSeconds = recordingSeconds
        self.fraction = fraction
        self.firstObservation = firstObservation
        self.lastObservation = lastObservation
        self.sourceIDs = sourceIDs
    }
}

public struct DriveLineRecording: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { recordingID }
    public var recordingID: UUID
    public var vehicleID: UUID
    public var name: String
    public var startedAt: Date
    public var endedAt: Date
    public var sourceIDs: [String]
    public var gpsPoints: [DriveLineGPSPoint]
    public var signalSamples: [DriveLineSignalSample]
    public var notes: String?
    public var events: [DriveLineTripEvent]
    public var recordedDistanceKm: Double?
    public var tripFuelLitres: Double?
    public var coverage: [DriveLineCoverageSummary]
    public var isSample: Bool
    public var metadata: [String: String]

    public init(recordingID: UUID, vehicleID: UUID, name: String, startedAt: Date,
                endedAt: Date, sourceIDs: [String], gpsPoints: [DriveLineGPSPoint] = [],
                signalSamples: [DriveLineSignalSample] = [], notes: String? = nil,
                events: [DriveLineTripEvent] = [], recordedDistanceKm: Double? = nil, tripFuelLitres: Double? = nil,
                coverage: [DriveLineCoverageSummary] = [], isSample: Bool = false) {
        self.recordingID = recordingID
        self.vehicleID = vehicleID
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceIDs = sourceIDs
        self.gpsPoints = gpsPoints
        self.signalSamples = signalSamples
        self.notes = notes
        self.events = events
        self.recordedDistanceKm = recordedDistanceKm
        self.tripFuelLitres = tripFuelLitres
        self.coverage = coverage
        self.isSample = isSample
        self.metadata = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case recordingID, vehicleID, name, startedAt, endedAt, sourceIDs, gpsPoints, signalSamples
        case notes, events, recordedDistanceKm, tripFuelLitres, coverage, isSample, metadata
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        recordingID = try values.decode(UUID.self,forKey:.recordingID)
        vehicleID = try values.decode(UUID.self,forKey:.vehicleID)
        name = try values.decode(String.self,forKey:.name)
        startedAt = try values.decode(Date.self,forKey:.startedAt)
        endedAt = try values.decode(Date.self,forKey:.endedAt)
        sourceIDs = try values.decodeIfPresent([String].self,forKey:.sourceIDs) ?? []
        gpsPoints = try values.decodeIfPresent([DriveLineGPSPoint].self,forKey:.gpsPoints) ?? []
        signalSamples = try values.decodeIfPresent([DriveLineSignalSample].self,forKey:.signalSamples) ?? []
        notes = try values.decodeIfPresent(String.self,forKey:.notes)
        events = try values.decodeIfPresent([DriveLineTripEvent].self,forKey:.events) ?? []
        recordedDistanceKm = try values.decodeIfPresent(Double.self,forKey:.recordedDistanceKm)
        tripFuelLitres = try values.decodeIfPresent(Double.self,forKey:.tripFuelLitres)
        coverage = try values.decodeIfPresent([DriveLineCoverageSummary].self,forKey:.coverage) ?? []
        isSample = try values.decodeIfPresent(Bool.self,forKey:.isSample) ?? false
        metadata = try values.decodeIfPresent([String:String].self,forKey:.metadata) ?? [:]
    }
}

public struct DriveLineArchive: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var producer: DriveLineProducer
    public var sources: [DriveLineSourceDescriptor]
    public var vehicles: [DriveLineVehicle]
    public var recordings: [DriveLineRecording]
    public var fuelEntries: [DriveLineFuelEntry]
    /// Receipt payloads keyed by their lowercase SHA-256 digest. Production
    /// stores keep these bytes outside their primary state and add them only
    /// to complete archives.
    public var receiptFiles: [String: Data]
    public var extensionData: [String: Data]

    public init(schemaVersion: Int = currentSchemaVersion, producer: DriveLineProducer,
                sources: [DriveLineSourceDescriptor], vehicles: [DriveLineVehicle] = [],
                recordings: [DriveLineRecording], fuelEntries: [DriveLineFuelEntry] = [],
                receiptFiles: [String: Data] = [:],
                extensionData: [String: Data] = [:]) {
        self.schemaVersion = schemaVersion
        self.producer = producer
        self.sources = sources
        self.vehicles = vehicles
        self.recordings = recordings
        self.fuelEntries = fuelEntries
        self.receiptFiles = receiptFiles
        self.extensionData = extensionData
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, producer, sources, vehicles, recordings, fuelEntries, receiptFiles, extensionData
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        schemaVersion = try values.decode(Int.self,forKey:.schemaVersion)
        producer = try values.decode(DriveLineProducer.self,forKey:.producer)
        sources = try values.decodeIfPresent([DriveLineSourceDescriptor].self,forKey:.sources) ?? []
        vehicles = try values.decodeIfPresent([DriveLineVehicle].self,forKey:.vehicles) ?? []
        recordings = try values.decodeIfPresent([DriveLineRecording].self,forKey:.recordings) ?? []
        fuelEntries = try values.decodeIfPresent([DriveLineFuelEntry].self,forKey:.fuelEntries) ?? []
        receiptFiles = try values.decodeIfPresent([String:Data].self,forKey:.receiptFiles) ?? [:]
        extensionData = try values.decodeIfPresent([String:Data].self,forKey:.extensionData) ?? [:]
    }

    public func encoded() throws -> Data {
        try DriveLinePerformance.measure("Archive export") {
            guard schemaVersion == Self.currentSchemaVersion else {
                throw DriveLineContractError.invalid("Only DriveLine archive schema version 2 can be encoded.")
            }
            try validate()
            return try DriveLineJSON.encoder().encode(self)
        }
    }

    public static func decoded(_ data: Data, fallbackVehicleID: UUID? = nil,
                               fallbackRecordingID: UUID? = nil) throws -> DriveLineArchive {
        try DriveLinePerformance.measure("Archive import") {
            guard data.count <= 100 * 1024 * 1024 else {
                throw DriveLineContractError.invalid("DriveLine archive exceeds 100 MB.")
            }
            let object = try JSONSerialization.jsonObject(with: data)
            if let envelope = object as? [String: Any], (envelope["schemaVersion"] as? NSNumber)?.intValue == 2 {
                let archive = try DriveLineJSON.decoder().decode(DriveLineArchive.self, from: data)
                try archive.validate()
                return archive
            }
            return try migrateVersion1(object, fallbackVehicleID: fallbackVehicleID,
                                       fallbackRecordingID: fallbackRecordingID)
        }
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DriveLineContractError.invalid("Unsupported DriveLine archive schema version \(schemaVersion).")
        }
        guard Set(recordings.map(\.recordingID)).count == recordings.count,
              Set(fuelEntries.map(\.id)).count == fuelEntries.count,
              Set(vehicles.map(\.id)).count == vehicles.count,
              Set(sources.map(\.id)).count == sources.count else {
            throw DriveLineContractError.invalid("Duplicate stable identifiers in DriveLine archive.")
        }
        let vehicleIDs = Set(vehicles.map(\.id))
        let sourceIDs = Set(sources.map(\.id))
        guard receiptFiles.count <= 1_000,
              receiptFiles.reduce(0, { $0 + $1.value.count }) <= 80 * 1024 * 1024,
              receiptFiles.allSatisfy({ digest,data in
                  digest.count == 64 && digest.allSatisfy(\.isHexDigit) && data.count <= 20 * 1024 * 1024
              }) else {
            throw DriveLineContractError.invalid("Invalid receipt attachments in DriveLine archive.")
        }
        guard recordings.allSatisfy({ vehicleIDs.contains($0.vehicleID) }),
              fuelEntries.allSatisfy({ vehicleIDs.contains($0.vehicleID) }),
              recordings.allSatisfy({ Set($0.sourceIDs).isSubset(of:sourceIDs) &&
                  Set($0.gpsPoints.map(\.sourceID)).isSubset(of:sourceIDs) &&
                  Set($0.signalSamples.map(\.sourceID)).isSubset(of:sourceIDs) }) else {
            throw DriveLineContractError.invalid("Every recording, fuel entry, and observation must reference declared stable identities.")
        }
        for recording in recordings {
            guard vehicleIDs.contains(recording.vehicleID), !recording.name.isEmpty,
                  recording.endedAt >= recording.startedAt,
                  recording.gpsPoints.allSatisfy(\.isValid),
                  recording.signalSamples.allSatisfy({ sample in
                      sample.timestamp.timeIntervalSince1970.isFinite && !sample.values.isEmpty &&
                      sample.values.allSatisfy { !$0.key.isEmpty && $0.value.isFinite }
                  }),
                  recording.recordedDistanceKm.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  recording.tripFuelLitres.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  recording.events.allSatisfy({ event in
                      event.timestamp.timeIntervalSince1970.isFinite && !event.kind.isEmpty &&
                      (event.endTimestamp.map { $0 >= event.timestamp && $0.timeIntervalSince1970.isFinite } ?? true) &&
                      (event.confidence.map { $0.isFinite && (0...1).contains($0) } ?? true)
                  }) else {
                throw DriveLineContractError.invalid("Invalid recording values in DriveLine archive.")
            }
        }
        for fill in fuelEntries {
            guard fill.litresPurchased.isFinite, fill.litresPurchased > 0,
                  fill.totalCost.isFinite, fill.totalCost >= 0,
                  fill.odometerKm.isFinite, fill.odometerKm >= 0,
                  fill.date.timeIntervalSince1970.isFinite,
                  (fill.stationName?.count ?? 0) <= 120,
                  (fill.stationAddress?.count ?? 0) <= 240,
                  fill.odometerProvenance.map({ provenance in
                      provenance.valueKm.isFinite && provenance.valueKm >= 0 &&
                      provenance.observedAt.timeIntervalSince1970.isFinite &&
                      !provenance.sourceIdentifier.isEmpty && provenance.sourceIdentifier.count <= 120
                  }) ?? true,
                  fill.stationProvenance.map({ provenance in
                      provenance.observedAt.timeIntervalSince1970.isFinite &&
                      !provenance.sourceIdentifier.isEmpty && provenance.sourceIdentifier.count <= 120
                  }) ?? true,
                  fill.receipt.map({ receipt in
                      receipt.byteCount >= 0 && !receipt.fileName.isEmpty && !receipt.mediaType.isEmpty &&
                      receipt.sha256.count == 64 && receipt.sha256.allSatisfy(\.isHexDigit)
                  }) ?? true,
                  fill.currencyCode.count == 3,
                  fill.currencyCode.allSatisfy({ $0.isASCII && $0.isLetter }) else {
                throw DriveLineContractError.invalid("Invalid fuel entry in DriveLine archive.")
            }
            if let receipt=fill.receipt,let bytes=receiptFiles[receipt.sha256.lowercased()] {
                let digest=SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
                guard bytes.count == receipt.byteCount,digest == receipt.sha256.lowercased() else {
                    throw DriveLineContractError.invalid("Receipt metadata does not match its archived attachment.")
                }
            }
        }
    }

    private static func migrateVersion1(_ object: Any, fallbackVehicleID: UUID?,
                                        fallbackRecordingID: UUID?) throws -> DriveLineArchive {
        guard let envelope = object as? [String: Any],
              (envelope["schemaVersion"] as? NSNumber)?.intValue == 1 else {
            throw DriveLineContractError.invalid("Unsupported DriveLine archive schema.")
        }
        let rawTrips = envelope["trips"] as? [[String: Any]] ?? [envelope]
        var recordings: [DriveLineRecording] = []
        for (index, trip) in rawTrips.enumerated() {
            let recordingID = uuid(trip["recordingID"] ?? trip["id"]) ?? (index == 0 ? fallbackRecordingID : nil)
            let vehicleID = uuid(trip["vehicleID"] ?? envelope["vehicleID"]) ?? fallbackVehicleID
            guard let recordingID, let vehicleID else {
                throw DriveLineContractError.invalid("Version-1 migration needs stable recordingID and vehicleID values.")
            }
            let rows = trip["samples"] as? [[String: Any]] ?? []
            var gps: [DriveLineGPSPoint] = []
            var signals: [DriveLineSignalSample] = []
            for row in rows {
                guard let timestamp = timestamp(row["timestamp"]) else { continue }
                if let latitude = number(row["latitude"]), let longitude = number(row["longitude"]) {
                    gps.append(DriveLineGPSPoint(timestamp: timestamp, latitude: latitude, longitude: longitude,
                        horizontalAccuracyM: number(row["accuracy"]), speedMps: number(row["gpsSpeedMps"])))
                }
                let values = (row["signals"] as? [String: Any] ?? [:]).compactMapValues(number)
                if !values.isEmpty {
                    signals.append(DriveLineSignalSample(timestamp:timestamp,values:values,command:row["command"] as? String,
                                                         reply:row["reply"] as? String,requestHeader:row["obdRequestHeader"] as? String,
                                                         responseHeader:row["obdResponseHeader"] as? String))
                }
            }
            let started = timestamp(trip["startedAt"]) ?? (gps.map(\.timestamp) + signals.map(\.timestamp)).min() ?? .distantPast
            let duration = number(trip["duration"]) ?? 0
            let ended = timestamp(trip["endedAt"]) ?? (gps.map(\.timestamp) + signals.map(\.timestamp)).max() ?? started.addingTimeInterval(duration)
            let source = trip["source"] as? String ?? "Version 1 import"
            let sourceIDs=Array(Set((gps.isEmpty ? [] : ["gps"])+(signals.isEmpty ? [] : ["obd"]))).sorted()
            var recording = DriveLineRecording(recordingID: recordingID, vehicleID: vehicleID,
                name: trip["name"] as? String ?? "Imported recording", startedAt: started, endedAt: max(started, ended),
                sourceIDs:sourceIDs, gpsPoints: gps,
                signalSamples: signals, recordedDistanceKm:number(trip["distanceKM"]),tripFuelLitres: number(trip["fuelLitres"]),
                isSample: trip["isSample"] as? Bool ?? false)
            recording.metadata["legacySource"]=source
            recording.coverage = DriveLineMetricPolicy.coverageSummaries(recording)
            recordings.append(recording)
        }
        let sourceIDs = Set(recordings.flatMap(\.sourceIDs))
        let sources = sourceIDs.sorted().map { id in
            DriveLineSourceDescriptor(id: id, kind: id == "gps" ? .gps : .obd,
                                      name: id == "gps" ? "iPhone GPS" : "OBD scanner")
        }
        let vehicles = Set(recordings.map(\.vehicleID)).sorted { $0.uuidString < $1.uuidString }.map {
            DriveLineVehicle(id:$0,name:"Migrated vehicle")
        }
        let archive = DriveLineArchive(producer: DriveLineProducer(app: "DriveLine legacy importer", version: "1", platform: "legacy"),
                                       sources: sources, vehicles:vehicles, recordings: recordings)
        try archive.validate()
        return archive
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue.isFinite ? number.doubleValue : nil }
        if let string = value as? String, let number = Double(string), number.isFinite { return number }
        return nil
    }

    private static func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap(UUID.init(uuidString:))
    }

    private static func timestamp(_ value: Any?) -> Date? {
        if let number = number(value) {
            let seconds = number > 100_000_000_000 ? number / 1000 : number
            guard (946_684_800...7_258_118_400).contains(seconds) else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        return (value as? String).flatMap(DriveLineJSON.date)
    }
}
