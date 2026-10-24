import Foundation

// Single-owner, bounded read-only KWP2000 over a negotiated VW TP 2.0 channel.
// Raw CAN is enabled only for the reviewed controller software fingerprints.
@MainActor
final class VWMeasuringBlocks {
    private let exchange: (String) async throws -> String
    private var transmit = 0
    private var receive = 0
    private var transmitSequence: UInt8 = 0
    private var assembler = VWMessageAssembler()
    private var channelOpen = false
    private var unsupported: [VWController:Set<Int>] = [:]
    private var disabled = Set<VWController>()
    private var transmitGap: TimeInterval = 0
    private var lastSent = Date.distantPast
    init(exchange: @escaping (String) async throws -> String) { self.exchange = exchange }

    private func sendFrame(_ command: String) async throws -> String {
        let remaining = transmitGap-Date().timeIntervalSince(lastSent)
        if remaining > 0 { try await Task.sleep(nanoseconds:UInt64(remaining*1_000_000_000)) }
        lastSent = Date()
        return try await exchange(command)
    }

    static let restoreCommands = ["ATSP6","ATCAF1","ATCFC1","ATAT1","ATST32","ATSH7E0","ATCRA7E8","ATH1","ATD0"]
    private func configure(_ commands: [String]) async throws {
        for command in commands {
            let reply = try await exchange(command)
            guard reply.trimmingCharacters(in:.whitespacesAndNewlines).uppercased() == "OK" else {
                throw AppFailure("The MX+ rejected VW diagnostic configuration \(command).")
            }
        }
    }
    private func open(_ controller: VWController) async throws {
        transmitSequence = 0; assembler = VWMessageAssembler(); channelOpen = false; transmitGap = 0
        try await configure(["ATPBC001","ATSPB","ATH1","ATD0","ATCAF0","ATCFC0","ATAT0","ATST19",
                             "ATSH200",String(format:"ATCRA%03X",0x200+controller.rawValue)])
        // The final '1' asks ELM for one reply. Waiting for retransmissions here
        // lets VW's setup deadline expire before parameter negotiation completes.
        let setup = try await sendFrame(String(format:"%02XC000100003011",controller.rawValue))
        let replies = VWRawFrame.parse(setup,address:0x200+controller.rawValue)
        guard let frame = replies.first?.data, frame.count == 7, frame[1] == 0xD0,
              replies.allSatisfy({$0.data == frame}), frame[3]&0xF0 == 0, frame[5]&0xF0 == 0,
              frame[6] == 1 else { throw AppFailure("The VW controller did not open a measurement channel.") }
        receive = Int(frame[2])+Int(frame[3])*256
        transmit = Int(frame[4])+Int(frame[5])*256
        guard receive == 0x300, (0x300...0x7EF).contains(transmit), transmit != receive else {
            throw AppFailure("Unexpected VW diagnostic channel addresses.")
        }
        try await configure([String(format:"ATSH%03X",transmit),String(format:"ATCRA%03X",receive),"ATST05"])
        channelOpen = true
        let parameters = try await sendFrame("A00F8AFF32FF1")
        guard let values = VWRawFrame.parse(parameters,address:receive).first?.data,
              values.count == 6, values[0] == 0xA1, values[1] > 0 else {
            throw AppFailure("The VW controller did not confirm channel timing.")
        }
        let units: [Double] = [0.0001,0.001,0.01,0.1]
        transmitGap = Double(values[4]&63)*units[Int(values[4]>>6)]
        guard transmitGap <= 0.1 else { throw AppFailure("VW controller requested unsupported diagnostic timing.") }
        let initialized = try await request([0x10,0x89])
        guard initialized.payload == [0x50,0x89] else { throw AppFailure("VW measurement session was not accepted.") }
    }
    private func request(_ payload: [UInt8]) async throws -> VWMeasurementReply {
        guard channelOpen, payload == [0x10,0x89] ||
                (payload.count == 2 && payload[0] == 0x21 && [19,108,240,241].contains(Int(payload[1]))) else {
            throw AppFailure("VW request is outside the read-only measurement allowlist.")
        }
        func hex(_ bytes: [UInt8]) -> String { bytes.map {String(format:"%02X",$0)}.joined() }
        let frame = [0x10|transmitSequence,0,UInt8(payload.count)] + payload
        transmitSequence = (transmitSequence+1)&15
        assembler.beginMessage()
        var reply = try await sendFrame(hex(frame)); var raw = [reply]
        var acknowledged = false
        for _ in 0..<12 {
            try Task.checkCancellation()
            var requiresACK = false; var testChannel = false
            for frame in VWRawFrame.parse(reply,address:receive).map(\.data) {
                guard let op = frame.first else { continue }
                switch op >> 4 {
                case 0...3:
                    requiresACK = try assembler.accept(frame) || requiresACK
                case 0xB:
                    guard frame.count == 1, op&15 == transmitSequence else { throw AppFailure("VW request acknowledgment mismatch.") }
                    acknowledged = true
                case 0xA:
                    if op == 0xA8 { channelOpen = false; throw AppFailure("VW measurement channel disconnected.") }
                    if op == 0xA3 { testChannel = true }
                    else { throw AppFailure("Unexpected VW channel control reply.") }
                default: throw AppFailure("Unexpected VW diagnostic frame.")
                }
            }
            let completed = assembler.payload
            if requiresACK {
                reply = try await sendFrame(hex([0xB0|assembler.sequence])); raw.append(reply)
            } else if testChannel {
                reply = try await sendFrame("A10F8AFF32FF"); raw.append(reply)
            } else if completed == nil {
                // A short adapter read can end between the ECU ACK and data.
                reply = try await sendFrame(hex([0xB0|assembler.sequence])); raw.append(reply)
            }
            if let completed {
                guard acknowledged else { throw AppFailure("VW response arrived without request acknowledgment.") }
                return VWMeasurementReply(payload:completed,raw:raw.joined(separator:"\r"),
                    requestHeader:String(format:"%03X",transmit),responseHeader:String(format:"%03X",receive),timestamp:Date())
            }
        }
        throw AppFailure("VW measurement response did not complete in time.")
    }
    private func closeChannel() async throws {
        if channelOpen { _ = try await sendFrame("A8"); channelOpen = false }
    }
    // Also runs after cancellation. The recorder's teardown barrier awaits this
    // cleanup before the same foreground MFi channel can be used again.
    private func restore() async throws {
        let cleanup = Task { @MainActor in
            if self.channelOpen { _ = try? await self.sendFrame("A8"); self.channelOpen = false }
            try await self.configure(Self.restoreCommands)
        }
        try await cleanup.value
    }
    func read(controllers: Set<VWController>) async throws -> [OBDSample] {
        var samples: [OBDSample] = []
        do {
            for controller in VWController.allCases where controllers.contains(controller) && !disabled.contains(controller) {
                do {
                try await open(controller)
                // On the tested engine, 240/241 return NRC 31. Probe only once
                // per connection and retain unavailable fields as unavailable.
                let groups = controller == .engine ? [108,240,241] : [19]
                for group in groups where !(unsupported[controller] ?? []).contains(group) {
                    let response = try await request([0x21,UInt8(group)])
                    if response.payload == [0x7F,0x21,0x31] {
                        unsupported[controller,default:[]].insert(group); continue
                    }
                    if let sample = VWMeasurementDecoder.decode(response,controller:controller,group:group) { samples.append(sample) }
                }
                try await closeChannel()
                } catch is CancellationError { throw CancellationError() }
                catch {
                    disabled.insert(controller)
                    try await restore()
                }
            }
            try await restore()
            return samples
        } catch {
            try await restore()
            throw error
        }
    }
}
