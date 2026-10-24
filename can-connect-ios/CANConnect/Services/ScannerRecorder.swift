import Foundation
import Combine

@MainActor
final class ScannerRecorder: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var status = "Not connected"
    @Published private(set) var readings: [String: (value: Double, date: Date)] = [:]
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
    init(makeSession: (@MainActor () -> ScannerTransport)? = nil) { self.makeSession = makeSession }

    func value(_ key: String, at date: Date) -> Double? {
        guard connected, let reading = readings[key], (0...10).contains(date.timeIntervalSince(reading.date)) else { return nil }
        return reading.value
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
                if let expected = vehicle.vin, let detected = identity.vin, expected != detected {
                    needsUserCorrection = true
                    throw AppFailure("The scanner VIN differs from the selected vehicle. Add or choose the correct vehicle before recording.")
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
                self.vehicleID = vehicle.id; self.connected = true; self.connecting = false
                self.status = "\(settings.kind.shortTitle) connected · \(pids.count) signals"
                self.onConnected?()
                var nextRead: [Int:Date] = [:]
                var lastReceived = Date()
                var missing = Set<Int>()
                let vw = VWMeasuringBlocks { try await self.exchange($0,transport:transport) }
                var nextEnhanced = Date.distantPast
                while !Task.isCancelled {
                    for definition in pids where Date() >= (nextRead[definition.pid] ?? .distantPast) {
                        let reply = try await self.exchange(String(format:"01%02X",definition.pid),transport:transport)
                        try Task.checkCancellation()
                        let sample = OBDDecoder.decode(reply,pid:definition.pid,ecu:ecu)
                        let keys = OBDDecoder.signalKeys(pid:definition.pid)
                        for key in keys where sample?.signals[key] == nil { self.readings.removeValue(forKey:key) }
                        if sample == nil { missing.insert(definition.pid) } else { missing.remove(definition.pid) }
                        if let sample {
                            for (key,value) in sample.signals { self.readings[key] = (value,sample.timestamp) }
                            lastReceived = sample.timestamp; self.onSample?(sample)
                        }
                        let fast = [0x0C,0x0D,0x5E,0x70,0x78,0x7A,0x04,0x10].contains(definition.pid)
                        nextRead[definition.pid] = Date().addingTimeInterval(fast ? 0.5 : 3)
                        try await Task.sleep(nanoseconds:25_000_000)
                    }
                    if !enhancedControllers.isEmpty, Date() >= nextEnhanced {
                        for key in VWMeasurementDecoder.keys { self.readings.removeValue(forKey:key) }
                        do {
                            for sample in try await vw.read(controllers:enhancedControllers) {
                                try Task.checkCancellation()
                                for (key,value) in sample.signals { self.readings[key] = (value,sample.timestamp) }
                                lastReceived = sample.timestamp; self.onSample?(sample)
                            }
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            self.journal?.append(command:"VW",reply:"Enhanced measurements unavailable: \(error.localizedDescription)")
                            enhancedControllers = []
                            // Optional VW measurements must not leave standard reads
                            // silently using raw-CAN settings after a failed cleanup.
                            let recovery = try await self.exchange("010C",transport:transport)
                            guard OBDDecoder.decode(recovery,pid:0x0C,ecu:ecu) != nil else { throw error }
                        }
                        nextEnhanced = Date().addingTimeInterval(5)
                    }
                    guard missing.count < pids.count, Date().timeIntervalSince(lastReceived) < 20 else { throw AppFailure("The vehicle stopped supplying readings. Check ignition and reconnect.") }
                    try await Task.sleep(nanoseconds:50_000_000)
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
