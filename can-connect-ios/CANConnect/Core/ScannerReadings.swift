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
        "dpfAverageRegenMinutes":("Average regeneration interval","min"), "dpfAverageRegenKM":("Average regeneration distance","km"),
        "dpfAshML":("DPF ash volume","mL"), "dpfSootG":("DPF soot mass","g"), "dsgFluidC":("DSG fluid temperature","°C")
    ]
    // Slow environmental/tank values do not need to compete with live engine
    // readings. All PIDs still run immediately on a new connection.
    static func pollInterval(pid: Int) -> TimeInterval {
        switch pid {
        case 0x46,0x33: return 60
        case 0x2F: return 30
        case 0x0C,0x0D,0x5E,0x70,0x78,0x7A,0x04,0x10: return 0.5
        default: return 3
        }
    }
    static func freshness(for key: String) -> TimeInterval {
        DriveLineAcquisitionPolicy.signal(key).displayValidity
    }
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
        prepareLiveEvidence()
        if samples == nil { samples = [] }
        samples?.append(sample)
        liveEvidence.accept(sample,recordingID:id)
        updateLiveDistance(at:sample.timestamp)
        updatedAt = max(updatedAt, sample.timestamp)
    }
}

struct LiveRecordingEvidence {
    var sampleCount=0
    var pointCount=0
    var latest:[String:DriveLineObservation]=[:]
    var speedIntegral=0.0
    var speedSeconds=0.0
    var gpsKm=0.0
    var gpsSeconds=0.0
    var lastPoint:RoutePoint?
    mutating func accept(_ sample:OBDSample,recordingID:UUID) {
        for (key,value) in sample.signals where value.isFinite {
            if let previous=latest[key],previous.timestamp > sample.timestamp { continue }
            if key == "speedKph",let previous=latest[key] {
                let seconds=sample.timestamp.timeIntervalSince(previous.timestamp)
                if seconds > 0,seconds <= DriveLineMetricPolicy.maximumSignalGap,
                   (0...DriveLineMetricPolicy.maximumPlausibleSpeedKph).contains(value),
                   (0...DriveLineMetricPolicy.maximumPlausibleSpeedKph).contains(previous.value) {
                    speedIntegral += (previous.value+value)/2*seconds;speedSeconds += seconds
                }
            }
            latest[key] = .init(key:key,value:value,timestamp:sample.timestamp,sourceID:"obd",recordingID:recordingID)
        }
        sampleCount += 1
    }
    mutating func accept(_ point:RoutePoint) {
        if let previous=lastPoint {
            let seconds=point.timestamp.timeIntervalSince(previous.timestamp),metres=previous.distance(to:point)
            if seconds > 0,seconds <= DriveLineMetricPolicy.maximumGPSGap,
               metres/seconds*3.6 <= DriveLineMetricPolicy.maximumPlausibleSpeedKph {
                gpsSeconds += seconds
                if metres >= DriveLineMetricPolicy.minimumGPSMovementM { gpsKm += metres/1000 }
            }
        }
        lastPoint=point;pointCount += 1
    }
}

extension RecordingDraft {
    mutating func prepareLiveEvidence() {
        guard liveEvidence.sampleCount != (samples?.count ?? 0) || liveEvidence.pointCount != route.count else { return }
        liveEvidence=LiveRecordingEvidence()
        for sample in samples ?? [] { liveEvidence.accept(sample,recordingID:id) }
        for point in route { liveEvidence.accept(point) }
    }
    mutating func updateLiveDistance(at date:Date) {
        let duration=max(0,date.timeIntervalSince(startedAt))
        let speedCoverage=duration > 0 ? liveEvidence.speedSeconds/duration:0
        let gpsCoverage=duration > 0 ? liveEvidence.gpsSeconds/duration:0
        if liveEvidence.gpsSeconds > 0,gpsCoverage >= speedCoverage-DriveLineMetricPolicy.comparableDistanceCoverage {
            distanceKM=liveEvidence.gpsKm
        } else if liveEvidence.speedSeconds > 0 { distanceKM=liveEvidence.speedIntegral/3600 }
    }
}


extension RecordingDraft {
    func integral(_ key: String) -> (value: Double, coverage: Double)? {
        DriveLineMetricPolicy.integral(key,samples:(samples ?? []).map { DriveLineSignalSample(timestamp:$0.timestamp,values:$0.signals,sourceID:"obd") })
    }
    func measuredFuel(endedAt: Date) -> (litres: Double?, economy: Double?) {
        let duration = endedAt.timeIntervalSince(startedAt)
        guard source == .scanner, duration > 0, let fuel = integral("fuelRateLph"), fuel.coverage/duration >= DriveLineMetricPolicy.requiredFuelCoverage else { return (nil,nil) }
        let litres = fuel.value/3600
        guard let speed = integral("speedKph"), speed.coverage/duration >= 0.8, distanceKM > 0.1 else { return (litres,nil) }
        return (litres,litres/distanceKM*100)
    }
}
extension Trip {
    func recordedValue(_ key: String) -> Double? { samples?.last(where:{$0.signals[key] != nil})?.signals[key] }
}

// Only real ECU responses drive automatic trip boundaries. Missing replies,
// GPS motion and accessory availability are never engine-off evidence.
struct ScannerTripBoundary {
    static let reconnectGrace: TimeInterval = 120
    private var stoppedSince: Date?
    private var lastZero: Date?
    private var speed: (value: Double, date: Date)?

    static func engineRunning(_ sample: OBDSample) -> Bool {
        sample.isValid && (sample.signals["rpm"] ?? 0) >= 400
    }
    mutating func reset() { self = ScannerTripBoundary() }
    mutating func engineOff(after sample: OBDSample) -> Bool {
        guard sample.isValid else { return false }
        if let value = sample.signals["speedKph"] {
            speed = (value,sample.timestamp)
            if value > 0 { stoppedSince = nil; lastZero = nil }
        }
        guard let rpm = sample.signals["rpm"] else { return false }
        guard rpm == 0, let speed, speed.value == 0,
              (0...15).contains(sample.timestamp.timeIntervalSince(speed.date)) else {
            stoppedSince = nil; lastZero = nil; return false
        }
        if let previous = lastZero {
            let interval = sample.timestamp.timeIntervalSince(previous)
            guard interval > 0 else { return false }
            if interval > 15 { stoppedSince = nil }
        }
        if stoppedSince == nil { stoppedSince = sample.timestamp }
        lastZero = sample.timestamp
        return sample.timestamp.timeIntervalSince(stoppedSince!) >= 3
    }
}
