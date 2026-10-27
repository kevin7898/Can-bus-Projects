import Foundation

public enum TelemetryFailure: Error, Equatable { case invalidRequest, malformed, ambiguous, unsupported, identityMismatch, missingIdentity, busy, storage, invalidTransition }

public struct TelemetryTime: Codable, Equatable, Sendable {
    public var epoch: UUID
    public var monotonic: Double
    public var wall: Date
    public init(epoch: UUID, monotonic: Double, wall: Date) { self.epoch=epoch; self.monotonic=monotonic; self.wall=wall }
}

/// Construction, not transport, defines the production command allowlist.
public struct TelemetryRequest: Codable, Equatable, Sendable {
    public enum Expected: String, Codable, Sendable { case ok, information, data }
    public let command: String
    public let expected: Expected
    public let sensitive: Bool
    private init(_ command: String, _ expected: Expected, sensitive: Bool = false) {
        self.command=command; self.expected=expected; self.sensitive=sensitive
    }
    public static func standard(_ pids: [Int]) throws -> Self {
        guard !pids.isEmpty, pids.count <= 6, Set(pids).count == pids.count,
              pids.allSatisfy({ TelemetryPID.lengths[$0] != nil || (0...224).contains($0) && $0 % 32 == 0 }) else { throw TelemetryFailure.invalidRequest }
        return Self("01"+pids.map { String(format:"%02X",$0) }.joined(), .data)
    }
    public static let vin = Self("0902", .data, sensitive:true)
    public static func configuration(_ command: String) throws -> Self {
        let allowed: Set<String> = ["ATD","ATE0","ATL0","ATS1","ATH1","ATH0","ATD0","ATCAF1","ATSP0","ATCFC1","ATAT1","ATST32"]
        guard allowed.contains(command) else { throw TelemetryFailure.invalidRequest }
        return Self(command,.ok)
    }
    public static func information(_ command: String) throws -> Self {
        guard ["ATI","ATDP","ATDPN","ATRV"].contains(command) else { throw TelemetryFailure.invalidRequest }
        return Self(command,.information,sensitive:command == "ATI")
    }
    public static func route(response: String) throws -> [Self] {
        guard response.count == 3, let address=Int(response,radix:16), (0x7E8...0x7EF).contains(address) else { throw TelemetryFailure.unsupported }
        return [Self(String(format:"ATSH%03X",address-8),.ok),Self("ATCRA"+response,.ok)]
    }
    // Fixed read-only cluster commands. No diagnostic session changes or writes.
    public static func cluster(_ command:String) throws -> Self {
        if ["22F187","22F189","222203","22229A"].contains(command) {
            return Self(command,.data,sensitive:command.hasPrefix("22F1"))
        }
        guard ["ATFCSM0","ATSH714","ATCRA77E","ATFCSH714","ATFCSD300000","ATFCSM1"].contains(command) else { throw TelemetryFailure.invalidRequest }
        return Self(command,.ok)
    }
    public func validate(_ reply: String) throws {
        let lines=reply.uppercased().components(separatedBy:CharacterSet(charactersIn:"\r\n>")).map { $0.trimmingCharacters(in:.whitespaces) }.filter { !$0.isEmpty && $0 != command }
        guard !lines.isEmpty else { throw TelemetryFailure.malformed }
        if expected == .ok, lines != ["OK"] { throw TelemetryFailure.malformed }
        if expected == .information, lines.contains(where:{ $0 == "?" || $0.contains("ERROR") }) { throw TelemetryFailure.malformed }
    }
}

