import Foundation
import CryptoKit
#if canImport(DriveLineShared)
import DriveLineShared
#endif

public final class LibraryRepository {
    public let root: URL
    public var originals: URL { root.appendingPathComponent("Originals", isDirectory: true) }
    public var receiptFiles:URL { root.appendingPathComponent("Receipts",isDirectory:true) }
    public var manifest: URL { root.appendingPathComponent("library.json") }
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at:receiptFiles,withIntermediateDirectories:true)
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
    public func receiptURL(_ metadata:DriveLineReceiptMetadata)->URL { receiptFiles.appendingPathComponent(metadata.sha256.lowercased()) }
    public func receiptData(_ metadata:DriveLineReceiptMetadata)->Data? {
        guard let data=try? Data(contentsOf:receiptURL(metadata)),data.count==metadata.byteCount,
              SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==metadata.sha256.lowercased() else { return nil }
        return data
    }
    public func archivedReceiptFiles(_ entries:[FuelEntry])->[String:Data] {
        entries.reduce(into:[String:Data]()) { result,entry in
            guard let metadata=entry.receipt,let data=receiptData(metadata) else { return }
            result[metadata.sha256.lowercased()]=data
        }
    }
    public func storeReceiptFiles(_ files:[String:Data],for entries:[FuelEntry]) throws {
        var metadata:[String:DriveLineReceiptMetadata]=[:]
        for value in entries.compactMap(\.receipt) {
            let digest=value.sha256.lowercased()
            if let existing=metadata[digest],existing.byteCount != value.byteCount { throw CANError.invalid("Duplicate receipt metadata disagrees about the file size.") }
            metadata[digest]=value
        }
        for (digest,data) in files {
            guard let value=metadata[digest.lowercased()],value.byteCount==data.count,
                  SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==digest.lowercased() else {
                throw CANError.invalid("Receipt attachment does not match its metadata.")
            }
            let destination=receiptURL(value)
            if FileManager.default.fileExists(atPath:destination.path) {
                guard try Data(contentsOf:destination)==data else { throw CANError.invalid("A different receipt already uses this content hash.") }
            } else { try data.write(to:destination,options:.atomic) }
        }
    }
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
    public static func json(_ trip: Trip, fuelEntries:[FuelEntry] = [],receiptFiles:[String:Data] = [:]) throws -> Data {
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
                                    recordings:[recording],fuelEntries:fills,receiptFiles:receiptFiles).encoded()
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
