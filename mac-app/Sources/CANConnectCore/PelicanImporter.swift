import Foundation
#if canImport(CSQLite)
import CSQLite
#else
import SQLite3
#endif

public enum PelicanImporter {
    public static func decode(command: String, response: String) -> [String:Double] {
        let command = command.uppercased().replacingOccurrences(of:" ",with:"")
        guard command.count == 4, command.hasPrefix("01") else { return [:] }
        let pid = String(command.suffix(2)), compact = response.uppercased().filter(\.isHexDigit)
        guard let range = compact.range(of:"41"+pid) else { return [:] }
        let payload = String(compact[range.upperBound...])
        guard payload.count >= 2, let a = Int(payload.prefix(2),radix:16) else { return [:] }
        let b = payload.count>=4 ? Int(payload.dropFirst(2).prefix(2),radix:16) : nil
        func pair(_ s:Signal,_ value:Double) -> [String:Double] { [s.rawValue:value] }
        switch pid {
        case "04": return pair(.engineLoad,Double(a)*100/255)
        case "05": return pair(.coolantC,Double(a)-40)
        case "0B": return pair(.mapKpa,Double(a))
        case "0C": return b.map { pair(.rpm,Double(a*256+$0)/4) } ?? [:]
        case "0D": return pair(.speedKph,Double(a))
        case "0F": return pair(.intakeC,Double(a)-40)
        case "2F": return pair(.fuelPercent,Double(a)*100/255)
        case "33": return pair(.barometricKpa,Double(a))
        case "42": return b.map { pair(.voltage,Double(a*256+$0)/1000) } ?? [:]
        case "5C": return pair(.oilC,Double(a)-40)
        case "5E": return b.map { pair(.fuelRateLph,Double(a*256+$0)/20) } ?? [:]
        default: return [:]
        }
    }
    public static func parse(database: URL, vehicleID: UUID, receiptID: UUID) throws -> ImportResult {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path,&db,SQLITE_OPEN_READONLY,nil) == SQLITE_OK else {
            if let db = db { sqlite3_close(db) }; throw CANError.invalid("Cannot open the Pelican database. Keep db.sqlite and its WAL file together in the .scanlogs folder.")
        }
        defer { sqlite3_close(db) }
        let sql = "SELECT ZSESSION, ZTIMESTAMP, ZCOMMAND, ZRESPONSE FROM ZCOMMANDRESPONSE ORDER BY ZSESSION, ZTIMESTAMP"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil) == SQLITE_OK else { throw CANError.invalid("This SQLite file is not a supported Pelican scanlogs session database.") }
        defer { sqlite3_finalize(statement) }
        var sessions:[Int:[TelemetrySample]] = [:], counts:[Int:Int] = [:], total = 0
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            total += 1; guard total <= 2_000_000 else { throw CANError.invalid("Pelican session exceeds the two million response import limit.") }
            let session = Int(sqlite3_column_int(statement,0)), reference = sqlite3_column_double(statement,1)
            guard let commandBytes = sqlite3_column_text(statement,2) else { step = sqlite3_step(statement); continue }
            let command = String(cString:commandBytes)
            let length = Int(sqlite3_column_bytes(statement,3))
            let data = sqlite3_column_blob(statement,3).map { Data(bytes:$0,count:length) } ?? Data()
            let response = String(data:data,encoding:.utf8) ?? ""
            let date = Date(timeIntervalSinceReferenceDate:reference)
            guard date.timeIntervalSince1970 >= 946684800, date.timeIntervalSince1970 <= 7258118400 else { step = sqlite3_step(statement); continue }
            let values = decode(command:command,response:response)
            sessions[session,default:[]].append(TelemetrySample(timestamp:date,signals:values))
            counts[session,default:0] += 1
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw CANError.invalid("Pelican database read failed; the original archive has been preserved.") }
        guard !sessions.isEmpty else { throw CANError.invalid("No command responses with valid session timestamps found.") }
        let trips = sessions.keys.sorted().map { key in
            Trip(vehicleID:vehicleID,receiptID:receiptID,name:"Pelican session \(key)",source:"Pelican diagnostic log",samples:sessions[key] ?? [],diagnosticResponseCount:counts[key] ?? 0)
        }
        return ImportResult(trips:trips,message:"Imported \(trips.count) Pelican session(s), \(total) diagnostic responses. Standard Mode 01 signals decoded; proprietary responses remain in the preserved original.")
    }
}
