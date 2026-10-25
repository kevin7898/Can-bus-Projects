import Foundation
#if canImport(DriveLineShared)
import DriveLineShared
#endif

public final class LibraryRepository {
    public let root: URL
    public var originals: URL { root.appendingPathComponent("Originals", isDirectory: true) }
    public var manifest: URL { root.appendingPathComponent("library.json") }
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
    }
    public func load() throws -> LibraryState {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return LibraryState() }
        let result = try Self.decoder().decode(LibraryState.self, from: Data(contentsOf: manifest))
        guard (1...3).contains(result.schemaVersion) else { throw CANError.invalid("This library uses an unsupported schema. Keep the original file and update the app.") }
        var migrated=result;migrated.schemaVersion=3
        return migrated
    }
    public func save(_ state: LibraryState) throws {
        let data = try Self.encoder().encode(state)
        try data.write(to: manifest, options: .atomic)
    }
    public func originalURL(_ receipt: ImportReceipt) -> URL { originals.appendingPathComponent(receipt.archiveName) }
    public func backup(to destination: URL) throws -> URL {
        let folder = destination.appendingPathComponent("CAN-Connect-Backup-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.copyItem(at: root, to: folder)
        return folder
    }
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .secondsSince1970; return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }
}

public enum TripExport {
    public static func json(_ trip: Trip, fuelEntries:[FuelEntry] = []) throws -> Data {
        var recording = trip.sharedRecording
        recording.coverage = DriveLineMetricPolicy.coverageSummaries(recording)
        let sources = recording.sourceIDs.map { id -> DriveLineSourceDescriptor in
            switch id {
            case "gps": return DriveLineSourceDescriptor(id:id,kind:.gps,name:"Recorded GPS")
            case "obd": return DriveLineSourceDescriptor(id:id,kind:.obd,name:"Recorded vehicle signals",detail:trip.source)
            case "synthetic": return DriveLineSourceDescriptor(id:id,kind:.synthetic,name:"Labelled synthetic source",detail:trip.source)
            default: return DriveLineSourceDescriptor(id:id,kind:.imported,name:"Imported recording",detail:trip.source)
            }
        }
        let fills=fuelEntries.filter { $0.vehicleID == trip.vehicleID }.map {
            DriveLineFuelEntry(id:$0.id,vehicleID:$0.vehicleID,date:$0.date,litresPurchased:$0.litresPurchased,
                               totalCost:$0.totalCost,currencyCode:$0.currencyCode,odometerKm:$0.odometerKm,
                               isFullFill:$0.isFullFill,stationName:$0.stationName,notes:$0.notes,receipt:$0.receipt,isSample:$0.isDemo)
        }
        return try DriveLineArchive(producer:DriveLineProducer(app:"DriveLine Mac",version:"2",platform:"macOS"),
                                    sources:sources,
                                    vehicles:[DriveLineVehicle(id:trip.vehicleID,name:"Recorded vehicle")],
                                    recordings:[recording],fuelEntries:fills).encoded()
    }
    public static func csv(_ trip: Trip) -> Data {
        let keys = trip.availableSignals
        var lines = [(["timestamp","latitude","longitude"] + keys.map(\.rawValue)).joined(separator: ",")]
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        for s in trip.samples {
            lines.append(([f.string(from:s.timestamp),s.latitude.map { String($0) } ?? "",s.longitude.map { String($0) } ?? ""] + keys.map { s.value($0).map { String($0) } ?? "" }).joined(separator:","))
        }
        return Data(lines.joined(separator:"\n").utf8)
    }
}
