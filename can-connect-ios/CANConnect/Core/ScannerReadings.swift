import Foundation

enum ScannerConnectionKind: String, Codable, CaseIterable, Identifiable {
    case wifi, obdLinkMXPlus
    var id: String { rawValue }
    var title: String { self == .wifi ? "Wi-Fi ELM327" : "OBDLink MX+ · Bluetooth" }
    var shortTitle: String { self == .wifi ? "Wi-Fi OBD" : "MX+ Bluetooth OBD" }
}

struct ScannerSettings: Codable, Equatable {
    var host = ""
    var port: UInt16 = 35000
    // Optional so saved Wi-Fi profiles decode without migration or data loss.
    var transport: ScannerConnectionKind? = nil
    var accessorySerial: String? = nil
    var kind: ScannerConnectionKind { transport ?? .wifi }
}

// One actual adapter response, timestamped on receipt. No carried-forward readings.
struct OBDSample: Codable, Equatable {
    var timestamp: Date
    var signals: [String: Double]
    var command: String
    var reply: String
    var requestHeader: String? = nil
    var responseHeader: String? = nil
    var isValid: Bool {
        timestamp.timeIntervalSince1970.isFinite && command.count <= 16 && reply.count <= 64_000 &&
        [requestHeader,responseHeader].allSatisfy { $0 == nil || ($0!.count == 3 && $0!.allSatisfy { $0.isASCII && $0.isHexDigit }) } &&
        !signals.isEmpty && signals.count <= 32 && signals.allSatisfy { OBDDecoder.keys.contains($0.key) && $0.value.isFinite }
    }
}

enum OBDDecoder {
    static let definitions: [(pid: Int, key: String, bytes: Int)] = [
        (0x0D,"speedKph",1), (0x0C,"rpm",2), (0x05,"coolantC",1),
        (0x0B,"mapKpa",1), (0x33,"barometricKpa",1), (0x5E,"fuelRateLph",2),
        (0x2F,"fuelPercent",1), (0x46,"outsideC",1), (0x42,"voltage",2),
        (0x0F,"intakeC",1), (0x5C,"oilC",1), (0x04,"engineLoad",1),
        (0x10,"mafGps",2), (0x70,"boostAbsoluteKpa",10), (0x78,"egt1C",9),
        (0x7A,"dpfDifferentialKpa",7), (0x8B,"dpfRegenActive",7)
    ]
    static let labels: [String:(title:String,unit:String)] = [
        "speedKph":("Vehicle speed","km/h"), "rpm":("Engine speed","rpm"),
        "coolantC":("Coolant","°C"), "mapKpa":("Manifold pressure","kPa absolute"),
        "barometricKpa":("Barometric pressure","kPa absolute"), "fuelRateLph":("Fuel rate","L/h"),
        "fuelPercent":("Fuel level","%"), "outsideC":("Outside temperature","°C"),
        "voltage":("System voltage","V"), "intakeC":("Intake temperature","°C"),
        "oilC":("Oil temperature","°C"), "engineLoad":("Engine load","%"),
        "mafGps":("Mass airflow","g/s"), "boostAbsoluteKpa":("Boost pressure A","kPa absolute"),
        "boostCommandedKpa":("Commanded boost A","kPa absolute"),
        "boostBAbsoluteKpa":("Boost pressure B","kPa absolute"), "boostBCommandedKpa":("Commanded boost B","kPa absolute"),
        "egt1C":("Exhaust temperature 1","°C"), "egt2C":("Exhaust temperature 2","°C"),
        "egt3C":("Exhaust temperature 3","°C"), "egt4C":("Exhaust temperature 4","°C"),
        "dpfDifferentialKpa":("DPF differential pressure","kPa"), "dpfInletKpa":("DPF inlet pressure","kPa"),
        "dpfOutletKpa":("DPF outlet pressure","kPa"), "dpfRegenActive":("DPF regeneration","state"),
        "dpfRegenType":("DPF active regeneration type","state"), "dpfRegenTrigger":("DPF regeneration trigger","%"),
        "dpfAverageRegenMinutes":("Average regeneration interval","min"), "dpfAverageRegenKM":("Average regeneration distance","km")
    ]
    static let keys = Set(labels.keys)
    static func signalKeys(pid: Int) -> Set<String> {
        switch pid {
        case 0x70: return ["boostAbsoluteKpa","boostCommandedKpa","boostBAbsoluteKpa","boostBCommandedKpa"]
        case 0x78: return ["egt1C","egt2C","egt3C","egt4C"]
        case 0x7A: return ["dpfDifferentialKpa","dpfInletKpa","dpfOutletKpa"]
        case 0x8B: return ["dpfRegenActive","dpfRegenType","dpfRegenTrigger","dpfAverageRegenMinutes","dpfAverageRegenKM"]
        default: return Set(definitions.filter {$0.pid == pid}.map(\.key))
        }
    }
    static func decode(_ reply: String, pid: Int, at timestamp: Date = Date(), ecu: String? = nil) -> OBDSample? {
        guard let definition = definitions.first(where:{$0.pid == pid}) else { return nil }
        let replies = ELMResponses.payloads(reply,ecu:ecu).filter { $0.count >= definition.bytes+2 && $0[0] == 0x41 && Int($0[1]) == pid }
        let decoded = replies.map { decodeData(Array($0.dropFirst(2)),pid:pid,key:definition.key) }
        // Ambiguous replies remain unavailable; never choose the first ECU value.
        guard let signals = decoded.first, !signals.isEmpty, decoded.allSatisfy({$0 == signals}) else { return nil }
        return OBDSample(timestamp:timestamp,signals:signals,command:String(format:"01%02X",pid),reply:reply,
                         requestHeader:ecu == "7E8" ? "7E0" : nil,responseHeader:ecu)
    }
    private static func decodeData(_ d: [UInt8], pid: Int, key: String) -> [String:Double] {
        func u16(_ i: Int) -> Double { Double(d[i])*256+Double(d[i+1]) }
        func supported(_ mask: UInt8) -> Bool { d[0] & mask != 0 }
        var result: [String:Double] = [:]
        switch pid {
        case 0x70:
            if supported(1) { result["boostCommandedKpa"] = u16(1)/32 }
            if supported(2) { result["boostAbsoluteKpa"] = u16(3)/32 }
            if supported(8) { result["boostBCommandedKpa"] = u16(5)/32 }
            if supported(16) { result["boostBAbsoluteKpa"] = u16(7)/32 }
        case 0x78:
            for i in 0..<4 where supported(UInt8(1 << i)) { result["egt\(i+1)C"] = u16(1+i*2)/10-40 }
        case 0x7A:
            if supported(1) { let raw = u16(1); result["dpfDifferentialKpa"] = (raw >= 32768 ? raw-65536 : raw)/100 }
            if supported(2) { result["dpfInletKpa"] = u16(3)/100 }
            if supported(4) { result["dpfOutletKpa"] = u16(5)/100 }
        case 0x8B:
            if supported(1) { result["dpfRegenActive"] = Double(d[1] & 1) }
            if supported(2) { result["dpfRegenType"] = Double((d[1] >> 1) & 1) }
            if supported(16) { result["dpfRegenTrigger"] = Double(d[2])*100/255 }
            if supported(32) { result["dpfAverageRegenMinutes"] = u16(3) }
            if supported(64) { result["dpfAverageRegenKM"] = u16(5) }
        case 0x0C: result[key] = u16(0)/4
        case 0x05,0x46,0x0F,0x5C: result[key] = Double(d[0])-40
        case 0x5E: result[key] = u16(0)/20
        case 0x42: result[key] = u16(0)/1000
        case 0x10: result[key] = u16(0)/100
        case 0x2F,0x04: result[key] = Double(d[0])*100/255
        default: result[key] = Double(d[0])
        }
        return result
    }
}

