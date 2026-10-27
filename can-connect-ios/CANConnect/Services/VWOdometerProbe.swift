import Foundation

/// Bounded diagnostic experiment, deliberately separate from the trip scheduler.
/// Candidates come from OBDb/Volkswagen-Jetta; none becomes a trusted odometer.
struct VWOdometerProbeReport: Codable {
    struct Entry: Codable {
        var requestHeader: String
        var responseHeader: String
        var command: String
        var reply: String
        var outcome: String
        var observedAt:Date? = nil
        var diagnosticSession:String? = nil
        var candidateKM: Double?
        var payloadHex: String? = nil
        var candidateLitres: Double? = nil
    }
    var id = UUID()
    var startedAt = Date()
    var entries: [Entry] = []
    var purpose:String? = nil
    var status = "Running"
    var text: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data:$0,encoding:.utf8) } ?? "Report unavailable"
    }
}

enum VWTripDiscoveryBatch:String,CaseIterable,Identifiable {
    case first,second
    var id:String { rawValue }
    var title:String { self == .first ? "Batch 1":"Batch 2" }
    var ranges:String { self == .first ? "2200–220F and 2290–229F":"2210–221F and 22A0–22AF" }
    var identifiers:[Int] { self == .first ? Array(0x2200...0x220F)+Array(0x2290...0x229F):Array(0x2210...0x221F)+Array(0x22A0...0x22AF) }
}

