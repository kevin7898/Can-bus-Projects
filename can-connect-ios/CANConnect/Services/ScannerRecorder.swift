import Foundation
import Combine

@MainActor
final class ScannerRecorder: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var status = "Not connected"
    @Published private(set) var readings: [String: (value: Double, date: Date)] = [:]
    private(set) var vehicleID: UUID?
    var onSample: ((OBDSample) -> Void)?
    var onDisconnect: ((String) -> Void)?
    private var work: Task<Void,Never>?
    private var session: ScannerTransport?
    private let makeSession: (@MainActor () -> ScannerTransport)?
    init(makeSession: (@MainActor () -> ScannerTransport)? = nil) { self.makeSession = makeSession }

    func value(_ key: String, at date: Date) -> Double? {
        guard connected, let reading = readings[key], (0...10).contains(date.timeIntervalSince(reading.date)) else { return nil }
        return reading.value
    }
    func connect(settings: ScannerSettings, vehicle: VehicleProfile) {
        disconnect()
        let transport: ScannerTransport
        if let makeSession { transport = makeSession() }
        else if settings.kind == .wifi { transport = ELMWiFiSession() }
        else { transport = ELMMXPlusSession(serial:settings.accessorySerial) }
        session = transport
        connecting = true; status = "Identifying vehicle…"
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let identity = try await transport.open(host:settings.host,port:settings.port)
                try Task.checkCancellation()
                guard !vehicle.isSample else { throw AppFailure("Choose a real vehicle before connecting a scanner.") }
                if let expected = vehicle.vin, let detected = identity.vin, expected != detected {
                    throw AppFailure("The scanner VIN differs from the selected vehicle. Add or choose the correct vehicle before recording.")
                }
                let pids = OBDDecoder.definitions.filter { identity.supportedPIDs.contains($0.pid) }
                guard !pids.isEmpty else { throw AppFailure("The vehicle reported no supported dashboard PIDs.") }
                self.vehicleID = vehicle.id; self.connected = true; self.connecting = false
                self.status = "\(settings.kind.shortTitle) connected · \(pids.count) signals"
                while !Task.isCancelled {
                    var received = false
                    for definition in pids {
                        let reply = try await transport.command(String(format:"01%02X",definition.pid))
                        try Task.checkCancellation()
                        if let sample = OBDDecoder.decode(reply,pid:definition.pid) {
                            for (key,value) in sample.signals { self.readings[key] = (value,sample.timestamp) }
                            received = true; self.onSample?(sample)
                        } else { self.readings.removeValue(forKey:definition.key) }
                        try await Task.sleep(nanoseconds:75_000_000)
                    }
                    guard received else { throw AppFailure("The vehicle stopped supplying readings. Check ignition and reconnect.") }
                }
            } catch is CancellationError {} catch {
                guard !Task.isCancelled else { return }
                self.connected = false; self.connecting = false; self.readings = [:]; self.vehicleID = nil
                self.status = error.localizedDescription; transport.disconnect(); self.onDisconnect?(self.status)
            }
        }
    }
    func disconnect() {
        work?.cancel(); work = nil; session?.disconnect(); session = nil
        connected = false; connecting = false; vehicleID = nil; readings = [:]; status = "Not connected"
    }
}
