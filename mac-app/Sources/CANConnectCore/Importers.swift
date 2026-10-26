import Foundation
#if canImport(DriveLineShared)
import DriveLineShared
#endif

public struct ImportResult: Sendable {
    public var trips: [Trip]
    public var fuelEntries:[FuelEntry]
    public var receiptFiles:[String:Data]
    public var message: String
    public init(trips: [Trip], fuelEntries:[FuelEntry] = [],receiptFiles:[String:Data] = [:], message: String) { self.trips = trips; self.fuelEntries=fuelEntries;self.receiptFiles=receiptFiles; self.message = message }
}

public enum RecordingImporter {
    public static let maxBytes = 100 * 1024 * 1024
    public static func parse(url: URL, vehicleID: UUID, receiptID: UUID) throws -> ImportResult {
        let ext = url.pathExtension.lowercased()
        if ext == "sqlite" || ext == "db" { return try PelicanImporter.parse(database: url, vehicleID:vehicleID, receiptID:receiptID) }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath:url.path, isDirectory:&isDirectory), isDirectory.boolValue {
            return try PelicanImporter.parse(database:url.appendingPathComponent("db.sqlite"),vehicleID:vehicleID,receiptID:receiptID)
        }
        let data = try Data(contentsOf: url, options:.mappedIfSafe)
        guard data.count <= maxBytes else { throw CANError.invalid("Recording exceeds the 50 MB import limit. Split this recording before importing.") }
        return try parse(data:data, name:url.lastPathComponent,vehicleID:vehicleID,receiptID:receiptID)
    }
    public static func parse(data: Data, name: String, vehicleID: UUID, receiptID: UUID) throws -> ImportResult {
        guard data.count <= maxBytes else { throw CANError.invalid("Recording exceeds 100 MB.") }
        guard var text = String(data:data,encoding:.utf8) else { throw CANError.invalid("This file is not UTF-8 telemetry text. Import Pelican .scanlogs folders or their ZIP archive using the file picker.") }
        text = text.replacingOccurrences(of:"\u{FEFF}",with:"")
        let clean = text.trimmingCharacters(in:.whitespacesAndNewlines)
        if clean.first == "{" || clean.first == "[" { return try parseJSON(data:data,name:name,vehicleID:vehicleID,receiptID:receiptID) }
        if clean.first == "(" { return try parseCandump(text,name:name,vehicleID:vehicleID,receiptID:receiptID) }
        return try parseCSV(text,name:name,vehicleID:vehicleID,receiptID:receiptID)
    }
    public static func parseDate(_ value: Any?) -> Date? {
        if let n = value as? NSNumber { return epoch(n.doubleValue) }
        guard let s = value as? String else { return nil }
        if let n = Double(s.trimmingCharacters(in:.whitespaces)) { return epoch(n) }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        if let d = f.date(from:s) { return d }
        f.formatOptions = [.withInternetDateTime]; if let d = f.date(from:s) { return d }
        // Human-readable exports without an offset are interpreted in the Mac's local time zone.
        for format in ["yyyy-MM-dd HH:mm:ss.SSS","yyyy-MM-dd HH:mm:ss","MM/dd/yyyy HH:mm:ss.SSS","dd.MM.yyyy HH:mm:ss.SSS"] {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.dateFormat = format; formatter.isLenient = false
            if let d = formatter.date(from:s) { return d }
        }
        return nil
    }
    private static func epoch(_ n: Double) -> Date? {
        guard n.isFinite else { return nil }
        let seconds = n > 100_000_000_000 ? n/1000 : n
        // Relative times must be anchored by the producer, never silently treated as absolute dates.
        guard (946684800...7258118400).contains(seconds) else { return nil }
        return Date(timeIntervalSince1970:seconds)
    }
    public static func number(_ s: String?) -> Double? {
        guard let s = s, !s.isEmpty else { return nil }
        let v = Double(s.trimmingCharacters(in:.whitespaces).replacingOccurrences(of:",",with:"."))
        return v.flatMap { $0.isFinite ? $0 : nil }
    }
    static func validSample(_ timestamp: Date, latitude: Double?, longitude: Double?, signals: [String:Double]) -> TelemetrySample {
        let valid = latitude.map { (-90...90).contains($0) } == true && longitude.map { (-180...180).contains($0) } == true
        return TelemetrySample(timestamp:timestamp,latitude:valid ? latitude:nil,longitude:valid ? longitude:nil,signals:signals)
    }
    static func parseJSON(data: Data, name: String, vehicleID: UUID, receiptID: UUID) throws -> ImportResult {
        let object = try JSONSerialization.jsonObject(with:data)
        let envelope = object as? [String:Any]
        if let schema = envelope?["schemaVersion"] as? Int, schema == 2 {
            let archive = try DriveLineArchive.decoded(data,fallbackVehicleID:vehicleID)
            guard archive.recordings.allSatisfy({$0.vehicleID == vehicleID}),
                  archive.fuelEntries.allSatisfy({$0.vehicleID == vehicleID}) else {
                throw CANError.invalid("The archive vehicleID does not match the selected vehicle.")
            }
            let trips = archive.recordings.map { recording in
                let gps = recording.gpsPoints.map { TelemetrySample(timestamp:$0.timestamp,latitude:$0.latitude,longitude:$0.longitude) }
                let signals = recording.signalSamples.map { TelemetrySample(timestamp:$0.timestamp,signals:$0.values,command:$0.command,
                    reply:$0.reply,requestHeader:$0.requestHeader,responseHeader:$0.responseHeader) }
                return Trip(id:recording.recordingID,vehicleID:recording.vehicleID,receiptID:receiptID,name:recording.name,
                            source:archive.sources.filter { recording.sourceIDs.contains($0.id) }.map(\.name).joined(separator:" + "),
                            samples:gps+signals,isDemo:recording.isSample,recordedStartedAt:recording.startedAt,recordedEndedAt:recording.endedAt,
                            recordedDistanceKm:recording.recordedDistanceKm,
                            tripFuelLitres:recording.tripFuelLitres)
            }
            let fills=archive.fuelEntries.map { fill in
                FuelEntry(id:fill.id,vehicleID:fill.vehicleID,date:fill.date,litresPurchased:fill.litresPurchased,totalCost:fill.totalCost,
                          currencyCode:fill.currencyCode,odometerKm:fill.odometerKm,isFullFill:fill.isFullFill,stationName:fill.stationName,
                          notes:fill.notes,receipt:fill.receipt,isDemo:fill.isSample)
            }
            guard !trips.isEmpty || !fills.isEmpty else { throw CANError.invalid("DriveLine archive contains no recordings or fuel entries.") }
            return ImportResult(trips:trips,fuelEntries:fills,receiptFiles:archive.receiptFiles,message:"Imported \(trips.count) DriveLine version-2 recording\(trips.count == 1 ? "" : "s") and \(fills.count) fuel entr\(fills.count == 1 ? "y" : "ies") with stable identities.")
        }
        if let schema = envelope?["schemaVersion"] as? Int, schema != 1 { throw CANError.invalid("Unsupported recording schema version.") }
        let rows = (envelope?["samples"] as? [[String:Any]]) ?? (object as? [[String:Any]]) ?? []
        guard !rows.isEmpty else { throw CANError.invalid("JSON needs a non-empty samples array.") }
        var samples: [TelemetrySample] = []; var skipped = 0
        for row in rows {
            guard let date = parseDate(row["timestamp"]) else { skipped += 1; continue }
            var signals: [String:Double] = [:]
            let values = (row["signals"] as? [String:Any]) ?? row
            for key in Signal.allCases {
                if let value = values[key.rawValue] as? NSNumber, value.doubleValue.isFinite { signals[key.rawValue] = value.doubleValue }
            }
            if signals[Signal.boostKpa.rawValue] == nil, let map = signals[Signal.mapKpa.rawValue], let baro = signals[Signal.barometricKpa.rawValue] { signals[Signal.boostKpa.rawValue] = map-baro }
            var sample=validSample(date,latitude:(row["latitude"] as? NSNumber)?.doubleValue,longitude:(row["longitude"] as? NSNumber)?.doubleValue,signals:signals)
            sample.command=row["command"] as? String;sample.reply=row["reply"] as? String
            sample.requestHeader=row["obdRequestHeader"] as? String;sample.responseHeader=row["obdResponseHeader"] as? String
            samples.append(sample)
        }
        guard !samples.isEmpty else { throw CANError.invalid("No valid absolute timestamps found in JSON samples.") }
        if let wireVehicle = (envelope?["vehicleID"] as? String).flatMap(UUID.init(uuidString:)), wireVehicle != vehicleID {
            throw CANError.invalid("The recording vehicleID does not match the selected vehicle.")
        }
        let stableID = (envelope?["recordingID"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let trip = Trip(id:stableID,vehicleID:vehicleID,receiptID:receiptID,name:envelope?["name"] as? String ?? name,source:envelope?["source"] as? String ?? "JSON import",samples:samples)
        return ImportResult(trips:[trip],message:"Imported \(trip.samples.count) samples; skipped \(skipped) rows with invalid timestamps.")
    }
    public static func csvRows(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(text.replacingOccurrences(of:"\r\n",with:"\n")); var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i+1 < chars.count && chars[i+1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == delimiter && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r") && !quoted {
                if c == "\r" && i+1 < chars.count && chars[i+1] == "\n" { i += 1 }
                row.append(field); field = ""; if row.contains(where:{ !$0.isEmpty }) { rows.append(row) }; row = []
            } else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw CANError.invalid("Unterminated quoted CSV field.") }
        row.append(field); if row.contains(where:{ !$0.isEmpty }) { rows.append(row) }
        return rows
    }
    static func normalize(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
    static func signal(for header: String) -> (Signal,Double,Double)? {
        let h = normalize(header)
        if let exact = Signal.allCases.first(where:{ normalize($0.rawValue) == h }) { return (exact,1,0) }
        switch h {
        case "speed", "speedkmh", "vehiclespeedkmh", "vehiclespeed": return (.speedKph,1,0)
        case "speedmph", "vehiclespeedmph": return (.speedKph,1.609344,0)
        case "rpm", "enginerpm", "enginespeedrpm": return (.rpm,1,0)
        case "coolant", "coolanttemperaturec", "enginecoolanttemperaturec": return (.coolantC,1,0)
        case "enginecoolanttemperaturef", "coolantf": return (.coolantC,5/9,-32*5/9)
        case "boost", "boostpressurekpa", "boostgaugekpa": return (.boostKpa,1,0)
        case "boostpsi", "boostpressurepsi": return (.boostKpa,6.894757,0)
        case "map", "intakemanifoldabsolutepressurekpa": return (.mapKpa,1,0)
        case "barometricpressurekpa": return (.barometricKpa,1,0)
        case "fuelrate", "enginefuelratelh", "fuelratelh": return (.fuelRateLph,1,0)
        case "fuellevel", "fuellevelinput", "fuellevelinputpercent": return (.fuelPercent,1,0)
        case "batteryvoltagev", "controlmodulevoltagev": return (.voltage,1,0)
        case "intakeairtemperaturec": return (.intakeC,1,0)
        case "engineoiltemperaturec": return (.oilC,1,0)
        case "calculatedengineload", "calculatedengineloadpercent": return (.engineLoad,1,0)
        default: return nil
        }
    }
    static func parseCSV(_ text: String, name: String, vehicleID: UUID, receiptID: UUID) throws -> ImportResult {
        let first = text.components(separatedBy:.newlines).first ?? ""
        let delimiter: Character = first.filter{$0 == ";"}.count > first.filter{$0 == ","}.count ? ";" : first.contains("\t") ? "\t" : ","
        let rows = try csvRows(text,delimiter:delimiter)
        guard let header = rows.first, rows.count > 1 else { throw CANError.invalid("CSV needs a header and at least one data row.") }
        let normalized = header.map(normalize)
        func index(_ candidates:[String]) -> Int? { normalized.firstIndex { candidates.contains($0) } }
        guard let ti = index(["timestamp","timestampepoch","timestampepochseconds","unixms","unixseconds","time","date","datetime","absolutetime"]) else { throw CANError.invalid("No absolute timestamp column found. Use timestamp (ISO-8601 or Unix seconds / milliseconds). Relative-only logs need a recording start time.") }
        let lati = index(["latitude","lat","gpslatitude"]), loni = index(["longitude","lon","lng","gpslongitude"])
        let idi = index(["id","arbitrationid"]), bytesi = index(["databytes","data"])
        let sensori = index(["sensor","pid","parameter","name"]), valuei = index(["value"])
        let mappings = header.enumerated().compactMap { i,h -> (Int,Signal,Double,Double)? in signal(for:h).map { (i,$0.0,$0.1,$0.2) } }
        var samples: [TelemetrySample] = [], skipped = 0, frames = 0, ids:[String:Int] = [:]
        for row in rows.dropFirst() {
            func cell(_ i:Int?) -> String? { guard let i = i, row.indices.contains(i) else { return nil }; return row[i] }
            guard let d = parseDate(cell(ti)) else { skipped += 1; continue }
            if let id = cell(idi), let bytes = cell(bytesi) {
                let hex = bytes.replacingOccurrences(of:" ",with:"")
                guard !hex.isEmpty, hex.count%2 == 0, hex.count<=128, hex.allSatisfy(\.isHexDigit), let idValue = UInt32(id,radix:16), idValue <= 0x1FFFFFFF else { skipped += 1; continue }
                frames += 1; ids[id.uppercased(), default:0] += 1; samples.append(TelemetrySample(timestamp:d)); continue
            }
            var values: [String:Double] = [:]
            for (i,key,mult,offset) in mappings { if let v = number(cell(i)) { values[key.rawValue] = v*mult+offset } }
            if let sensor = cell(sensori), let (key,mult,offset) = signal(for:sensor), let v = number(cell(valuei)) { values[key.rawValue] = v*mult+offset }
            if values[Signal.boostKpa.rawValue] == nil, let map = values[Signal.mapKpa.rawValue], let baro = values[Signal.barometricKpa.rawValue] { values[Signal.boostKpa.rawValue] = map-baro }
            let s = validSample(d,latitude:number(cell(lati)),longitude:number(cell(loni)),signals:values)
            guard !values.isEmpty || s.hasCoordinate else { skipped += 1; continue }
            samples.append(s)
        }
        guard !samples.isEmpty else { throw CANError.invalid("No recognized telemetry or valid raw CAN frames. Supported columns include timestamp, latitude, longitude, speedKph, rpm, coolantC, fuelRateLph, or webCAN TimestampEpoch/ID/DataBytes. Unknown sensor columns are not guessed.") }
        let source = frames > 0 ? "Raw CAN · webCAN" : text.lowercased().contains("car scanner") ? "Car Scanner CSV" : "CSV import"
        let trip = Trip(vehicleID:vehicleID,receiptID:receiptID,name:name,source:source,samples:samples,rawFrameCount:frames,arbitrationIDs:ids)
        return ImportResult(trips:[trip],message:"Imported \(frames > 0 ? frames : trip.samples.count) \(frames > 0 ? "frames" : "samples"); skipped \(skipped) rows.")
    }
    static func parseCandump(_ text: String, name: String, vehicleID: UUID, receiptID: UUID) throws -> ImportResult {
        let regex = try NSRegularExpression(pattern:#"^\(([0-9.]+)\)\s+\S+\s+([0-9A-Fa-f]{3,8})#([0-9A-Fa-f]*)$"#)
        var samples:[TelemetrySample] = [], ids:[String:Int] = [:], skipped = 0
        for line in text.components(separatedBy:.newlines) where !line.isEmpty {
            let s = line as NSString
            guard let m = regex.firstMatch(in:line,range:NSRange(location:0,length:s.length)), let date = parseDate(s.substring(with:m.range(at:1))) else { skipped += 1; continue }
            let id = s.substring(with:m.range(at:2)).uppercased(), bytes = s.substring(with:m.range(at:3))
            guard let number = UInt32(id,radix:16), number <= 0x1FFFFFFF, bytes.count%2 == 0, bytes.count <= 16 else { skipped += 1; continue }
            samples.append(TelemetrySample(timestamp:date)); ids[id,default:0] += 1
        }
        guard !samples.isEmpty else { throw CANError.invalid("No supported classic CAN candump frames. Use absolute timestamps and ID#hex data.") }
        return ImportResult(trips:[Trip(vehicleID:vehicleID,receiptID:receiptID,name:name,source:"Raw CAN · candump",samples:samples,rawFrameCount:samples.count,arbitrationIDs:ids)],message:"Archived \(samples.count) raw frames; skipped \(skipped) lines. No signal decoder applied.")
    }
}