@MainActor
final class VWOdometerProbe {
    struct Candidate {
        let did: String
        let byteCount: Int
        let divisor: Double
        var littleEndian = false
    }
    // Hypothesis-driven neighborhoods, NOT documented trip-counter identifiers.
    static let tripDiscoveryDIDs = VWTripDiscoveryBatch.first.identifiers
    private var tripBatch:VWTripDiscoveryBatch = .first
    private var tripDiscovery=false
    private var sessionName="default"
    static let cluster = [Candidate(did:"2203",byteCount:3,divisor:1), Candidate(did:"22B8",byteCount:4,divisor:1000)]
    static let engine = [Candidate(did:"108C",byteCount:4,divisor:1), Candidate(did:"10E0",byteCount:4,divisor:1), Candidate(did:"1160",byteCount:4,divisor:1000)]
    static let gearbox = [Candidate(did:"103D",byteCount:3,divisor:1), Candidate(did:"3841",byteCount:4,divisor:10), Candidate(did:"3887",byteCount:4,divisor:10,littleEndian:true)]
    private let transport: ScannerTransport
    private var report = VWOdometerProbeReport()
    private var tx = "", rx = ""
    private var clusterSessionAttempted = false
    private let progress: (String) -> Void
    init(transport:ScannerTransport,progress:@escaping (String)->Void = {_ in}) {
        self.transport=transport;self.progress=progress
    }
    static func candidateKM(_ candidate:Candidate, reply:String, response:String) -> Double? {
        let parsed = TelemetryELM.parse(reply)
        guard parsed.rejected == 0, let did = UInt16(candidate.did,radix:16) else { return nil }
        let prefix: [UInt8] = [0x62,UInt8(did >> 8),UInt8(did & 255)]
        let payloads = parsed.payloads.filter { $0.ecu == response }.map(\.bytes)
        guard let first=payloads.first, first.count == 3+candidate.byteCount,
              first.starts(with:prefix),payloads.allSatisfy({$0 == first}) else { return nil }
        let bytes = Array(first.dropFirst(3))
        guard !bytes.allSatisfy({$0 == 255}) else { return nil }
        let ordered = candidate.littleEndian ? Array(bytes.reversed()) : bytes
        let value = ordered.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let km = Double(value)/candidate.divisor
        guard km.isFinite, (0...5_000_000).contains(km) else { return nil }
        return km
    }
    private func exchange(_ command:String, candidate:Candidate? = nil, cleanup:Bool = false) async throws -> String {
        if !cleanup { try Task.checkCancellation() }
        // No free-form commands, security access, coding, resets or writes.
        let dataCommands = Set((Self.cluster+Self.engine+Self.gearbox).map { "22"+$0.did })
            .union(tripDiscovery ? tripBatch.identifiers.map { String(format:"22%04X",$0) }:[])
            .union(["22F187","22F189","22229A","1003","1001","010D","0904","ATDPN"])
        let settings:Set<String> = ["ATE0","ATL0","ATS1","ATH1","ATD0","ATCAF1","ATCFC1","ATAT1","ATST32","ATFCSM0","ATFCSD300000","ATFCSM1"]
        let routes = ["714","7E0","7E1"].flatMap { ["ATSH"+$0,"ATFCSH"+$0] } + ["77E","7E8","7E9"].map { "ATCRA"+$0 }
        guard dataCommands.contains(command) || settings.contains(command) || routes.contains(command) else { throw AppFailure("Request outside odometer probe allowlist.") }
        let reply = try await transport.command(command)
        let km = candidate.flatMap { Self.candidateKM($0,reply:reply,response:rx) }
        let bytes = TelemetryELM.parse(reply).payloads.filter {$0.ecu == rx}.map(\.bytes)
        let outcome:String
        if let negative=bytes.first(where:{$0.count == 3 && $0[0] == 0x7F}) {
            outcome=String(format:"Negative response %02X (request not accepted in this session)",negative[2])
        } else if km != nil { outcome="Unverified candidate; compare with dashboard" }
        else if reply.uppercased().contains("NO DATA") { outcome="No reply; support undetermined" }
        else { outcome="Response captured" }
        report.entries.append(.init(requestHeader:tx,responseHeader:rx,command:command,reply:reply,outcome:outcome,observedAt:Date(),diagnosticSession:sessionName,candidateKM:km))
        if command.hasPrefix("AT"),command != "ATDPN",
           reply.trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:">"))).uppercased() != "OK" {
            throw AppFailure("Adapter rejected probe configuration \(command).")
        }
        return reply
    }
    private func route(_ request:String,_ response:String) async throws {
        tx=request;rx=response
        // Non-OBD cluster addresses need an explicit flow-control header.
        for command in ["ATFCSM0","ATSH"+tx,"ATCRA"+rx,"ATFCSH"+tx,"ATFCSD300000","ATFCSM1"] {
            _ = try await exchange(command)
        }
    }
    private func read(_ candidates:[Candidate]) async throws {
        for candidate in candidates {
            progress("Checking \(tx) · \(candidate.did)…")
            _ = try await exchange("22"+candidate.did,candidate:candidate)
        }
    }
    static func fuelLitres(reply:String) -> Double? {
        let candidate=Candidate(did:"229A",byteCount:2,divisor:8)
        guard let litres=candidateKM(candidate,reply:reply,response:"77E"),litres <= 200 else { return nil }
        return litres
    }
    private func readClusterFuel() async throws {
        progress("Checking cluster fuel level…")
        let reply=try await exchange("22229A")
        if let litres=Self.fuelLitres(reply:reply) {
            report.entries[report.entries.count-1].candidateLitres=litres
            report.entries[report.entries.count-1].outcome="Unverified cluster fuel volume; compare with gauge and fill-ups"
        }
    }
    private func restoreCluster() async throws {
        guard clusterSessionAttempted else { return }
        let reply = try await exchange("1001",cleanup:true)
        guard TelemetryELM.parse(reply).payloads.contains(where:{$0.ecu == "77E" && $0.bytes.starts(with:[0x50,0x01])}) else {
            throw AppFailure("Cluster default-session reply missing. Probe stopped; switch ignition off before reconnecting.")
        }
        clusterSessionAttempted=false
    }
    private func probeDSGMileage() async throws -> String {
        try await route("7E1","7E9")
        progress("Checking DSG software…")
        let calibration=try await exchange("0904")
        guard VWController.dsg.matchesCalibration(calibration) else {
            return "DSG measuring-block check skipped: software fingerprint not verified."
        }
        progress("Reading DSG measuring block 109…")
        // VWMeasuringBlocks constructs its own narrowly allowlisted raw frames.
        // Do not send these through the ISO-TP request/response parser above.
        let reader=VWMeasuringBlocks(exchange: { command in
            if command.hasPrefix("ATSH") { self.tx=String(command.dropFirst(4)) }
            if command.hasPrefix("ATCRA") { self.rx=String(command.dropFirst(5)) }
            let reply=try await self.transport.command(command)
            self.report.entries.append(.init(requestHeader:self.tx,responseHeader:self.rx,command:command,
                reply:reply,outcome:"VW TP2.0 diagnostic exchange; raw evidence only",candidateKM:nil))
            return reply
        })
        let response=try await reader.probeDSGMileage(calibrationReply:calibration)
        let positive=response.payload.starts(with:[0x61,109])
        let outcome=positive ? "DSG block 109 returned data; scale and meaning unverified" : "DSG block 109 rejected; support undetermined"
        report.entries.append(.init(requestHeader:response.requestHeader,responseHeader:response.responseHeader,
            command:"216D",reply:response.raw,outcome:outcome,candidateKM:nil,
            payloadHex:response.payload.map {String(format:"%02X",$0)}.joined(separator:" ")))
        return outcome+"."
    }
    static func rawClusterPayload(_ reply:String,did:Int)->[UInt8]? {
        let parsed=TelemetryELM.parse(reply),prefix:[UInt8]=[0x62,UInt8(did >> 8),UInt8(did & 255)]
        guard parsed.rejected == 0,let first=parsed.payloads.first,
              first.ecu == "77E",first.bytes.starts(with:prefix),first.bytes.count>3,
              parsed.payloads.allSatisfy({ $0.ecu == "77E" && $0.bytes == first.bytes }) else { return nil }
        return Array(first.bytes.dropFirst(3))
    }
    private func tripSnapshot() async throws {
        for (index,did) in tripBatch.identifiers.enumerated() {
            progress("Trip discovery · \(tripBatch.title) · \(sessionName) · \(index+1)/32")
            let reply=try await exchange(String(format:"22%04X",did))
            if let bytes=Self.rawClusterPayload(reply,did:did) {
                report.entries[report.entries.count-1].payloadHex=bytes.map { String(format:"%02X",$0) }.joined(separator:" ")
                report.entries[report.entries.count-1].outcome="Positive response; meaning and scale unknown. Compare snapshots with dashboard trip."
            }
        }
    }
    private func discoverTrip() async throws {
        try await route("714","77E")
        let part=try await exchange("22F187"),version=try await exchange("22F189")
        guard Self.rawClusterPayload(part,did:0xF187).map({String(decoding:$0,as:UTF8.self).trimmingCharacters(in:.whitespaces)}) == "5C6920853A",
              Self.rawClusterPayload(version,did:0xF189).map({String(decoding:$0,as:UTF8.self)}) == "0809" else {
            throw AppFailure("Trip discovery stopped: cluster hardware/software does not match the tested Jetta.")
        }
        try await tripSnapshot()
        clusterSessionAttempted=true
        let reply=try await exchange("1003")
        if TelemetryELM.parse(reply).payloads.contains(where:{$0.ecu == "77E" && $0.bytes.starts(with:[0x50,0x03])}) {
            sessionName="extended";try await tripSnapshot()
        }
        try await restoreCluster()
        _ = try await exchange("ATFCSM0")
        let count=report.entries.filter { $0.payloadHex != nil }.count
        report.status="Finished. \(count) positive readings captured; none identified as trip distance yet. Share this report with a dashboard trip photo. Reconnect to resume recording."
    }
    func run(settings:ScannerSettings,vehicle:VehicleProfile,tripDiscovery:Bool=false,tripBatch:VWTripDiscoveryBatch = .first) async -> VWOdometerProbeReport {
        self.tripDiscovery=tripDiscovery;self.tripBatch=tripBatch
        report.purpose=tripDiscovery ? "Cluster trip discovery \(tripBatch.title): \(tripBatch.ranges); raw hypotheses":"Odometer and fuel candidates"
        defer { transport.disconnect() }
        do {
            guard !vehicle.isSample, vehicle.make.lowercased().contains("volkswagen"),
                  let expected=vehicle.vin,!expected.isEmpty else { throw AppFailure("Select your Volkswagen with a saved VIN before probing.") }
            progress("Verifying vehicle…")
            let identity = try await transport.open(host:settings.host,port:settings.port)
            try Task.checkCancellation()
            guard identity.vin?.uppercased() == expected.uppercased() else { throw AppFailure("Vehicle VIN could not be verified. Probe stopped.") }
            let proto = try await exchange("ATDPN").trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
            guard ["6","A6"].contains(proto) else { throw AppFailure("Probe requires verified 11-bit 500 kbit CAN.") }
            for command in ["ATE0","ATL0","ATS1","ATH1","ATD0","ATCAF1","ATCFC1","ATAT1","ATST32"] { _ = try await exchange(command) }
            try await route("7E0","7E8")
            let speedReply = try await exchange("010D")
            let speeds=TelemetryELM.parse(speedReply).payloads.filter {$0.ecu == "7E8"}.map(\.bytes)
            guard !speeds.isEmpty,speeds.allSatisfy({$0 == [0x41,0x0D,0]}) else { throw AppFailure("A fresh stationary vehicle reading is required. Park and retry.") }
            if tripDiscovery { try await discoverTrip();return report }
            try await read(Self.engine)
            try await route("7E1","7E9")
            try await read(Self.gearbox)
            try await route("714","77E")
            for command in ["22F187","22F189"] { _ = try await exchange(command) }
            try await read(Self.cluster)
            try await readClusterFuel()
            clusterSessionAttempted=true
            let session = try await exchange("1003")
            if TelemetryELM.parse(session).payloads.contains(where:{$0.ecu == "77E" && $0.bytes.starts(with:[0x50,0x03])}) {
                try await read(Self.cluster)
                try await readClusterFuel()
            }
            try await restoreCluster()
            _ = try await exchange("ATFCSM0")
            let dsgResult=try await probeDSGMileage()
            report.status = "Finished. " + dsgResult + " No odometer saved. Reconnect to resume recording."
        } catch {
            report.status = error is CancellationError ? "Cancelled. Partial results retained." : error.localizedDescription
            // Cleanup runs outside cancellation before the caller releases ownership.
            if clusterSessionAttempted {
                let cleanup = Task { @MainActor in try await self.restoreCluster() }
                do { try await cleanup.value } catch { report.status += " " + error.localizedDescription }
            }
        }
        return report
    }
}
