import Foundation

public struct HTTPRequest: Sendable {
    public let method: String
    public let target: String
    public let headers: [String:String]
    public let body: Data
    public var path: String { URLComponents(string:target)?.path ?? target }
    public var query: [String:String] {
        var result:[String:String] = [:]
        for item in URLComponents(string:target)?.queryItems ?? [] { result[item.name] = item.value ?? "" }
        return result
    }
    public static func parse(_ data:Data, limit:Int = RecordingImporter.maxBytes) throws -> HTTPRequest? {
        guard let split = data.range(of:Data("\r\n\r\n".utf8)) else {
            if data.count>16_384 { throw CANError.invalid("HTTP headers too large") }; return nil
        }
        guard split.lowerBound <= 16_384, let text = String(data:data[..<split.lowerBound],encoding:.utf8) else { throw CANError.invalid("Invalid HTTP headers") }
        let lines = text.components(separatedBy:"\r\n"), first = (lines.first ?? "").split(separator:" ")
        guard first.count==3, first[2]=="HTTP/1.1" || first[2]=="HTTP/1.0" else { throw CANError.invalid("Invalid HTTP request line") }
        var headers:[String:String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of:":") else { throw CANError.invalid("Malformed header") }
            let key = String(line[..<colon]).lowercased(), value = String(line[line.index(after:colon)...]).trimmingCharacters(in:.whitespaces)
            if headers[key] != nil { throw CANError.invalid("Duplicate header") }; headers[key] = value
        }
        guard headers["transfer-encoding"] == nil else { throw CANError.invalid("Chunked requests are not supported; provide Content-Length") }
        let length: Int
        if let raw = headers["content-length"] { guard let n = Int(raw), n>=0 else { throw CANError.invalid("Invalid Content-Length") }; length = n } else { length = 0 }
        guard length <= limit else { throw CANError.invalid("Request body exceeds 50 MB") }
        guard data.count >= split.upperBound+length else { return nil }
        return HTTPRequest(method:String(first[0]),target:String(first[1]),headers:headers,body:data.subdata(in:split.upperBound..<split.upperBound+length))
    }
    public func isAuthorized(token: String) -> Bool {
        guard !token.isEmpty, let raw = headers["authorization"], raw.hasPrefix("Bearer ") else { return false }
        let a = Array(raw.dropFirst(7).utf8), b = Array(token.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for i in a.indices { difference |= a[i] ^ b[i] }
        return difference == 0
    }
}
public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public init(_ status:Int, data:Data) { self.status = status; self.body = data }
    public init(_ status:Int, json:[String:Any]) { self.init(status,data:(try? JSONSerialization.data(withJSONObject:json,options:[.sortedKeys])) ?? Data("{}".utf8)) }
    public var wire: Data {
        let reasons = [200:"OK",201:"Created",202:"Accepted",400:"Bad Request",401:"Unauthorized",404:"Not Found",405:"Method Not Allowed",409:"Conflict",413:"Payload Too Large",422:"Unprocessable Content",503:"Service Unavailable",500:"Internal Server Error"]
        let head = "HTTP/1.1 \(status) \(reasons[status] ?? "Response")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        return Data(head.utf8)+body
    }
}
