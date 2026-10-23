import Foundation
import Network

/// Read-only ELM/TCP identity discovery. This is deliberately separate from raw CAN capture.
final class ScannerVINReader {
    let queue = DispatchQueue(label:"can.connect.scanner")
    let connection:NWConnection
    init(host:String,port:UInt16) { connection = NWConnection(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:port)!,using:.tcp) }
    static func read(host:String,port:UInt16) async throws -> String {
        let reader = ScannerVINReader(host:host,port:port)
        defer { reader.connection.cancel() }
        try await reader.connect()
        for command in ["ATZ","ATE0","ATL0","ATS0","ATH0","ATSP0"] { _ = try await reader.exchange(command) }
        let response = try await reader.exchange("0902")
        return try parseVIN(response)
    }
    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            var finished = false
            func finish(_ result:Result<Void,Error>) { guard !finished else { return };finished = true;continuation.resume(with:result) }
            connection.stateUpdateHandler = { state in
                switch state { case .ready:finish(.success(()));case .failed(let error):finish(.failure(error));default:break }
            }
            queue.asyncAfter(deadline:.now()+8) { finish(.failure(CANError.invalid("Scanner connection timed out. Confirm Wi-Fi, IP, and port."))) }
            connection.start(queue:queue)
        }
    }
    func exchange(_ command:String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var finished = false;var buffer = Data()
                func finish(_ result:Result<String,Error>) { guard !finished else { return };finished = true;continuation.resume(with:result) }
                func receive() {
                    self.connection.receive(minimumIncompleteLength:1,maximumLength:8192) { data,_,complete,error in
                        guard !finished else { return }
                        if let data = data { buffer.append(data) }
                        if let text = String(data:buffer,encoding:.utf8),text.contains(">") { finish(.success(text));return }
                        if let error = error { finish(.failure(error));return }
                        if complete || buffer.count>65536 { finish(.failure(CANError.invalid("Scanner returned an incomplete or oversized response.")));return }
                        receive()
                    }
                }
                self.queue.asyncAfter(deadline:.now()+15) { finish(.failure(CANError.invalid("Scanner command timed out."))) }
                self.connection.send(content:Data((command+"\r").utf8),completion:.contentProcessed { error in if let error = error { finish(.failure(error)) } else { receive() } })
            }
        }
    }
    static func parseVIN(_ response:String) throws -> String {
        var bytes:[UInt8] = []
        for line in response.uppercased().components(separatedBy:.newlines) {
            var text = line.trimmingCharacters(in:.whitespacesAndNewlines)
            if let colon = text.firstIndex(of:":") { text = String(text[text.index(after:colon)...]) }
            text = text.replacingOccurrences(of:" ",with:"").replacingOccurrences(of:">",with:"")
            if let marker = text.range(of:"490201") { text = String(text[marker.upperBound...]);bytes = [] }
            else if bytes.isEmpty { continue }
            guard text.allSatisfy(\.isHexDigit),text.count%2==0 else { continue }
            let chars = Array(text);for i in stride(from:0,to:chars.count,by:2) { if let byte = UInt8(String(chars[i...i+1]),radix:16) { bytes.append(byte) } }
        }
        let candidate = String(bytes:bytes.prefix(17),encoding:.ascii) ?? ""
        guard candidate.count==17,candidate.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber) && !"IOQ".contains($0)}) else { throw CANError.invalid("The scanner did not return a complete Mode 09 VIN. Enter the profile manually.") }
        return candidate
    }
}
