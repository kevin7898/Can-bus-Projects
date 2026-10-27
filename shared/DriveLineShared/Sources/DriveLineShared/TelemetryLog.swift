import Foundation
import CryptoKit

public struct TelemetryExchange: Codable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var sequence: UInt64
    public var command: String
    public var reply: String
    public var start: TelemetryTime
    public var end: TelemetryTime
    public var generation: UUID
    public var outcome: String
    public init(sessionID: UUID, sequence: UInt64, request: TelemetryRequest, reply: String, start: TelemetryTime, end: TelemetryTime, generation: UUID, outcome: String) {
        id=UUID(); self.sessionID=sessionID; self.sequence=sequence; command=request.command
        self.reply=TelemetryPrivacy.reply(command:request.command,reply:reply)
        self.start=start; self.end=end; self.generation=generation; self.outcome=outcome
    }
}
public struct TelemetryEvent: Codable, Sendable {
    public var kind: String
    public var time: TelemetryTime
    public init(_ kind: String, at time: TelemetryTime) { self.kind=kind; self.time=time }
}
public struct TelemetryLogHeader: Codable, Sendable {
    public var recordingID: UUID
    public var vehicleID: UUID
    public var epoch: UUID
    public var schema = 1
    public var parser = TelemetryELM.version
    public var policy = "matched-interval.v1"
    public init(recordingID: UUID, vehicleID: UUID, epoch: UUID) { self.recordingID=recordingID; self.vehicleID=vehicleID; self.epoch=epoch }
}

/// Binary v1: DLTL + 01 00 00 00; repeated u32 big-endian body length,
/// u8 record type, JSON body, u32 big-endian CRC32(type+body). Max body 1 MiB.
/// File operations are serialized off the main actor by callers or this actor.
public actor TelemetryLog {
    public static let magic=Data([0x44,0x4C,0x54,0x4C,1,0,0,0])
    public static let maximumBody=1_048_576
    public struct Recovery: Sendable {
        public var validBytes: UInt64
        public var records: Int
        public var damagedTail: Bool
    }
    public struct Finalize: Codable, Sendable {
        public var recordingID: UUID
        public var byteLength: UInt64
        public var records: Int
        public var sha256: String
    }
    private let url: URL
    private let id: UUID
    private var handle: FileHandle?
    private var count=0
    private var lastSync=ProcessInfo.processInfo.systemUptime
    private var finalized: Finalize?
    private var finishing=false
    public private(set) var syncCount=0
    public init(url: URL, header: TelemetryLogHeader) throws {
        self.url=url; id=header.recordingID
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        guard !FileManager.default.fileExists(atPath:url.path) else { throw TelemetryFailure.storage }
        var data=Self.magic
        data.append(try Self.frame(type:0,body:JSONEncoder().encode(header)))
        try data.write(to:url,options:.atomic)
        let handle=try FileHandle(forWritingTo:url); try handle.seekToEnd(); try handle.synchronize()
        self.handle=handle; count=1; syncCount=1
    }
    public func append<T: Encodable & Sendable>(_ value:T, type:UInt8, important:Bool=false) throws {
        guard let handle, finalized == nil,!finishing else { throw TelemetryFailure.storage }
        let frame=try Self.frame(type:type,body:JSONEncoder().encode(value))
        try handle.write(contentsOf:frame); count += 1
        let now=ProcessInfo.processInfo.systemUptime
        if important || now-lastSync >= 1 { try handle.synchronize(); lastSync=now; syncCount += 1 }
    }
    public func sync() throws { guard let handle else { throw TelemetryFailure.storage }; try handle.synchronize(); syncCount += 1 }
    public func finish() throws -> Finalize {
        if let finalized { return finalized }
        guard let handle else { throw TelemetryFailure.storage }
        finishing=true
        try handle.synchronize(); syncCount += 1
        let reader=try FileHandle(forReadingFrom:url); defer { try? reader.close() }
        var hash=SHA256(), length:UInt64=0
        while let bytes=try reader.read(upToCount:65_536), !bytes.isEmpty { hash.update(data:bytes); length += UInt64(bytes.count) }
        let marker=Finalize(recordingID:id,byteLength:length,records:count,sha256:hash.finalize().map { String(format:"%02x",$0) }.joined())
        let markerURL=url.appendingPathExtension("finalized")
        try JSONEncoder().encode(marker).write(to:markerURL,options:.atomic)
        let markerHandle=try FileHandle(forWritingTo:markerURL); try markerHandle.synchronize(); try markerHandle.close()
        try handle.close();self.handle=nil
        finalized=marker
        return marker
    }
    public static func frame(type:UInt8, body:Data) throws -> Data {
        guard body.count <= maximumBody else { throw TelemetryFailure.storage }
        var frame=word(UInt32(body.count)), covered=Data([type]); covered.append(body)
        frame.append(covered); frame.append(word(crc32(covered))); return frame
    }
    public static func recover(url:URL, visit:(UInt8,Data)throws->Void = {_,_ in}) throws -> Recovery {
        let handle=try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        guard try handle.read(upToCount:8) == magic else { throw TelemetryFailure.malformed }
        var offset:UInt64=8, count=0
        while let prefix=try handle.read(upToCount:4), !prefix.isEmpty {
            guard prefix.count == 4 else { return .init(validBytes:offset,records:count,damagedTail:true) }
            let length=prefix.reduce(UInt32(0)) { ($0 << 8)|UInt32($1) }
            guard length <= maximumBody, let covered=try handle.read(upToCount:Int(length)+1), covered.count == Int(length)+1,
                  let crc=try handle.read(upToCount:4), crc.count == 4,
                  crc.reduce(UInt32(0),{ ($0 << 8)|UInt32($1) }) == crc32(covered) else { return .init(validBytes:offset,records:count,damagedTail:true) }
            try visit(covered[0],Data(covered.dropFirst()))
            offset += UInt64(length)+9; count += 1
        }
        return .init(validBytes:offset,records:count,damagedTail:false)
    }
    private static func word(_ n:UInt32)->Data { var n=n.bigEndian; return withUnsafeBytes(of:&n) { Data($0) } }
    public static func crc32(_ data:Data)->UInt32 {
        var crc=UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1)^0xEDB88320 : crc >> 1 }
        }
        return ~crc
    }
}
