import Foundation

/// Stable facade in ScannerRecorder owns this engine. Only this task may issue
/// commands; the explicit inFlight guard remains set across suspension points.
@MainActor
final class RebuiltScannerEngine {
    enum State: String { case idle,connecting,discovering,validatingIdentity,ready,recording,recovering,stopping,failed }
    private(set) var state:State = .idle
    private var task:Task<Void,Never>?
    private var inFlight=false
    private var currentCommand="none"
    private var generation=UUID()
    private let epoch=UUID()
    private let sessionID=UUID()
    private let wallAnchor=Date()
    private let monotonicAnchor:Double
    private var sequence:UInt64=0
    private var lastExchangeID:UUID?
    private var lastLatency=0.0
    private var lastReceipt:TelemetryTime?
    private var rates=TelemetryRates()
    private(set) var rateWindows:[String:[Int:TelemetryRates.Summary]]=[:]
    private let transport:ScannerTransport
    private let vehicle:VehicleProfile
    private let settings:ScannerSettings
    private var log:TelemetryLog?
    private let clock:()->Double
    var onReady:((Set<Int>,String,Bool)->Void)?
    var onSample:((OBDSample)->Void)?
    var onFailure:((String)->Void)?
    var onRates:((Double,Int)->Void)?
    init(transport:ScannerTransport,vehicle:VehicleProfile,settings:ScannerSettings,
         clock:@escaping ()->Double = { ProcessInfo.processInfo.systemUptime }) {
        self.transport=transport;self.vehicle=vehicle;self.settings=settings;self.clock=clock;self.monotonicAnchor=clock()
    }
    private func time()->TelemetryTime { .init(epoch:epoch,monotonic:clock(),wall:Date()) }
    private func exchange(_ request:TelemetryRequest) async throws -> String {
        try Task.checkCancellation()
        guard !inFlight else { throw TelemetryFailure.busy }
        inFlight=true;currentCommand=request.command; defer { inFlight=false }
        let token=generation, start=time()
        do {
            let reply=try await transport.command(request.command)
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            let receipt=time();lastReceipt=receipt;lastLatency=max(0,receipt.monotonic-start.monotonic)
            sequence += 1
            let evidence=TelemetryExchange(sessionID:sessionID,sequence:sequence,request:request,reply:reply,start:start,end:receipt,generation:token,outcome:"prompt")
            lastExchangeID=evidence.id
            try await log?.append(evidence,type:1)
            try request.validate(reply)
            return reply
        } catch {
            // A failed transport boundary cannot be reused by a later command.
            generation=UUID();transport.disconnect();throw error
        }
    }
    struct ClusterTiming:Codable {
        var windows=0;var failures=0;var lastSeconds=0.0;var maximumSeconds=0.0
    }
    private(set) var clusterTiming=ClusterTiming()
    private func clusterPayload(_ reply:String,did:UInt16)->[UInt8]? {
        let parsed=TelemetryELM.parse(reply)
        let prefix:[UInt8]=[0x62,UInt8(did >> 8),UInt8(did & 255)]
        guard parsed.rejected == 0,!parsed.payloads.isEmpty,
              parsed.payloads.allSatisfy({$0.ecu == "77E" && $0.bytes.starts(with:prefix)}),
              let first=parsed.payloads.first?.bytes,parsed.payloads.allSatisfy({$0.bytes == first}) else { return nil }
        return Array(first.dropFirst(3))
    }
    private func clusterWindow(ecu:String,verify:Bool) async throws -> Bool {
        let start=clock()
        for c in ["ATFCSM0","ATSH714","ATCRA77E","ATFCSH714","ATFCSD300000","ATFCSM1"] { _ = try await exchange(.cluster(c)) }
        var valid=true
        if verify {
            let part=try await exchange(.cluster("22F187"))
            let version=try await exchange(.cluster("22F189"))
            valid=clusterPayload(part,did:0xF187).map { String(decoding:$0,as:UTF8.self).trimmingCharacters(in:.whitespaces) } == "5C6920853A" &&
                clusterPayload(version,did:0xF189).map { String(decoding:$0,as:UTF8.self) } == "0809"
        }
        if valid {
            for (command,did,key,scale) in [("22229A",UInt16(0x229A),"clusterFuelLitres",0.125),("222203",UInt16(0x2203),"clusterOdometerCoarseKM",10.0)] {
                let reply=try await exchange(.cluster(command))
                guard let data=clusterPayload(reply,did:did),data.count == 2,data != [255,255] else { valid=false;continue }
                let value=Double(Int(data[0])*256+Int(data[1]))*scale
                guard key != "clusterFuelLitres" || value <= 200 else { valid=false;continue }
                var sample=OBDSample(timestamp:wallAnchor.addingTimeInterval((lastReceipt?.monotonic ?? clock())-monotonicAnchor),signals:[key:value],command:command,reply:TelemetryPrivacy.reply(command:command,reply:reply),requestHeader:"714",responseHeader:"77E")
                sample.clockEpoch=epoch;sample.monotonicTime=lastReceipt?.monotonic;sample.exchangeID=lastExchangeID
                onSample?(sample)
            }
        }
        _ = try await exchange(.cluster("ATFCSM0"))
        for request in try TelemetryRequest.route(response:ecu) { _ = try await exchange(request) }
        clusterTiming.windows += 1;clusterTiming.lastSeconds=clock()-start
        clusterTiming.maximumSeconds=max(clusterTiming.maximumSeconds,clusterTiming.lastSeconds)
        if !valid { clusterTiming.failures += 1 }
        try await log?.append(TelemetryEvent("clusterWindowSeconds:\(clusterTiming.lastSeconds):valid:\(valid)",at:time()),type:2,important:true)
        return valid
    }
    func start(after previous:Task<Void,Never>?) {
        task=Task { [weak self] in
            guard let self else { return }
            await previous?.value
            var openingTransport=false
            do {
                try Task.checkCancellation()
                state = .connecting
                guard !vehicle.isSample else { throw TelemetryFailure.identityMismatch }
                let directory=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
                    .appendingPathComponent("CANConnect/Telemetry")
                log=try TelemetryLog(url:directory.appendingPathComponent(sessionID.uuidString+".dlt"),header:.init(recordingID:sessionID,vehicleID:vehicle.id,epoch:epoch))
                // Platform open performs the legacy identity handshake as well.
                // Its responses are sanitized at the existing journal boundary.
                openingTransport=true
                _ = try await transport.open(host:settings.host,port:settings.port)
                openingTransport=false
                try Task.checkCancellation()
                state = .discovering
                for command in ["ATD","ATE0","ATL0","ATS1","ATH1","ATD0","ATCAF1","ATSP0"] {
                    _ = try await exchange(.configuration(command))
                }
                let first=try await exchange(.standard([0]))
                let candidates=TelemetryELM.supported(TelemetryELM.parse(first).payloads,base:0)
                let protocolReply=try await exchange(.information("ATDPN"))
                let protocolCode=protocolReply.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
                guard ["6","A6","8","A8"].contains(protocolCode) else { throw TelemetryFailure.unsupported }
                // Only verified ISO 15765 11-bit routing is enabled. Parser
                // supports 29-bit fixtures, but routing requires hardware proof.
                let ecu=try TelemetryELM.primaryECU(candidates)
                try await log?.append(TelemetryEvent("selectedECU:"+ecu,at:time()),type:2,important:true)
                // VIN is collected on broadcast before narrowing to one ECU.
                state = .validatingIdentity
                let vinReply=try await exchange(.vin)
                let identities=try TelemetryELM.identities(TelemetryELM.parse(vinReply).payloads)
                let observed=identities.values.first
                if let expected=vehicle.vin,!expected.isEmpty {
                    guard let observed else { throw TelemetryFailure.missingIdentity }
                    guard expected.uppercased() == observed else { throw TelemetryFailure.identityMismatch }
                }
                for request in try TelemetryRequest.route(response:ecu) { _ = try await exchange(request) }
                var supported=Set<Int>()
                for base in stride(from:0,through:224,by:32) {
                    if base != 0 && !supported.contains(base) { break }
                    let reply=try await exchange(.standard([base]))
                    supported.formUnion(TelemetryELM.supported(TelemetryELM.parse(reply).payloads,base:base)[ecu] ?? [])
                }
                supported=Set(supported.filter { TelemetryPID.lengths[$0] != nil })
                guard !supported.isEmpty else { throw TelemetryFailure.unsupported }
                state = .ready
                try await log?.append(TelemetryEvent(observed != nil && observed == vehicle.vin ? "identityVerified":"manualIdentity",at:time()),type:2,important:true)
                onReady?(supported,ecu,observed != nil && observed == vehicle.vin)
                var scheduler=TelemetryScheduler(supported:supported,jetta:Jetta2014Profile.matches(vehicle),now:clock())
                var clusterEnabled=vehicle.year == 2014 && ["volkswagen","vw"].contains(vehicle.make.lowercased()) && vehicle.model.lowercased() == "jetta" && observed != nil && observed == vehicle.vin && ["6","A6"].contains(protocolCode)
                var clusterVerified=false, nextCluster=clock()+15
                var lastValid=clock(), lastPublish=clock()
                while !Task.isCancelled {
                    if let work=scheduler.next(now:clock()) {
                        let reply=try await exchange(.standard(work.pids)), date=wallAnchor.addingTimeInterval((lastReceipt?.monotonic ?? clock())-monotonicAnchor)
                        var decoded:[Int:[UInt8]]=[:], conflict=Set<Int>()
                        for payload in TelemetryELM.parse(reply).payloads where payload.ecu == ecu {
                            guard let values=try? TelemetryPID.split(payload,requested:Set(work.pids)) else { continue }
                            for (pid,bytes) in values {
                                if let old=decoded[pid],old != bytes { conflict.insert(pid) }
                                decoded[pid]=bytes
                            }
                        }
                        for pid in conflict { decoded.removeValue(forKey:pid) }
                        var valid=Set<Int>()
                        for pid in work.pids {
                            guard let bytes=decoded[pid],var sample=OBDDecoder.decodePayload(bytes,pid:pid,at:date,ecu:ecu,command:try TelemetryRequest.standard(work.pids).command,reply:reply) else { continue }
                            sample.clockEpoch=epoch;sample.monotonicTime=lastReceipt?.monotonic;sample.exchangeID=lastExchangeID
                            valid.insert(pid);onSample?(sample);lastValid=clock()
                        }
                        scheduler.record(work,valid:valid,latency:lastLatency,now:clock())
                        rates.record(pids:work.pids,valid:valid,latency:lastLatency,at:clock())
                        rateWindows=["10s":rates.summaries(now:clock(),window:10),"60s":rates.summaries(now:clock(),window:60)]
                        if clock()-lastPublish >= 0.25 { onRates?(scheduler.driveHz,scheduler.exchanges);lastPublish=clock() }
                    }
                    if clusterEnabled,clock() >= nextCluster {
                        // Single transport owner; restore primary routing before the next scheduler request.
                        // Any malformed/unsupported window disables polling for this connection.
                        clusterEnabled=try await clusterWindow(ecu:ecu,verify:!clusterVerified)
                        clusterVerified=clusterEnabled;nextCluster=clock()+60
                        if clusterTiming.lastSeconds > 3 { clusterEnabled=false }
                    }
                    guard clock()-lastValid < 30 else { throw TelemetryFailure.malformed }
                    try await Task.sleep(for:.milliseconds(10))
                }
            } catch is CancellationError {} catch {
                let phase=openingTransport ? "opening."+transport.openingStage.rawValue:state.rawValue+":"+currentCommand
                // Persist only a fixed category and a reviewed phase/command, never
                // arbitrary error text (which can contain hostnames or identity).
                try? await log?.append(TelemetryEvent("failure:"+phase+":"+Self.failureCategory(error),at:time()),type:2,important:true)
                state = .failed
                onFailure?(Self.failureMessage(error,opening:openingTransport))
            }
            transport.disconnect()
            if let log {
                do { try await log.append(TelemetryEvent("disconnected",at:time()),type:2,important:true); _ = try await log.finish() }
                catch { onFailure?("Telemetry log could not be finalized. Its valid prefix remains recoverable.") }
            }
        }
    }
    static func failureCategory(_ error:Error)->String {
        if error as? TelemetryFailure == .storage { return "storage" }
        let text=error.localizedDescription.lowercased()
        if text.contains("timed out") { return "timeout" }
        if text.contains("disconnected") { return "disconnected" }
        if text.contains("unavailable") || text.contains("no authenticated") { return "unavailable" }
        if text.contains("rejected configuration") { return "configurationRejected" }
        return error is AppFailure ? "adapterFailure":"acquisitionFailure"
    }
    static func failureMessage(_ error:Error,opening:Bool)->String {
        switch error {
        case TelemetryFailure.identityMismatch: return "The scanner VIN differs from the selected vehicle. Recording is blocked."
        case TelemetryFailure.missingIdentity: return "The vehicle did not provide a VIN. The saved identity cannot be verified."
        case TelemetryFailure.ambiguous: return "The vehicle returned ambiguous ECU identity or capability data. Recording is blocked."
        case TelemetryFailure.unsupported: return "This protocol or ECU routing is not yet supported by the development engine."
        case TelemetryFailure.storage: return "Recording storage is unavailable. Saved evidence remains on this iPhone; check available storage before reconnecting."
        case let failure as AppFailure: return failure.localizedDescription
        default: return opening ? "Could not open the scanner connection. Check adapter power, Bluetooth pairing and ignition, and close other OBD apps before reconnecting.":"Scanner acquisition failed. Reconnect to resume; saved evidence remains available."
        }
    }
    func stop()->Task<Void,Never>? {
        state = .stopping;task?.cancel();generation=UUID()
        let previous=task;task=nil;return previous
    }
}
