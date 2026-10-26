import Foundation
import Network

// Standard diagnostic identification only. No DTC clearing, coding, or security access.
enum ELMIdentityParser {
    static func payloads(_ reply: String) -> [[UInt8]] {
        reply.uppercased().components(separatedBy:.newlines).compactMap { raw in
            var line = raw.replacingOccurrences(of:">",with:"").trimmingCharacters(in:.whitespaces)
            if let colon = line.firstIndex(of:":") { line = String(line[line.index(after:colon)...]) }
            var tokens=line.split(whereSeparator:\.isWhitespace).map(String.init)
            if let first=tokens.first, [3,8].contains(first.count),first.allSatisfy(\.isHexDigit) { tokens.removeFirst() }
            if let first=tokens.first,first.count==2,let pci=UInt8(first,radix:16) {
                if pci & 0xF0 == 0x10,tokens.count >= 2 { tokens.removeFirst(2) }
                else if pci & 0xF0 == 0x20 { tokens.removeFirst() }
            }
            let hex = tokens.isEmpty ? line.filter { !$0.isWhitespace } : tokens.joined()
            guard hex.count >= 2, hex.count % 2 == 0, hex.allSatisfy({$0.isHexDigit}) else { return nil }
            var bytes: [UInt8] = []; var i = hex.startIndex
            while i < hex.endIndex { let end = hex.index(i,offsetBy:2); guard let byte = UInt8(hex[i..<end],radix:16) else { return nil }; bytes.append(byte); i = end }
            return bytes
        }
    }
    static func vin(_ reply: String) throws -> String? {
        var current: [UInt8] = [], candidates = Set<String>()
        func collect() {
            let letters = current.filter { $0 != 0 }.map { Character(UnicodeScalar($0)) }
            if let value = try? VIN.normalized(String(letters)) { candidates.insert(value) }
        }
        for bytes in payloads(reply) {
            if bytes.count >= 3 && bytes[0] == 0x49 && bytes[1] == 0x02 {
                if bytes[2] == 1 && !current.isEmpty { collect(); current = [] }
                current += bytes.dropFirst(3)
            } else if !current.isEmpty { current += bytes }
        }
        collect()
        guard candidates.count <= 1 else { throw AppFailure("The scanner reported different VINs. Review the vehicle manually.") }
        return candidates.first
    }
    static func respondingAddress(_ reply:String)->String? {
        for raw in reply.uppercased().components(separatedBy:.newlines) {
            let tokens=raw.trimmingCharacters(in:.whitespacesAndNewlines).split(whereSeparator:\.isWhitespace)
            guard let first=tokens.first,[3,8].contains(first.count),first.allSatisfy(\.isHexDigit) else { continue }
            if raw.contains("49 02") || raw.replacingOccurrences(of:" ",with:"").contains("4902") { return String(first) }
        }
        return nil
    }
    static func supportedPIDs(_ reply: String, base: Int) -> [Int] {
        var pids = Set<Int>()
        for b in payloads(reply) where b.count >= 6 && b[0] == 0x41 && Int(b[1]) == base {
            let mask = UInt32(b[2]) << 24 | UInt32(b[3]) << 16 | UInt32(b[4]) << 8 | UInt32(b[5])
            for i in 0..<32 where mask & (UInt32(1) << (31-i)) != 0 { pids.insert(base+i+1) }
        }
        return pids.sorted()
    }
}

@MainActor
protocol ScannerTransport: AnyObject {
    func open(host: String, port: UInt16) async throws -> ScannerIdentity
    func command(_ text: String) async throws -> String
    func disconnect()
}

