import XCTest
@testable import CANConnect

@MainActor
private final class FixtureAccessoryStreams: AccessoryStreams {
    var onEvent: ((Stream.Event) -> Void)?
    var isOpen = false
    var openImmediately = true
    var hasSpace = true
    var hasBytes: Bool { !chunks.isEmpty }
    var closes = 0
    var written = Data()
    var chunks: [Data] = []
    var response: ((String) -> String)?
    var maximumWrite = 2
    private var command = Data()
    func open() { if openImmediately { isOpen = true; onEvent?(.openCompleted) } }
    func close() { isOpen = false; closes += 1; onEvent = nil }
    func read() throws -> Data { chunks.removeFirst() }
    func write(_ bytes: Data) throws -> Int {
        let count = min(maximumWrite,bytes.count)
        let sent = Data(bytes.prefix(count)); written.append(sent); command.append(sent)
        if command.last == 13, let response {
            let text = String(decoding:command.dropLast(),as:UTF8.self); command.removeAll()
            let reply = response(text)
            Task { @MainActor in
                await Task.yield()
                for byte in reply.utf8 { self.inject(Data([byte])) }
            }
        }
        return count
    }
    func inject(_ bytes: Data) { chunks.append(bytes); onEvent?(.hasBytesAvailable) }
}

final class MXPlusTransportTests: XCTestCase {
    @MainActor func testInformationalAndRejectedATRepliesCompleteAtPrompt() async throws {
        let streams=FixtureAccessoryStreams()
        let tested=ELMAccessoryChannel(streams:streams,timeoutNanoseconds:100_000_000)
        streams.response = { command in command == "ATRV" ? "12.6V\r>" : "REJECTED\r>" }
        try await tested.open();defer { tested.disconnect() }
        let voltage=try await tested.command("ATRV")
        XCTAssertTrue(voltage.contains("12.6V"))
        let rejected=try await tested.command("ATE0")
        XCTAssertTrue(rejected.contains("REJECTED"))
    }

