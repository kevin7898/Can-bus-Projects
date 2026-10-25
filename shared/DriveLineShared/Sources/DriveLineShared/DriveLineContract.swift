import Foundation

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
            try container.encode(timestamp(date))
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

    public init(id: UUID, name: String, year: String? = nil, make: String? = nil, model: String? = nil) {
        self.id = id
        self.name = name
        self.year = year
        self.make = make
        self.model = model
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

    public init(timestamp: Date, values: [String: Double], sourceID: String = "obd") {
        self.timestamp = timestamp
        self.values = values
        self.sourceID = sourceID
    }
}

public struct DriveLineTripEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var kind: String
    public var note: String?

    public init(id: UUID = UUID(), timestamp: Date, kind: String, note: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.note = note
    }
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
    public var notes: String?
    public var receipt: DriveLineReceiptMetadata?
    public var isSample: Bool

    public init(id: UUID = UUID(), vehicleID: UUID, date: Date, litresPurchased: Double,
                totalCost: Double, currencyCode: String = "CAD", odometerKm: Double,
                isFullFill: Bool, stationName: String? = nil, notes: String? = nil,
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
    public var tripFuelLitres: Double?
    public var coverage: [DriveLineCoverageSummary]
    public var isSample: Bool

    public init(recordingID: UUID, vehicleID: UUID, name: String, startedAt: Date,
                endedAt: Date, sourceIDs: [String], gpsPoints: [DriveLineGPSPoint] = [],
                signalSamples: [DriveLineSignalSample] = [], notes: String? = nil,
                events: [DriveLineTripEvent] = [], tripFuelLitres: Double? = nil,
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
        self.tripFuelLitres = tripFuelLitres
        self.coverage = coverage
        self.isSample = isSample
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

    public init(schemaVersion: Int = currentSchemaVersion, producer: DriveLineProducer,
                sources: [DriveLineSourceDescriptor], vehicles: [DriveLineVehicle] = [],
                recordings: [DriveLineRecording], fuelEntries: [DriveLineFuelEntry] = []) {
        self.schemaVersion = schemaVersion
        self.producer = producer
        self.sources = sources
        self.vehicles = vehicles
        self.recordings = recordings
        self.fuelEntries = fuelEntries
    }

    public func encoded() throws -> Data {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DriveLineContractError.invalid("Only DriveLine archive schema version 2 can be encoded.")
        }
        try validate()
        return try DriveLineJSON.encoder().encode(self)
    }

    public static func decoded(_ data: Data, fallbackVehicleID: UUID? = nil,
                               fallbackRecordingID: UUID? = nil) throws -> DriveLineArchive {
        guard data.count <= 50 * 1024 * 1024 else {
            throw DriveLineContractError.invalid("DriveLine archive exceeds 50 MB.")
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

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DriveLineContractError.invalid("Unsupported DriveLine archive schema version \(schemaVersion).")
        }
        guard Set(recordings.map(\.recordingID)).count == recordings.count,
              Set(fuelEntries.map(\.id)).count == fuelEntries.count else {
            throw DriveLineContractError.invalid("Duplicate stable identifiers in DriveLine archive.")
        }
        let vehicleIDs = Set(vehicles.map(\.id)).union(recordings.map(\.vehicleID)).union(fuelEntries.map(\.vehicleID))
        for recording in recordings {
            guard vehicleIDs.contains(recording.vehicleID), !recording.name.isEmpty,
                  recording.endedAt >= recording.startedAt,
                  recording.gpsPoints.allSatisfy(\.isValid),
                  recording.signalSamples.allSatisfy({ sample in
                      sample.timestamp.timeIntervalSince1970.isFinite && !sample.values.isEmpty &&
                      sample.values.allSatisfy { !$0.key.isEmpty && $0.value.isFinite }
                  }),
                  recording.tripFuelLitres.map({ $0.isFinite && $0 >= 0 }) ?? true else {
                throw DriveLineContractError.invalid("Invalid recording values in DriveLine archive.")
            }
        }
        for fill in fuelEntries {
            guard fill.litresPurchased.isFinite, fill.litresPurchased > 0,
                  fill.totalCost.isFinite, fill.totalCost >= 0,
                  fill.odometerKm.isFinite, fill.odometerKm >= 0,
                  !fill.currencyCode.isEmpty else {
                throw DriveLineContractError.invalid("Invalid fuel entry in DriveLine archive.")
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
                if !values.isEmpty { signals.append(DriveLineSignalSample(timestamp: timestamp, values: values)) }
            }
            let started = timestamp(trip["startedAt"]) ?? (gps.map(\.timestamp) + signals.map(\.timestamp)).min() ?? .distantPast
            let duration = number(trip["duration"]) ?? 0
            let ended = timestamp(trip["endedAt"]) ?? (gps.map(\.timestamp) + signals.map(\.timestamp)).max() ?? started.addingTimeInterval(duration)
            let source = trip["source"] as? String ?? "Version 1 import"
            var recording = DriveLineRecording(recordingID: recordingID, vehicleID: vehicleID,
                name: trip["name"] as? String ?? "Imported recording", startedAt: started, endedAt: max(started, ended),
                sourceIDs: [source.lowercased().contains("gps") ? "gps" : "obd"], gpsPoints: gps,
                signalSamples: signals, tripFuelLitres: number(trip["fuelLitres"]),
                isSample: trip["isSample"] as? Bool ?? false)
            recording.coverage = DriveLineMetricPolicy.coverageSummaries(recording)
            recordings.append(recording)
        }
        let sourceIDs = Set(recordings.flatMap(\.sourceIDs))
        let sources = sourceIDs.sorted().map { id in
            DriveLineSourceDescriptor(id: id, kind: id == "gps" ? .gps : .obd,
                                      name: id == "gps" ? "iPhone GPS" : "OBD scanner")
        }
        let archive = DriveLineArchive(producer: DriveLineProducer(app: "DriveLine legacy importer", version: "1", platform: "legacy"),
                                       sources: sources, recordings: recordings)
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