// The same reviewed identity and read-only configuration for every transport.
@MainActor
enum ELMIdentification {
    static func read(restoreCANDefaults: Bool = false, command: (String) async throws -> String) async throws -> ScannerIdentity {
        let adapter = try await command("ATI")
        // AT D restores protocol-independent defaults, including stale header
        // and receive-filter overrides, without resetting the MFi connection.
        // ELM327 datasheet: D (set all to Defaults). Do not impose 7DF/11-bit
        // addressing before automatic protocol discovery on generic vehicles.
        let settings = ["ATD","ATE0","ATL0","ATS1","ATH1","ATCAF1","ATSP0"]
        for setting in settings {
            let response = try await command(setting)
            guard response.uppercased().contains("OK") else { throw AppFailure("The adapter rejected configuration \(setting). Check ELM327 compatibility.") }
        }
        let vinReply = try await command("0902")
        let vin = try ELMIdentityParser.vin(vinReply)
        let respondingAddress=ELMIdentityParser.respondingAddress(vinReply)
        let headersOff=try await command("ATH0")
        guard headersOff.uppercased().contains("OK") else { throw AppFailure("The adapter could not restore header-free diagnostic replies.") }
        var supported: [Int] = []
        for base in stride(from:0,through:224,by:32) {
            if base != 0 && !supported.contains(base) { break }
            let response = try await command(String(format:"01%02X",base))
            supported += ELMIdentityParser.supportedPIDs(response,base:base)
        }
        let vehicleProtocol = try await command("ATDP")
        guard vin != nil || !supported.isEmpty else { throw AppFailure("The adapter replied, but the vehicle did not provide identification. Check ignition and connection, or continue manually.") }
        return ScannerIdentity(vin:vin,adapter:Self.clean(adapter),vehicleProtocol:["ISO","CAN","J1850","SAE"].contains(where:{vehicleProtocol.uppercased().contains($0)}) ? Self.clean(vehicleProtocol) : "Unknown",supportedPIDs:supported.filter {$0 % 32 != 0},respondingAddress:respondingAddress,observedAt:Date())
    }
    private static func clean(_ value: String) -> String { value.components(separatedBy:.newlines).filter {!$0.uppercased().hasPrefix("AT") && !$0.isEmpty}.joined(separator:" ").trimmingCharacters(in:.whitespacesAndNewlines) }
}

@MainActor
final class ELMWiFiSession: ScannerTransport {
    private var connection: NWConnection?
    private var opening: CheckedContinuation<Void, Error>?
    private var waiting: CheckedContinuation<String, Error>?
    private var timeout: Task<Void,Never>?
    private var buffer = ""
    private var pendingCommand = ""
    private var ready = false
    func identify(host: String, port: UInt16) async throws -> ScannerIdentity {
        defer { disconnect() }
        return try await open(host:host,port:port)
    }
    func open(host: String, port: UInt16) async throws -> ScannerIdentity {
        guard Self.isLocalHost(host), port > 0 else { throw AppFailure("Enter the scanner's local IPv4 address (or .local hostname) and TCP port from its instructions.") }
        try await connect(host:host,port:port)
        return try await ELMIdentification.read(command:command)
    }
    nonisolated static func isLocalHost(_ input: String) -> Bool {
        let host = input.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
        if host == "localhost" || host == "127.0.0.1" { return true }
        if host.hasSuffix(".local"), host.count < 254 {
            let labels = host.split(separator:".",omittingEmptySubsequences:false)
            return labels.allSatisfy { !$0.isEmpty && $0.count <= 63 && $0.first != "-" && $0.last != "-" && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }
        }
        let labels = host.split(separator:".",omittingEmptySubsequences:false)
        guard labels.count == 4, labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return false }
        let parts = labels.compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({(0...255).contains($0)}) else { return false }
        return parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 169 && parts[1] == 254)
    }
    private func connect(host: String, port: UInt16) async throws {
        try Task.checkCancellation()
        disconnect()
        let c = NWConnection(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:port)!,using:.tcp)
        connection = c
        try await withCheckedThrowingContinuation { continuation in
            opening = continuation
            c.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.connection === c else { return }
                    switch state {
                    case .ready: self.ready = true; self.timeout?.cancel(); let pending = self.opening; self.opening = nil; pending?.resume(); self.receive()
                    case .failed(let error): self.fail(error)
                    case .cancelled: self.fail(CancellationError())
                    default: break
                    }
                }
            }
            armTimeout(); c.start(queue:.main)
        }
    }
    func command(_ text: String) async throws -> String {
        try Task.checkCancellation()
        guard ready, waiting == nil, let c = connection else { throw AppFailure("Scanner connection is unavailable.") }
        buffer = ""
        return try await withCheckedThrowingContinuation { continuation in
            waiting = continuation; pendingCommand = text; armTimeout()
            c.send(content:Data((text+"\r").utf8),completion:.contentProcessed { [weak self] error in
                if let error { Task { @MainActor in if self?.connection === c { self?.fail(error) } } }
            })
        }
    }
    private func receive() {
        guard let c = connection else { return }
        c.receive(minimumIncompleteLength:1,maximumLength:4096) { [weak self] data,_,complete,error in
            Task { @MainActor in
                guard let self, self.connection === c else { return }
                if let data { self.buffer += String(decoding:data,as:UTF8.self) }
                if self.buffer.count > 64_000 { self.fail(AppFailure("The adapter response was too large.")); return }
                while let end = self.buffer.firstIndex(of:">") {
                    let response = String(self.buffer[..<end])
                    self.buffer = String(self.buffer[self.buffer.index(after:end)...])
                    let normalized = response.uppercased().replacingOccurrences(of:self.pendingCommand,with:"").trimmingCharacters(in:.whitespacesAndNewlines)
                    let configuration = self.pendingCommand.hasPrefix("AT") && !["ATI","ATDP","ATZ"].contains(self.pendingCommand)
                    let accepted = !normalized.isEmpty && (!configuration || normalized.contains("OK") || normalized.contains("?") || normalized.contains("ERROR"))
                    if accepted, let pending = self.waiting {
                        self.waiting = nil; self.timeout?.cancel(); pending.resume(returning:response)
                    }
                }
                if let error { self.fail(error) }
                else if complete { self.fail(AppFailure("The scanner disconnected.")) }
                else { self.receive() }
            }
        }
    }
    private func armTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds:12_000_000_000)
            guard !Task.isCancelled else { return }
            self?.fail(AppFailure("Scanner timed out. Join its Wi-Fi network, allow local network access, and check the address and port."))
        }
    }
    private func fail(_ error: Error) {
        timeout?.cancel(); ready = false
        let start = opening; opening = nil; start?.resume(throwing:error)
        let request = waiting; waiting = nil; request?.resume(throwing:error)
        let c = connection; connection = nil; c?.stateUpdateHandler = nil; c?.cancel()
    }
    func disconnect() { fail(CancellationError()) }
}