public enum TelemetryPrivacy {
    /// Only reviewed Mode 01 replies are eligible for raw diagnostics. Identity,
    /// calibration, adapter serials and arbitrary error descriptions are opaque.
    public static func reply(command: String, reply: String) -> String {
        let c=command.uppercased().filter { !$0.isWhitespace }
        if ["222203","22229A"].contains(c),reply.utf8.count <= 64_000 {
            let parsed=TelemetryELM.parse(reply)
            let prefix=TelemetryELM.bytes("62"+String(c.dropFirst(2)))!
            if parsed.rejected == 0,!parsed.payloads.isEmpty,
               parsed.payloads.allSatisfy({ $0.ecu == "77E" && $0.bytes.count == 5 && $0.bytes.starts(with:prefix) }) { return reply }
            return "[redacted]"
        }
        if c == "VW",reply.lowercased().contains("recover") { return "measurement recovery" }
        guard c.hasPrefix("01"), c.count >= 4, c.count <= 14, c.allSatisfy(\.isHexDigit), reply.utf8.count <= 64_000 else { return "[redacted]" }
        // An unexpected identity response to a standard request is also opaque.
        let hex=reply.uppercased().filter { !$0.isWhitespace }
        guard !hex.contains("4902"), !hex.contains("4904"), !hex.contains("490A") else { return "[redacted]" }
        let payloads=TelemetryELM.parse(reply,anonymous:true)
        guard payloads.rejected == 0,!payloads.payloads.isEmpty else { return "[redacted]" }
        let requestBytes=TelemetryELM.bytes(String(c.dropFirst(2))) ?? []
        let requested=Set(requestBytes.map(Int.init))
        for payload in payloads.payloads {
            if payload.bytes.count == 6,payload.bytes[0] == 0x41,Int(payload.bytes[1]) % 32 == 0,requested.contains(Int(payload.bytes[1])) { continue }
            guard (try? TelemetryPID.split(payload,requested:requested)) != nil else { return "[redacted]" }
        }
        return reply
    }
}

public struct TelemetryPayload: Equatable, Sendable {
    public var ecu: String
    public var bytes: [UInt8]
}
public struct TelemetryParse: Sendable {
    public var payloads: [TelemetryPayload] = []
    public var rejected = 0
}

