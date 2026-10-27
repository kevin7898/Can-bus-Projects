import Foundation

// Single-owner, bounded read-only KWP2000 over a negotiated VW TP 2.0 channel.
// Raw CAN is enabled only for the reviewed controller software fingerprints.
@MainActor
final class VWMeasuringBlocks {
    private enum ChannelFailure: Error { case temporarilyUnavailable }
    private let exchange: (String) async throws -> String
    private let pause: (TimeInterval) async throws -> Void
    private var transmit = 0
    private var receive = 0
    private var transmitSequence: UInt8 = 0
    private var assembler = VWMessageAssembler()
    private var channelOpen = false
    private var probingDSGMileage = false
    private struct Retry {
        var failures: Int
        var after: ContinuousClock.Instant
    }
    private var controllerRetries: [VWController:Retry] = [:]
    private var groupRetries: [VWController:[Int:Retry]] = [:]
    private let clock: () -> ContinuousClock.Instant
    private let sampleDate: () -> Date
    private let report: (String) -> Void
    private var transmitGap: TimeInterval = 0
    private var lastSent: ContinuousClock.Instant?
    init(exchange: @escaping (String) async throws -> String,
         pause: @escaping (TimeInterval) async throws -> Void = { seconds in
             try await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))
         }, clock: @escaping () -> ContinuousClock.Instant = { .now },
         sampleDate: @escaping () -> Date = Date.init,
         report: @escaping (String) -> Void = { _ in }) {
        self.exchange = exchange; self.pause = pause; self.clock = clock; self.sampleDate = sampleDate; self.report = report
    }
    private func retry(after previous: Retry?, minimum: TimeInterval) -> Retry {
        let failures = min((previous?.failures ?? 0)+1,5)
        return Retry(failures:failures,after:clock().advanced(by:.seconds(min(300,minimum*pow(2,Double(failures-1))))))
    }
    private func deferGroup(_ group: Int, controller: VWController, rejected: Bool) {
        // A negative response describes this request, not permanent support.
        // Retry explicit rejection slowly; ordinary malformed/blank data sooner.
        let next = retry(after:groupRetries[controller]?[group],minimum:rejected ? 300 : max(30,controller.pollInterval))
        groupRetries[controller,default:[:]][group] = next
        report("Controller \(controller.rawValue) block \(group) \(rejected ? "rejected" : "unavailable"); retry in \(max(0,clock().duration(to:next.after).components.seconds))s")
    }

    private func sendFrame(_ command: String) async throws -> String {
        if let lastSent {
            try await Task.sleep(until:lastSent.advanced(by:.seconds(transmitGap)),clock:.continuous)
        }
        lastSent = .now
        return try await exchange(command)
    }

    static let restoreCommands = ["ATFCSM0","ATSP6","ATCAF1","ATCFC1","ATAT1","ATST32","ATSH7E0","ATCRA7E8","ATH1","ATD0"]
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
        if let frame = replies.first?.data, frame.count == 7, frame[0] == 0, frame[6] == 1,
           replies.allSatisfy({$0.data == frame}), [UInt8(0xD7),0xD8].contains(frame[1]) {
            throw ChannelFailure.temporarilyUnavailable
        }
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
                (payload.count == 2 && payload[0] == 0x21 && ([19,108,114].contains(Int(payload[1])) || (probingDSGMileage && payload[1] == 109))) else {
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
                    requestHeader:String(format:"%03X",transmit),responseHeader:String(format:"%03X",receive),timestamp:sampleDate())
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
    /// Group 109 is a documented 02E-family mileage lead, not a verified decoder.
    /// Keep this out of periodic telemetry. Only the reviewed DSG fingerprint
    /// may enter the existing TP2.0 session; preserve the complete typed payload.
    func probeDSGMileage(calibrationReply:String) async throws -> VWMeasurementReply {
        guard VWController.dsg.matchesCalibration(calibrationReply) else {
            throw AppFailure("DSG software fingerprint differs from the reviewed controller. TP2.0 probe skipped.")
        }
        probingDSGMileage=true
        defer { probingDSGMileage=false }
        do {
            try Task.checkCancellation()
            try await configure(["ATFCSM0"])
            try await open(.dsg)
            let response=try await request([0x21,109])
            guard response.payload.starts(with:[0x61,109]) ||
                    (response.payload.count == 3 && response.payload.starts(with:[0x7F,0x21])) else {
                throw AppFailure("DSG block 109 returned an unexpected response.")
            }
            try await closeChannel()
            try await restore()
            return response
        } catch {
            try await restore()
            throw error
        }
    }
    func read(controllers: Set<VWController>) async throws -> [OBDSample] {
        var samples: [OBDSample] = []
        do {
            for controller in VWController.allCases where controllers.contains(controller) {
                guard controllerRetries[controller].map({ clock() >= $0.after }) ?? true else { continue }
                let groups = (controller == .engine ? [108,114] : [19]).filter {
                    groupRetries[controller]?[$0].map { clock() >= $0.after } ?? true
                }
                guard !groups.isEmpty else { continue }
                do {
                    // The engine needs a quiet interval before TP 2.0 setup.
                    // This single owner prevents interleaved ordinary OBD polls.
                    if controller == .engine { try await pause(6) }
                    try Task.checkCancellation()
                    try await open(controller)
                    for group in groups {
                        let response = try await request([0x21,UInt8(group)])
                        if response.payload == [0x7F,0x21,0x31] {
                            deferGroup(group,controller:controller,rejected:true)
                            continue
                        }
                        if let sample = VWMeasurementDecoder.decode(response,controller:controller,group:group) {
                            samples.append(sample)
                            if groupRetries[controller]?.removeValue(forKey:group) != nil {
                                report("Controller \(controller.rawValue) block \(group) recovered")
                            }
                        } else { deferGroup(group,controller:controller,rejected:false) }
                    }
                    try await closeChannel()
                    if controllerRetries.removeValue(forKey:controller) != nil {
                        report("Controller \(controller.rawValue) measurement channel recovered")
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    let next = retry(after:controllerRetries[controller],minimum:max(30,controller.pollInterval))
                    controllerRetries[controller] = next
                    let reason = error is ChannelFailure ? "temporarily unavailable" : error.localizedDescription
                    report("Controller \(controller.rawValue) \(reason); retry in \(max(0,clock().duration(to:next.after).components.seconds))s")
                    // Only continue standard/other-controller reads after raw
                    // CAN cleanup succeeds. Never disable a controller forever.
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