extension RecordingDraft {
    mutating func accept(_ sample: OBDSample) {
        guard source == .scanner, sample.isValid, sample.timestamp >= startedAt,
              sample.timestamp >= (samples?.last?.timestamp ?? startedAt) else { return }
        if let speed = sample.signals["speedKph"],
           let previous = samples?.last(where:{$0.signals["speedKph"] != nil}),
           let before = previous.signals["speedKph"] {
            let dt = sample.timestamp.timeIntervalSince(previous.timestamp)
            if dt > 0 && dt <= 10 { distanceKM += (before+speed)/2 * dt/3600 }
        }
        if samples == nil { samples = [] }
        samples?.append(sample); updatedAt = sample.timestamp
    }
}


extension RecordingDraft {
    func integral(_ key: String) -> (value: Double, coverage: Double)? {
        let values = (samples ?? []).compactMap { sample in sample.signals[key].map { (sample.timestamp,$0) } }
        var value = 0.0, coverage = 0.0
        for (a,b) in zip(values,values.dropFirst()) {
            let seconds = b.0.timeIntervalSince(a.0)
            guard seconds > 0, seconds <= 10, a.1 >= 0, b.1 >= 0 else { continue }
            value += (a.1+b.1)/2*seconds; coverage += seconds
        }
        return coverage > 0 ? (value,coverage) : nil
    }
    func measuredFuel(endedAt: Date) -> (litres: Double?, economy: Double?) {
        let duration = endedAt.timeIntervalSince(startedAt)
        guard source == .scanner, duration > 0, let fuel = integral("fuelRateLph"), fuel.coverage/duration >= 0.8 else { return (nil,nil) }
        let litres = fuel.value/3600
        guard let speed = integral("speedKph"), speed.coverage/duration >= 0.8, distanceKM > 0.1 else { return (litres,nil) }
        return (litres,litres/distanceKM*100)
    }
}
extension Trip {
    func recordedValue(_ key: String) -> Double? { samples?.last(where:{$0.signals[key] != nil})?.signals[key] }
}
