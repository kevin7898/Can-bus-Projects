import Foundation

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
        guard result.schemaVersion == 1 else { throw CANError.invalid("This library uses an unsupported schema. Keep the original file and update the app.") }
        return result
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
    public static func json(_ trip: Trip) throws -> Data {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let samples = trip.samples.map { sample -> [String: Any] in
            var row: [String: Any] = ["timestamp": formatter.string(from: sample.timestamp), "signals": sample.signals]
            if sample.hasCoordinate { row["latitude"] = sample.latitude!; row["longitude"] = sample.longitude! }
            return row
        }
        return try JSONSerialization.data(withJSONObject: ["schemaVersion":1,"vehicleID":trip.vehicleID.uuidString,"name":trip.name,"source":trip.source,"samples":samples], options:[.prettyPrinted,.sortedKeys])
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