struct VINLookupResult { var vehicle: VehicleProfile; var partial: Bool }
struct VINLookup {
    private struct Response: Decodable { var Results: [[String:String?]] }
    func decode(_ input: String) async throws -> VINLookupResult {
        _ = try VIN.normalized(input)
        throw AppFailure("Cloud VIN lookup is disabled. Validate the VIN locally or finish setup manually.")
    }
    static func parse(_ data: Data, vin: String) throws -> VINLookupResult {
        let response = try JSONDecoder().decode(Response.self,from:data)
        guard let row = response.Results.first else { throw AppFailure("No details were returned. Continue manually.") }
        func field(_ key: String) -> String { (row[key] ?? nil) ?? "" }
        var v = VehicleProfile(); v.vin = try VIN.normalized(vin)
        v.make = field("Make"); v.model = field("Model"); v.year = Int(field("ModelYear")); v.trim = field("Trim")
        v.engine = [field("DisplacementL").isEmpty ? "" : field("DisplacementL")+" L",field("EngineModel")].filter {!$0.isEmpty}.joined(separator:" ")
        v.transmission = field("TransmissionStyle"); v.identificationSource = "VIN lookup · NHTSA suggestions"
        let fuel = field("FuelTypePrimary").lowercased()
        v.fuel = fuel.contains("diesel") ? .diesel : fuel.contains("electric") ? .electric : fuel.contains("gasoline") ? .gasoline : .unknown
        if !field("FuelTypeSecondary").isEmpty && field("FuelTypeSecondary").lowercased().contains("electric") { v.fuel = .hybrid }
        let body = (field("VehicleType")+" "+field("BodyClass")).lowercased()
        v.kind = body.contains("motorcycle") ? .motorcycle : body.contains("pickup") ? .pickup : body.contains("van") ? .van : .car
        return VINLookupResult(vehicle:v,partial:field("ErrorCode") != "0" || v.make.isEmpty || v.model.isEmpty)
    }
}
