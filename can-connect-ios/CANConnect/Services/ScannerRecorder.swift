import Foundation
import Combine

@MainActor
final class ScannerRecorder: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var status = "Not connected"
    @Published private(set) var readings: [String: (value: Double, date: Date)] = [:]
    @Published private(set) var supportedSignalKeys:Set<String> = []
    @Published private(set) var unsupportedSignalKeys:Set<String> = []
    @Published private(set) var diagnostics=OBDPollDiagnostics()
    private(set) var vehicleID: UUID?
    private(set) var failureRequiresAttention = false
    var onConnected: (() -> Void)?
    var onSample: ((OBDSample) -> Void)?
    var onDisconnect: ((String) -> Void)?
    private var work: Task<Void,Never>?
    private var pendingTeardown: Task<Void,Never>?
    private var session: ScannerTransport?
    private var journal: ScannerJournal?
    private let makeSession: (@MainActor () -> ScannerTransport)?
    // Scheduling uses elapsed time; recording timestamps remain calendar dates.
    private let pollClock: () -> ContinuousClock.Instant
    private let sampleDate: () -> Date
    private let measurementPause: (TimeInterval) async throws -> Void
    init(makeSession: (@MainActor () -> ScannerTransport)? = nil,
         pollClock: @escaping () -> ContinuousClock.Instant = { .now },
         sampleDate: @escaping () -> Date = Date.init,
         measurementPause: @escaping (TimeInterval) async throws -> Void = { seconds in
             try await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))
         }) {
        self.makeSession = makeSession; self.pollClock = pollClock; self.sampleDate = sampleDate; self.measurementPause = measurementPause
    }

    func value(_ key: String, at date: Date) -> Double? {
        guard connected, let reading = readings[key], (0...max(OBDDecoder.freshness(for:key),VWMeasurementDecoder.freshness(for:key))).contains(date.timeIntervalSince(reading.date)) else { return nil }
        return reading.value
    }
    /// One bounded, read-only identification session for onboarding. The VIN is
    /// returned to the caller and is never written to the scanner journal.
    func identify(settings:ScannerSettings) async throws -> ScannerIdentity {
        disconnect()
        await pendingTeardown?.value
        let transport:ScannerTransport
        if let makeSession { transport=makeSession() }
        else if settings.kind == .wifi { transport=ELMWiFiSession() }
        else { transport=ELMMXPlusSession(serial:settings.accessorySerial,journal:nil,restoreCANDefaults:false) }
        defer { transport.disconnect() }
        return try await transport.open(host:settings.host,port:settings.port)
    }
    func connect(settings: ScannerSettings, vehicle: VehicleProfile) {
        disconnect()
        failureRequiresAttention = false
        let previous = pendingTeardown
        journal = makeSession == nil ? ScannerJournal() : nil
        let transport: ScannerTransport
        if let makeSession { transport = makeSession() }
        else if settings.kind == .wifi { transport = ELMWiFiSession() }
        else { transport = ELMMXPlusSession(serial:settings.accessorySerial,journal:journal,restoreCANDefaults:Jetta2014Profile.matches(vehicle)) }
        session = transport
        connecting = true; status = "Identifying vehicle…"
        work = Task { [weak self] in
            guard let self else { return }
            var needsUserCorrection = false
            do {
                // Cancellation cleanup must finish before iOS opens the same MFi protocol again.
                await previous?.value
                try Task.checkCancellation()
                self.pendingTeardown = nil
                let identity = try await transport.open(host:settings.host,port:settings.port)
                try Task.checkCancellation()
                guard !vehicle.isSample else {
                    needsUserCorrection = true
                    throw AppFailure("Choose a real vehicle before connecting a scanner.")
                }
                if let expected = vehicle.vin, !expected.isEmpty, expected != identity.vin {
                    needsUserCorrection = true
                    throw AppFailure("The scanner VIN differs from the selected vehicle or could not be verified. Add or choose the correct vehicle before recording.")
                }
                let jetta = Jetta2014Profile.matches(vehicle)
                let ecu: String? = jetta ? "7E8" : nil
                var supported = identity.supportedPIDs
                var enhancedControllers = Set<VWController>()
                if jetta {
                    guard identity.vehicleProtocol.uppercased().contains("CAN"), !identity.vehicleProtocol.contains("29") else {
                        needsUserCorrection = true
                        throw AppFailure("The 2014 TDI profile requires the vehicle's 11-bit CAN protocol.")
                    }
                    // Retain the anonymous reply to diagnose conflicting engine/DSG RPM.
                    _ = try await self.exchange("010C",transport:transport)
                    for setting in ["ATH1","ATD0","ATSH7E0","ATCRA7E8"] {
                        let reply = try await self.exchange(setting,transport:transport)
                        guard reply.uppercased().contains("OK") else { throw AppFailure("The adapter rejected engine ECU selection: \(setting).") }
                    }
                    supported = []
                    for base in stride(from:0,through:224,by:32) {
                        if base != 0 && !supported.contains(base) { break }
                        let reply = try await self.exchange(String(format:"01%02X",base),transport:transport)
                        for payload in ELMResponses.payloads(reply,ecu:ecu) {
                            let anonymous = payload.map { String(format:"%02X",$0) }.joined()
                            supported += ELMIdentityParser.supportedPIDs(anonymous,base:base)
                        }
                    }
                    if settings.kind == .obdLinkMXPlus {
                        for controller in VWController.allCases {
                            for setting in ["ATSH\(controller.obdRequest)","ATCRA\(controller.obdResponse)"] {
                                let reply = try await self.exchange(setting,transport:transport)
                                guard reply.contains("OK") else { throw AppFailure("Could not select the VW controller for identification.") }
                            }
                            let calibration = try await self.exchange("0904",transport:transport)
                            if controller.matchesCalibration(calibration) { enhancedControllers.insert(controller) }
                        }
                        for setting in ["ATSH7E0","ATCRA7E8"] { _ = try await self.exchange(setting,transport:transport) }
                    }
                }
                let pids = OBDDecoder.definitions.filter { supported.contains($0.pid) }
                guard !pids.isEmpty else { throw AppFailure("The vehicle reported no supported dashboard PIDs.") }
                var supportedKeys=Set(pids.flatMap { OBDDecoder.signalKeys(pid:$0.pid) })
                if enhancedControllers.contains(.engine) { supportedKeys.formUnion(VWMeasurementDecoder.engineKeys) }
                if enhancedControllers.contains(.dsg) { supportedKeys.insert("dsgFluidC") }
                if supportedKeys.contains("barometricKpa") &&
                    (supportedKeys.contains("boostAbsoluteKpa") || supportedKeys.contains("mapKpa")) {
                    supportedKeys.insert("boostGaugeKpa")
                }
                self.supportedSignalKeys=supportedKeys
                var knownKeys=OBDDecoder.keys;knownKeys.insert("boostGaugeKpa")
                self.unsupportedSignalKeys=knownKeys.subtracting(supportedKeys)
                self.vehicleID = vehicle.id; self.connected = true; self.connecting = false
                self.status = "\(settings.kind.shortTitle) connected · \(pids.count) signals"
                self.onConnected?()
                // A generic ECU exposing only slow PIDs must not time out before
                // its next scheduled response. RPM-capable ECUs retain 20 seconds.
                let responseTimeout = max(20,(pids.map { OBDDecoder.pollInterval(pid:$0.pid) }.min() ?? 3)+15)
                var lastReceived = self.pollClock()
                var missing = Set<Int>()
                var scheduler=OBDPollScheduler(pids:pids.map(\.pid),now:self.pollClock())
                let vw = VWMeasuringBlocks(exchange:{ try await self.exchange($0,transport:transport) },
                    pause:self.measurementPause,clock:self.pollClock,sampleDate:self.sampleDate,
                    report:{ self.journal?.append(command:"VW",reply:$0) })
                var nextEnhanced: [VWController:ContinuousClock.Instant] = [:]
                while !Task.isCancelled {
                    let now=self.pollClock()
                    if let request=scheduler.next(at:now) {
                        let started=self.pollClock()
                        do {
                            let reply=try await self.exchange(String(format:"01%02X",request.pid),transport:transport)
                            try Task.checkCancellation()
                            let finished=self.pollClock()
                            let sample=OBDDecoder.decode(reply,pid:request.pid,at:self.sampleDate(),ecu:ecu)
                            let outcome=OBDPollScheduler.classify(reply:reply,pid:request.pid,decoded:sample,ecu:ecu)
                            scheduler.record(request,outcome:outcome,responseLatency:OBDPollScheduler.seconds(started.duration(to:finished)),at:finished)
                            if outcome == .pending {
                                // No verified drain for a delayed response exists
                                // on this channel: do not issue a different PID.
                                throw AppFailure("The ECU response is pending. Reconnecting before another request.")
                            }
                            if let sample {
                                missing.remove(request.pid)
                                for (key,value) in sample.signals { self.readings[key]=(value,sample.timestamp) }
                                lastReceived=finished;self.onSample?(sample)
                            } else { missing.insert(request.pid) }
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            let finished=self.pollClock()
                            scheduler.record(request,outcome:.timeout,responseLatency:OBDPollScheduler.seconds(started.duration(to:finished)),at:finished)
                            missing.insert(request.pid);self.diagnostics=scheduler.diagnostics(at:finished)
                            // A transport failure has no verified prompt boundary.
                            // Reopen through the existing teardown barrier before
                            // another PID can consume a late reply.
                            throw error
                        }
                        self.diagnostics=scheduler.diagnostics(at:self.pollClock())
                    }
                    let enhancedNow=self.pollClock()
                    let due=enhancedControllers.filter { nextEnhanced[$0].map { enhancedNow >= $0 } ?? true }
                    if let controller=due.sorted(by:{$0.rawValue<$1.rawValue}).first,
                       scheduler.enhancedWindowOpportunity(at:enhancedNow) {
                        let windowStarted=self.pollClock()
                        do {
                            let samples = try await vw.read(controllers:Set([controller]))
                            for sample in samples {
                                try Task.checkCancellation()
                                for (key,value) in sample.signals { self.readings[key] = (value,sample.timestamp) }
                                lastReceived = self.pollClock(); self.onSample?(sample)
                            }
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            self.journal?.append(command:"VW",reply:"Enhanced measurements unavailable: \(error.localizedDescription)")
                            // A cleanup error does not permanently disable enhanced
                            // polling. Re-establish and verify ordinary OBD first.
                            for setting in VWMeasuringBlocks.restoreCommands {
                                let reply = try await self.exchange(setting,transport:transport)
                                guard reply.trimmingCharacters(in:.whitespacesAndNewlines).uppercased() == "OK" else { throw error }
                            }
                            let recovery = try await self.exchange("010C",transport:transport)
                            guard let sample=OBDDecoder.decode(recovery,pid:0x0C,at:self.sampleDate(),ecu:ecu) else { throw error }
                            for (key,value) in sample.signals { self.readings[key]=(value,sample.timestamp) }
                            lastReceived=self.pollClock();self.onSample?(sample)
                        }
                        let windowEnded=self.pollClock()
                        scheduler.recordEnhancedWindow(seconds:OBDPollScheduler.seconds(windowStarted.duration(to:windowEnded)))
                        scheduler.prioritizeCore(at:windowEnded)
                        self.diagnostics=scheduler.diagnostics(at:windowEnded)
                        nextEnhanced[controller]=windowEnded.advanced(by:.seconds(controller.pollInterval))
                    }
                    guard missing.count < pids.count,lastReceived.duration(to:self.pollClock()) < .seconds(responseTimeout) else { throw AppFailure("The vehicle stopped supplying readings. Check ignition and reconnect.") }
                    try await Task.sleep(nanoseconds:20_000_000)
                }
            } catch is CancellationError {} catch {
                guard !Task.isCancelled else { return }
                // Transport timeouts (including an explicit Connect while the
                // car is off) belong in the existing status, not a modal alert.
                // A wrong vehicle/profile still requires the user's attention.
                self.failureRequiresAttention = needsUserCorrection
                self.connected = false; self.connecting = false; self.readings = [:]; self.vehicleID = nil
                self.status = error.localizedDescription; self.journal?.append(command:"ERROR",reply:self.status)
                transport.disconnect(); self.onDisconnect?(self.status)
            }
        }
    }
    private func exchange(_ command: String, transport: ScannerTransport) async throws -> String {
        let reply = try await transport.command(command)
        if !(transport is ELMMXPlusSession) { journal?.append(command:command,reply:reply) }
        return reply
    }
    func disconnect() {
        if let work {
            work.cancel()
            if let transport = session as? ELMMXPlusSession {
                // Keep the logical channel alive until TP 2.0 cancellation has
                // restored ordinary OBD settings. A reconnect awaits this task.
                pendingTeardown = Task { await work.value; transport.disconnect() }
            } else { session?.disconnect(); pendingTeardown = work }
        } else { session?.disconnect() }
        work = nil; session = nil
        connected = false; connecting = false; vehicleID = nil; readings = [:]; status = "Not connected"; journal = nil
    }
}
