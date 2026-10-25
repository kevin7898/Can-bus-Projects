import Foundation

// Ported from Android Pocket Recorder EngineIsoTp. ATH1 + ATD0: no DLC column.
// Reassemble each ECU independently, preserving sequence and declared length.
enum ELMResponses {
    static func payloads(_ reply: String, ecu: String? = nil) -> [[UInt8]] {
        var result: [[UInt8]] = []
        var pending: [String:(data:[UInt8],length:Int,sequence:UInt8)] = [:]
        for raw in reply.uppercased().components(separatedBy:CharacterSet(charactersIn:"\r\n>")) {
            let hex = raw.filter { !$0.isWhitespace }
            guard hex.count >= 5, hex.count % 2 == 1, hex.allSatisfy(\.isHexDigit) else { continue }
            let header = String(hex.prefix(3))
            guard let address = Int(header,radix:16), address <= 0x7FF, ecu == nil || header == ecu else { continue }
            let frame = bytes(String(hex.dropFirst(3)))
            guard let pci = frame.first, frame.count <= 8 else { continue }
            switch pci >> 4 {
            case 0:
                pending[header] = nil
                let count = Int(pci & 15)
                if (1...7).contains(count), frame.count >= count+1 { result.append(Array(frame.dropFirst().prefix(count))) }
            case 1:
                pending[header] = nil
                guard frame.count >= 3 else { continue }
                let length = Int(pci & 15)*256+Int(frame[1])
                guard (8...4095).contains(length) else { continue }
                pending[header] = (Array(frame.dropFirst(2)),length,1)
            case 2:
                guard var message = pending[header] else { continue }
                guard pci & 15 == message.sequence, frame.count >= 2 else { pending[header] = nil; continue }
                message.data += frame.dropFirst(); message.sequence = (message.sequence+1)&15
                if message.data.count >= message.length { result.append(Array(message.data.prefix(message.length))); pending[header] = nil }
                else { pending[header] = message }
            default: break
            }
        }
        // A targeted read requires an actual matching header, never an anonymous reply.
        return ecu == nil ? result + ELMIdentityParser.payloads(reply) : result
    }
    private static func bytes(_ hex: String) -> [UInt8] {
        guard hex.count % 2 == 0 else { return [] }
        var result: [UInt8] = []; var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index,offsetBy:2)
            guard let byte = UInt8(hex[index..<end],radix:16) else { return [] }
            result.append(byte); index = end
        }
        return result
    }
}