/// ATH1/ATD0 CAN framing. 11- and 29-bit headers stay attached through ISO-TP.
/// Anonymous legacy payloads are accepted only when explicitly requested.
public enum TelemetryELM {
    public static let version = "elm.v1"
    public static func parse(_ reply: String, anonymous: Bool = false) -> TelemetryParse {
        var result=TelemetryParse()
        guard reply.utf8.count <= 64_000 else { result.rejected=1; return result }
        var pending: [String:(bytes:[UInt8],length:Int,next:UInt8)] = [:]
        for raw in reply.uppercased().components(separatedBy:CharacterSet(charactersIn:"\r\n>")) {
            let compact=raw.filter { !$0.isWhitespace }
            if compact.isEmpty || compact == "OK" || compact.hasPrefix("SEARCHING") { continue }
            let tokens=raw.split(whereSeparator: \.isWhitespace)
            var header: String?, hex=compact
            if let first=tokens.first, [3,8].contains(first.count), first.allSatisfy(\.isHexDigit), tokens.count > 1 {
                header=String(first); hex=tokens.dropFirst().joined()
            } else if compact.count % 2 == 1, compact.count >= 5 {
                header=String(compact.prefix(3)); hex=String(compact.dropFirst(3))
            } else if compact.hasPrefix("18DA"), compact.count >= 12 {
                header=String(compact.prefix(8)); hex=String(compact.dropFirst(8))
            }
            guard let bytes=bytes(hex), !bytes.isEmpty else { result.rejected += 1; continue }
            guard let header else {
                if anonymous, [0x41,0x49,0x7F].contains(bytes[0]) { result.payloads.append(.init(ecu:"anonymous",bytes:bytes)) }
                else { result.rejected += 1 }
                continue
            }
            guard let address=UInt32(header,radix:16), address <= (header.count == 3 ? 0x7FF:0x1FFFFFFF), bytes.count <= 8 else { result.rejected += 1; continue }
            let pci=bytes[0]
            switch pci >> 4 {
            case 0:
                if pending.removeValue(forKey:header) != nil { result.rejected += 1 }
                let count=Int(pci & 15)
                guard (1...7).contains(count), bytes.count >= count+1 else { result.rejected += 1; continue }
                result.payloads.append(.init(ecu:header,bytes:Array(bytes.dropFirst().prefix(count))))
            case 1:
                if pending.removeValue(forKey:header) != nil { result.rejected += 1 }
                guard bytes.count == 8 else { result.rejected += 1; continue }
                let length=Int(pci & 15)*256+Int(bytes[1])
                guard (8...4095).contains(length) else { result.rejected += 1; continue }
                pending[header]=(Array(bytes.dropFirst(2)),length,1)
            case 2:
                guard var p=pending.removeValue(forKey:header), bytes.count >= 2, pci & 15 == p.next else { result.rejected += 1; continue }
                p.bytes += bytes.dropFirst(); p.next=(p.next+1)&15
                if p.bytes.count >= p.length { result.payloads.append(.init(ecu:header,bytes:Array(p.bytes.prefix(p.length)))) }
                else if bytes.count == 8 { pending[header]=p }
                else { result.rejected += 1 }
            default: result.rejected += 1
            }
        }
        result.rejected += pending.count
        return result
    }
    public static func bytes(_ hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0, hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes:[UInt8]=[], index=hex.startIndex
        while index < hex.endIndex {
            let end=hex.index(index,offsetBy:2)
            guard let byte=UInt8(hex[index..<end],radix:16) else { return nil }
            bytes.append(byte); index=end
        }
        return bytes
    }
    public static func identities(_ payloads: [TelemetryPayload]) throws -> [String:String] {
        var result:[String:String]=[:]
        for p in payloads where p.bytes.starts(with:[0x49,0x02,0x01]) {
            let bytes=Array(p.bytes.dropFirst(3))
            guard bytes.count == 17, bytes.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) && ![73,79,81].contains($0) }) else { continue }
            let vin=String(decoding:bytes,as:UTF8.self)
            if let prior=result[p.ecu], prior != vin { throw TelemetryFailure.ambiguous }
            result[p.ecu]=vin
        }
        guard Set(result.values).count <= 1 else { throw TelemetryFailure.ambiguous }
        return result
    }
    /// Select one RPM-capable source. Resolve equal core support only when
    /// one ECU advertises a strict superset of every other tied candidate.
    /// Equal or incomparable maps stay ambiguous; address order and profile
    /// metadata are not evidence that a particular ECU is the primary source.
    public static func primaryECU(_ candidates: [String:Set<Int>]) throws -> String {
        func score(_ ecu:String)->Int {
            (candidates[ecu]!.contains(0x0D) ? 2:0)+(candidates[ecu]!.contains(0x05) ? 1:0)
        }
        let eligible=candidates.keys.filter { candidates[$0]!.contains(0x0C) }
        guard let best=eligible.map(score).max() else { throw TelemetryFailure.unsupported }
        let tied=eligible.filter { score($0) == best }
        if tied.count == 1 { return tied[0] }
        let dominant=tied.filter { ecu in
            tied.allSatisfy { other in
                other == ecu || candidates[ecu]!.isStrictSuperset(of:candidates[other]!)
            }
        }
        guard dominant.count == 1 else { throw TelemetryFailure.ambiguous }
        return dominant[0]
    }
    public static func supported(_ payloads: [TelemetryPayload], base: Int) -> [String:Set<Int>] {
        var result:[String:Set<Int>]=[:]
        for p in payloads where p.bytes.count == 6 && p.bytes[0] == 0x41 && Int(p.bytes[1]) == base {
            let mask=p.bytes.dropFirst(2).reduce(UInt32(0)) { ($0 << 8)|UInt32($1) }
            for bit in 0..<32 where mask & (UInt32(1) << (31-bit)) != 0 { result[p.ecu,default:[]].insert(base+bit+1) }
        }
        return result
    }
}

public enum TelemetryPID {
    public static let lengths:[Int:Int] = [0x0D:1,0x0C:2,0x05:1,0x0B:1,0x33:1,0x5E:2,0x2F:1,0x46:1,0x42:2,0x0F:1,0x5C:1,0x04:1,0x10:2,0x70:10,0x78:9,0x7A:7,0x8B:7]
    /// Walk known layouts only. Unknown bytes never become a new PID by scanning.
    public static func split(_ payload: TelemetryPayload, requested: Set<Int>) throws -> [Int:[UInt8]] {
        guard payload.bytes.first == 0x41 else { throw TelemetryFailure.malformed }
        var offset=1, result:[Int:[UInt8]]=[:]
        while offset < payload.bytes.count {
            if payload.bytes[offset] == 0x41 { offset += 1 }
            guard offset < payload.bytes.count else { throw TelemetryFailure.malformed }
            let pid=Int(payload.bytes[offset]); offset += 1
            guard requested.contains(pid), let length=lengths[pid] else { throw TelemetryFailure.unsupported }
            guard offset+length <= payload.bytes.count else { throw TelemetryFailure.malformed }
            let data=Array(payload.bytes[offset..<offset+length]); offset += length
            if let prior=result[pid], prior != data { throw TelemetryFailure.ambiguous }
            result[pid]=data
        }
        return result
    }
}
