import Foundation

// Reviewed software fingerprints, not a year-only assumption about VW controllers.
enum VWController: Int, CaseIterable {
    case engine = 1, dsg = 2
    var obdRequest: String { self == .engine ? "7E0" : "7E1" }
    var obdResponse: String { self == .engine ? "7E8" : "7E9" }
    var calibration: String { self == .engine ? "03L997030M9983" : "02E300062B9430" }
    func matchesCalibration(_ reply: String) -> Bool {
        let values = ELMResponses.payloads(reply,ecu:obdResponse).filter {
            $0.count == 19 && $0.starts(with:[0x49,0x04,0x01])
        }
        return !values.isEmpty && values.allSatisfy {
            String(decoding:$0.dropFirst(3),as:UTF8.self).filter { !$0.isWhitespace && $0 != "\0" } == calibration
        }
    }
}

struct VWRawFrame: Equatable {
    var address: Int
    var data: [UInt8]
    static func parse(_ reply: String, address: Int) -> [Self] {
        reply.components(separatedBy:CharacterSet(charactersIn:"\r\n>")).compactMap { line in
            let hex = line.filter { !$0.isWhitespace }
            guard hex.count >= 5, hex.count <= 19, hex.count % 2 == 1,
                  hex.allSatisfy({$0.isASCII && $0.isHexDigit}),
                  Int(hex.prefix(3),radix:16) == address else { return nil }
            let body = String(hex.dropFirst(3)); var data: [UInt8] = []; var index = body.startIndex
            while index < body.endIndex {
                let end = body.index(index,offsetBy:2)
                guard let byte = UInt8(body[index..<end],radix:16) else { return nil }
                data.append(byte); index = end
            }
            return Self(address:address,data:data)
        }
    }
}

// TP 2.0 uses its own sequencing/length fields; ISO-TP decoding does not apply.
// Protocol description: https://jazdw.net/tp20 . No third-party transport code.
struct VWMessageAssembler {
    private(set) var sequence: UInt8 = 0
    private var previous: [UInt8]?
    private var bytes: [UInt8] = []
    private var length: Int?
    private(set) var complete = false
    mutating func beginMessage() { bytes = []; length = nil; complete = false }
    mutating func accept(_ frame: [UInt8]) throws -> Bool {
        guard let op = frame.first, op >> 4 <= 3, frame.count >= 2 else { throw AppFailure("Invalid VW data frame.") }
        if op & 15 == ((sequence &+ 15) & 15), frame == previous { return op >> 4 <= 1 }
        guard !complete, op & 15 == sequence else { throw AppFailure("VW response sequence mismatch.") }
        var data = Array(frame.dropFirst())
        if length == nil {
            guard data.count >= 2 else { throw AppFailure("VW response has no length.") }
            let count = Int(data[0])*256 + Int(data[1])
            guard (1...4095).contains(count) else { throw AppFailure("Invalid VW response length.") }
            length = count; data = Array(data.dropFirst(2))
        }
        guard bytes.count + data.count <= length! else { throw AppFailure("VW response exceeded its declared length.") }
        bytes += data; sequence = (sequence+1)&15; previous = frame
        let last = op >> 4 == 1 || op >> 4 == 3
        guard !last || bytes.count == length else { throw AppFailure("VW response is incomplete.") }
        complete = last
        return op >> 4 <= 1
    }
    var payload: [UInt8]? { complete ? bytes : nil }
}

struct VWMeasurementReply {
    var payload: [UInt8]
    var raw: String
    var requestHeader: String
    var responseHeader: String
    var timestamp: Date
}

enum VWMeasurementDecoder {
    static let keys: Set<String> = ["dpfAshML","dsgFluidC"]
    static func decode(_ response: VWMeasurementReply, controller: VWController, group: Int) -> OBDSample? {
        let p = response.payload
        guard p.count >= 14, (p.count-2)%3 == 0, p[0] == 0x61, Int(p[1]) == group else { return nil }
        func field(_ index: Int, type: UInt8) -> (Double,Double)? {
            let start = 2+index*3
            guard start+2 < p.count, p[start] == type else { return nil }
            return (Double(p[start+1]),Double(p[start+2]))
        }
        var signals: [String:Double] = [:]
        if controller == .dsg, group == 19, let (a,b) = field(0,type:0x1A) {
            let temperature = b-a
            if (-40...180).contains(temperature) { signals["dsgFluidC"] = temperature }
        }
        if controller == .engine, group == 108, let (a,b) = field(0,type:0x68) {
            let volume = (b-128)*a/5
            if (0...1000).contains(volume) { signals["dpfAshML"] = volume }
        }
        guard !signals.isEmpty else { return nil }
        return OBDSample(timestamp:response.timestamp,signals:signals,command:String(format:"21%02X",group),
            reply:response.raw,requestHeader:response.requestHeader,responseHeader:response.responseHeader)
    }
}
