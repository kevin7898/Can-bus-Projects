import Foundation

struct ScannerSettings: Codable, Equatable {
    var host = ""
    var port: UInt16 = 35000
}

// One actual adapter response, timestamped on receipt. No carried-forward readings.
struct OBDSample: Codable, Equatable {
    var timestamp: Date
    var signals: [String: Double]
    var command: String
    var reply: String
    var isValid: Bool {
        timestamp.timeIntervalSince1970.isFinite && command.count <= 16 && reply.count <= 64_000 &&
        !signals.isEmpty && signals.count <= 20 && signals.allSatisfy { OBDDecoder.keys.contains($0.key) && $0.value.isFinite }
    }
}

enum OBDDecoder {
    static let definitions: [(pid: Int, key: String, bytes: Int)] = [
        (0x0D,"speedKph",1), (0x0C,"rpm",2), (0x05,"coolantC",1),
        (0x0B,"mapKpa",1), (0x33,"barometricKpa",1), (0x5E,"fuelRateLph",2),
        (0x2F,"fuelPercent",1), (0x46,"outsideC",1), (0x42,"voltage",2),
        (0x0F,"intakeC",1), (0x5C,"oilC",1), (0x04,"engineLoad",1)
    ]
    static let labels: [String:(title:String,unit:String)] = [
        "speedKph":("Vehicle speed","km/h"), "rpm":("Engine speed","rpm"),
        "coolantC":("Coolant","°C"), "mapKpa":("Manifold pressure","kPa absolute"),
        "barometricKpa":("Barometric pressure","kPa absolute"), "fuelRateLph":("Fuel rate","L/h"),
        "fuelPercent":("Fuel level","%"), "outsideC":("Outside temperature","°C"),
        "voltage":("System voltage","V"), "intakeC":("Intake temperature","°C"),
        "oilC":("Oil temperature","°C"), "engineLoad":("Engine load","%")
    ]
    static let keys = Set(definitions.map(\.key))
    static func decode(_ reply: String, pid: Int, at timestamp: Date = Date()) -> OBDSample? {
        guard let definition = definitions.first(where:{$0.pid == pid}) else { return nil }
        let replies = ELMIdentityParser.payloads(reply).filter { $0.count >= definition.bytes+2 && $0[0] == 0x41 && Int($0[1]) == pid }
        // With headers off, conflicting ECU replies cannot safely be attributed. Leave unavailable.
        let values = Set(replies.map { bytes -> Double in
            let a = Double(bytes[2]), b = bytes.count > 3 ? Double(bytes[3]) : 0
            switch pid {
            case 0x0C: return (a*256+b)/4
            case 0x05,0x46,0x0F,0x5C: return a-40
            case 0x5E: return (a*256+b)/20
            case 0x42: return (a*256+b)/1000
            case 0x2F,0x04: return a*100/255
            default: return a
            }
        })
        guard values.count == 1, let value = values.first else { return nil }
        return OBDSample(timestamp:timestamp,signals:[definition.key:value],command:String(format:"01%02X",pid),reply:reply)
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
