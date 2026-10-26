import Foundation
import Network

/// Read-only ELM/TCP identity discovery. This is deliberately separate from raw CAN capture.
// The connection is thread-safe; exchange state is confined to its serial callback queue.
final class ScannerVINReader: @unchecked Sendable {
    struct Identity:Equatable {
        var vin:String
        var protocolName:String
        var respondingAddress:String?
        var observedAt:Date
    }
    let queue = DispatchQueue(label:"can.connect.scanner")
    let connection:NWConnection
    init(host:String,port:UInt16) { connection = NWConnection(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:port)!,using:.tcp) }
    static func read(host:String,port:UInt16) async throws -> String {
        try await identify(host:host,port:port).vin
    }
    static func identify(host:String,port:UInt16) async throws -> Identity {
        let reader = ScannerVINReader(host:host,port:port)
        defer { reader.connection.cancel() }
        try await reader.connect()
        for command in ["ATZ","ATE0","ATL0","ATS1","ATH1","ATSP0"] { _ = try await reader.exchange(command) }
        let response = try await reader.exchange("0902")
        let vin=try parseVIN(response)
        let address=respondingAddress(response)
        _ = try await reader.exchange("ATH0")
        let protocolName=clean(try await reader.exchange("ATDP"))
        return Identity(vin:vin,protocolName:protocolName.isEmpty ? "Unavailable":protocolName,
                        respondingAddress:address,observedAt:Date())
    }
    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            let pending = ScannerCompletion(continuation)
            connection.stateUpdateHandler = { state in
                switch state { case .ready:pending.finish(.success(()));case .failed(let error):pending.finish(.failure(error));case .cancelled:pending.finish(.failure(CancellationError()));default:break }
            }
            queue.asyncAfter(deadline:.now()+8) { pending.finish(.failure(CANError.invalid("Scanner connection timed out. Confirm Wi-Fi, IP, and port."))) }
            connection.start(queue:queue)
        }
    }
    func exchange(_ command:String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let exchange = ScannerExchange(connection:connection,queue:queue,continuation:continuation)
            queue.async { exchange.start(command) }
        }
    }
    static func parseVIN(_ response:String) throws -> String {
        var bytes:[UInt8] = []
        for line in response.uppercased().components(separatedBy:.newlines) {
            var text = line.trimmingCharacters(in:.whitespacesAndNewlines)
            if let colon = text.firstIndex(of:":") { text = String(text[text.index(after:colon)...]) }
            var tokens=text.split(whereSeparator:\.isWhitespace).map(String.init)
            if let first=tokens.first,[3,8].contains(first.count),first.allSatisfy(\.isHexDigit) { tokens.removeFirst() }
            if let first=tokens.first,let pci=UInt8(first,radix:16) {
                if pci & 0xF0 == 0x10,tokens.count>=2 { tokens.removeFirst(2) }
                else if pci & 0xF0 == 0x20 { tokens.removeFirst() }
            }
            if !tokens.isEmpty { text=tokens.joined() }
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
    static func respondingAddress(_ response:String)->String? {
        for line in response.uppercased().components(separatedBy:.newlines) {
            let tokens=line.trimmingCharacters(in:.whitespacesAndNewlines).split(whereSeparator:\.isWhitespace)
            guard let first=tokens.first,[3,8].contains(first.count),first.allSatisfy(\.isHexDigit) else { continue }
            if line.contains("49 02") || line.replacingOccurrences(of:" ",with:"").contains("4902") { return String(first) }
        }
        return nil
    }
    private static func clean(_ value:String)->String {
        value.replacingOccurrences(of:">",with:"").components(separatedBy:.newlines)
            .map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter{!$0.isEmpty && !$0.hasPrefix("AT")}.joined(separator:" ")
    }
}

// Connection state and timeout can both complete a request. Consume the continuation
// under a lock so cancellation/failure/timeout can never resume it twice.
private final class ScannerCompletion<Value:Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation:CheckedContinuation<Value,Error>?
    init(_ continuation:CheckedContinuation<Value,Error>) { self.continuation = continuation }
    func finish(_ result:Result<Value,Error>) {
        lock.lock();let continuation = continuation;self.continuation = nil;lock.unlock()
        continuation?.resume(with:result)
    }
}

// All mutable exchange state and all Network callbacks run on the connection queue.
private final class ScannerExchange: @unchecked Sendable {
    let connection:NWConnection
    let queue:DispatchQueue
    let completion:ScannerCompletion<String>
    private var finished = false
    private var buffer = Data()
    init(connection:NWConnection,queue:DispatchQueue,continuation:CheckedContinuation<String,Error>) {
        self.connection = connection;self.queue = queue;completion = ScannerCompletion(continuation)
    }
    func start(_ command:String) {
        dispatchPrecondition(condition:.onQueue(queue))
        queue.asyncAfter(deadline:.now()+15) { self.finish(.failure(CANError.invalid("Scanner command timed out."))) }
        connection.send(content:Data((command+"\r").utf8),completion:.contentProcessed { error in
            if let error = error { self.finish(.failure(error)) } else { self.receive() }
        })
    }
    func finish(_ result:Result<String,Error>) {
        dispatchPrecondition(condition:.onQueue(queue))
        guard !finished else { return };finished = true;completion.finish(result)
    }
    func receive() {
        dispatchPrecondition(condition:.onQueue(queue))
        guard !finished else { return }
        connection.receive(minimumIncompleteLength:1,maximumLength:8192) { data,_,complete,error in
            guard !self.finished else { return }
            if let data = data { self.buffer.append(data) }
            if self.buffer.count>65536 { self.finish(.failure(CANError.invalid("Scanner returned an oversized response.")));return }
            if let text = String(data:self.buffer,encoding:.utf8),text.contains(">") { self.finish(.success(text));return }
            if let error = error { self.finish(.failure(error));return }
            if complete { self.finish(.failure(CANError.invalid("Scanner returned an incomplete response.")));return }
            self.receive()
        }
    }
}