    @MainActor
    func testFragmentedStreamIdentificationAndShortWrites() async throws {
        let streams = FixtureAccessoryStreams()
        streams.response = { command in
            switch command {
            case "ATI": return "ELM327 SYNTHETIC MX+ STREAM\r>"
            case "0902": return "NO DATA\r>"
            case "0100": return "41 00 00 18 00 00\r>"
            case "ATDP": return "ISO 15765-4 CAN\r>"
            case "010C": return "41 0C 1A F8\r>"
            default: return command+"\r>OK\r>" // Ignore echo-only prompt, await configuration acknowledgment.
            }
        }
        let channel = ELMAccessoryChannel(streams:streams)
        defer { channel.disconnect() }
        try await channel.open()
        let identity = try await ELMIdentification.read(command:channel.command)
        XCTAssertEqual(identity.supportedPIDs,[12,13]); XCTAssertNil(identity.vin)
        let sample = try await channel.command("010C")
        XCTAssertEqual(OBDDecoder.decode(sample,pid:12)?.signals["rpm"],1726)
        let commands = String(decoding:streams.written,as:UTF8.self).split(separator:"\r").map(String.init)
        XCTAssertEqual(commands,["ATI","ATD","ATE0","ATL0","ATS1","ATH1","ATCAF1","ATSP0","0902","ATH0","0100","ATDP","010C"])
        XCTAssertFalse(commands.contains("04"))
    }
    @MainActor
    func testOutputBackpressureAndDisconnectResumePendingCommand() async throws {
        let streams = FixtureAccessoryStreams(); let channel = ELMAccessoryChannel(streams:streams)
        try await channel.open(); streams.hasSpace = false
        let request = Task { try await channel.command("010C") }
        await Task.yield()
        XCTAssertTrue(streams.written.isEmpty)
        streams.hasSpace = true; streams.onEvent?(.hasSpaceAvailable)
        XCTAssertEqual(String(decoding:streams.written,as:UTF8.self),"010C\r")
        streams.onEvent?(.endEncountered)
        do { _ = try await request.value; XCTFail("Disconnect did not fail the request") } catch {}
        XCTAssertEqual(streams.closes,1)
        do { _ = try await channel.command("010D"); XCTFail("Disconnected channel accepted a command") } catch {}
    }
    @MainActor
    func testCancellationTimeoutAndResponseLimitCloseStreams() async throws {
        let streams = FixtureAccessoryStreams(); let channel = ELMAccessoryChannel(streams:streams)
        try await channel.open()
        let request = Task { try await channel.command("ATI") }
        await Task.yield(); request.cancel()
        do { _ = try await request.value; XCTFail("Cancelled command completed") } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
        XCTAssertEqual(streams.closes,1)
        let silent = FixtureAccessoryStreams(); let timeout = ELMAccessoryChannel(streams:silent,timeoutNanoseconds:20_000_000)
        try await timeout.open()
        do { _ = try await timeout.command("ATI"); XCTFail("Silent accessory did not time out") } catch { XCTAssertTrue(error.localizedDescription.contains("timed out waiting for ATI")) }
        XCTAssertEqual(silent.closes,1)
        let noisy = FixtureAccessoryStreams(); let limit = ELMAccessoryChannel(streams:noisy)
        try await limit.open()
        let overflow = Task { try await limit.command("ATI") }
        await Task.yield(); noisy.inject(Data(repeating:65,count:64_001))
        do { _ = try await overflow.value; XCTFail("Oversized response accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("64 KB")) }
        XCTAssertEqual(noisy.closes,1)
    }
    @MainActor
    func testMXPlusFilteringAndLegacySettings() throws {
        XCTAssertTrue(MXPlusAccessory.matches(name:"OBDLink MX+",model:"MX201",protocols:["com.obdlink"]))
        XCTAssertTrue(MXPlusAccessory.matches(name:"Renamed adapter",model:"MX201",protocols:["com.obdlink"]))
        XCTAssertFalse(MXPlusAccessory.matches(name:"OBDLink MX+",model:"MX201",protocols:[]))
        XCTAssertFalse(MXPlusAccessory.matches(name:"OBDLink CX",model:"CX",protocols:["com.obdlink"]))
        let legacy = try JSONDecoder().decode(ScannerSettings.self,from:Data(#"{"host":"192.168.0.10","port":35000}"#.utf8))
        XCTAssertEqual(legacy.kind,.wifi)
        let bluetooth = ScannerSettings(transport:.obdLinkMXPlus,accessorySerial:"SYNTHETIC SERIAL")
        XCTAssertEqual(try JSONDecoder().decode(ScannerSettings.self,from:JSONEncoder().encode(bluetooth)),bluetooth)
        XCTAssertNotEqual(legacy,bluetooth)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey:"UISupportedExternalAccessoryProtocols") as? [String],["com.obdlink"])
    }
    func testNonScannerCannotClaimBluetoothProvenance() throws {
        var trip = Trip(name:"GPS fixture",startedAt:Date(),duration:1,distanceKM:0,source:.phoneGPS,isSample:false)
        trip.scannerTransport = .obdLinkMXPlus
        XCTAssertThrowsError(try TripArchive.decode(TripArchive(trips:[trip]).encoded()))
        XCTAssertThrowsError(try MacRecording.encode(trip))
    }

}


extension MXPlusTransportTests {
    @MainActor
    func testForegroundCancellationDrainsReplyBeforeReusingChannel() async throws {
        let streams=FixtureAccessoryStreams()
        let channel=ELMAccessoryChannel(streams:streams,drainOnCancellation:true)
        defer { channel.disconnect() }
        try await channel.open()
        let pending=Task { try await channel.command("010C") }
        await Task.yield();pending.cancel();await Task.yield()
        XCTAssertEqual(streams.closes,0)
        streams.inject(Data("410C0D00\r>".utf8))
        do { _ = try await pending.value;XCTFail("Canceled reading was published") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(channel.reusable);XCTAssertEqual(streams.closes,0)
        streams.response = { _ in "410D00\r>" }
        let reply=try await channel.command("010D")
        XCTAssertEqual(OBDDecoder.decode(reply,pid:13)?.signals["speedKph"],0)
    }
    @MainActor
    func testForegroundOpeningCancellationLeavesOpenedChannelReusable() async throws {
        let streams=FixtureAccessoryStreams();streams.openImmediately=false
        let channel=ELMAccessoryChannel(streams:streams,drainOnCancellation:true)
        defer { channel.disconnect() }
        let opening=Task { try await channel.open() }
        await Task.yield();opening.cancel();await Task.yield()
        XCTAssertEqual(streams.closes,0)
        streams.isOpen=true;streams.onEvent?(.openCompleted)
        do { try await opening.value;XCTFail("Canceled opening completed") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(channel.reusable)
        streams.response = { _ in "ELM327 FIXTURE\r>" }
        let reply=try await channel.command("ATI")
        XCTAssertTrue(reply.contains("ELM327"))
    }
}
