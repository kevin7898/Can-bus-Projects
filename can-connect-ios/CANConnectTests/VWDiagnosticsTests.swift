import XCTest
@testable import CANConnect

final class VWDiagnosticsTests: XCTestCase {
    @MainActor
    func testVWReconnectClearsRawCANSettingsBeforeVehicleIdentification() async throws {
        for restore in [false,true] {
            var commands: [String] = []
            _ = try await ELMIdentification.read(restoreCANDefaults:restore) { command in
                commands.append(command)
                switch command {
                case "ATI": return "SYNTHETIC ELM"
                case "0902": return "NO DATA"
                case "0100": return "410000100000"
                case "ATDP": return "ISO 15765-4 CAN"
                default: return "OK"
                }
            }
            let identify = try XCTUnwrap(commands.firstIndex(of:"0902"))
            for reset in ["ATCFC1","ATAT1","ATST32","ATSH7DF","ATCRA"] {
                if restore { XCTAssertLessThan(try XCTUnwrap(commands.firstIndex(of:reset)),identify) }
                else { XCTAssertFalse(commands.contains(reset),"Generic non-CAN adapters keep their original startup path") }
            }
        }
    }
    func testCalibrationRequiresCompleteReplyFromCorrectControllerAndExactSoftware() {
        func reply(_ text: String, header: String = "7E8") -> String {
            let p: [UInt8] = [0x49,0x04,1]+Array(text.utf8)
            return ["\(header) 10 13 " + p.prefix(6).map{String(format:"%02X",$0)}.joined(separator:" "),
                    "\(header) 21 " + p.dropFirst(6).prefix(7).map{String(format:"%02X",$0)}.joined(separator:" "),
                    "\(header) 22 " + p.dropFirst(13).map{String(format:"%02X",$0)}.joined(separator:" ")].joined(separator:"\r")
        }
        XCTAssertTrue(VWController.engine.matchesCalibration(reply("03L997030M  9983")))
        XCTAssertFalse(VWController.engine.matchesCalibration(reply("03L997030M  9984")))
        XCTAssertFalse(VWController.engine.matchesCalibration(reply("03L997030M  9983",header:"7E9")))
        XCTAssertFalse(VWController.engine.matchesCalibration("49040130334C"))
        XCTAssertTrue(VWController.dsg.matchesCalibration(reply("02E300062B  9430",header:"7E9")))
    }
    func testRawCANAndVWReassemblyRejectMalformedWrongECUAndMissingFrames() throws {
        XCTAssertEqual(VWRawFrame.parse("300 10 00 02 50 89\r7E8 04 41 0C 00 00\r300 XX\r",address:0x300).count,1)
        var message = VWMessageAssembler();message.beginMessage()
        XCTAssertTrue(try message.accept([0x10,0,2,0x50,0x89]))
        XCTAssertEqual(message.payload,[0x50,0x89])
        message.beginMessage()
        XCTAssertFalse(try message.accept([0x21,0,8,0x61,0x13,0x1A,0,80]))
        XCTAssertTrue(try message.accept([0x12,0x25,0,0]))
        XCTAssertEqual(message.payload,[0x61,0x13,0x1A,0,80,0x25,0,0])
        var missing = VWMessageAssembler();missing.beginMessage()
        _ = try missing.accept([0x20,0,8,0x61,0x13,0x1A,0,80])
        XCTAssertThrowsError(try missing.accept([0x12,0x25,0,0]))
        XCTAssertNil(missing.payload)
        var truncated = VWMessageAssembler();truncated.beginMessage()
        XCTAssertThrowsError(try truncated.accept([0x10,0,8,0x61,0x13]))
        var oversized = VWMessageAssembler();oversized.beginMessage()
        XCTAssertThrowsError(try oversized.accept([0x10,0,1,0x50,0x89]))
    }
    func testTypedAshAndDSGReadingsDoNotTurnBlankSootFieldsIntoZero() throws {
        let ash: [UInt8] = [0x61,108,0x68,5,141]+Array(repeating:[UInt8(0x25),0,0],count:3).flatMap{$0}
        let response = VWMeasurementReply(payload:ash,raw:"SYNTHETIC VW ash fixture",requestHeader:"740",responseHeader:"300",timestamp:Date())
        let sample = try XCTUnwrap(VWMeasurementDecoder.decode(response,controller:.engine,group:108))
        XCTAssertEqual(sample.signals,["dpfAshML":13]);XCTAssertTrue(sample.isValid)
        XCTAssertNil(sample.signals["dpfSootCalculatedG"])
        XCTAssertNil(VWMeasurementDecoder.decode(response,controller:.dsg,group:108))
        var rejected = response;rejected.payload = [0x7F,0x21,0x31]
        XCTAssertNil(VWMeasurementDecoder.decode(rejected,controller:.engine,group:241))
        let dsg = VWMeasurementReply(payload:[0x61,19,0x1A,3,83,0x25,0,0,0x25,0,0,0x25,0,0],raw:"SYNTHETIC DSG fixture",requestHeader:"760",responseHeader:"300",timestamp:Date())
        XCTAssertEqual(VWMeasurementDecoder.decode(dsg,controller:.dsg,group:19)?.signals,["dsgFluidC":80])
    }
    func testBlock114SootRequiresCorrectControllerFieldTypeAndCompletePayload() throws {
        let blank: [UInt8] = [0x25,0,0]
        let fields: [UInt8] = Array(repeating:blank,count:5).flatMap { (field: [UInt8]) -> [UInt8] in field } + [0x7E,2,43] + blank + blank
        var response = VWMeasurementReply(payload:[0x61,114]+fields,raw:"SYNTHETIC block 114",requestHeader:"740",responseHeader:"300",timestamp:Date(timeIntervalSince1970:1700000000.25))
        let sample = try XCTUnwrap(VWMeasurementDecoder.decode(response,controller:.engine,group:114))
        XCTAssertEqual(sample.signals,["dpfSootG":8.6]); XCTAssertTrue(sample.isValid)
        XCTAssertNil(VWMeasurementDecoder.decode(response,controller:.dsg,group:114))
        XCTAssertEqual(try TripArchive.decode(TripArchive(trips:[Trip(name:"Synthetic soot",startedAt:response.timestamp,duration:1,distanceKM:0,source:.scanner,isSample:true,samples:[sample])]).encoded()).trips.first?.samples?.first,sample)
        response.payload.removeLast()
        XCTAssertNil(VWMeasurementDecoder.decode(response,controller:.engine,group:114))
        response.payload = [0x61,114]+Array(repeating:blank,count:8).flatMap{$0}
        XCTAssertNil(VWMeasurementDecoder.decode(response,controller:.engine,group:114),"Blank is not zero soot")
        response.payload = [0x7F,0x21,0x31]
        XCTAssertNil(VWMeasurementDecoder.decode(response,controller:.engine,group:114))
        XCTAssertEqual(VWMeasurementDecoder.freshness(for:"rpm"),10)
        XCTAssertGreaterThan(VWMeasurementDecoder.freshness(for:"dpfSootG"),VWController.engine.pollInterval+6)
    }
    @MainActor
    func testEngineQuietWindowTransientRejectionRetryAndCancellation() async throws {
        let fixture = VWProtocolFixture(); var pauses: [TimeInterval] = []
        let reader = VWMeasuringBlocks(exchange:fixture.command,pause:{ seconds in pauses.append(seconds) })
        fixture.rejectEngine = true
        let unavailable = try await reader.read(controllers:[.engine])
        XCTAssertTrue(unavailable.isEmpty); XCTAssertEqual(pauses,[6])
        fixture.rejectEngine = false
        let recovered = try await reader.read(controllers:[.engine])
        XCTAssertTrue(recovered.contains{$0.signals["dpfSootG"] == 8.6})
        XCTAssertEqual(pauses,[6,6],"D7 must not disable the engine for the entire trip")
        _ = try await reader.read(controllers:[.dsg]); XCTAssertEqual(pauses,[6,6],"DSG needs no engine quiet window")
        let canceledFixture = VWProtocolFixture(); var waiting = false
        let canceled = VWMeasuringBlocks(exchange:canceledFixture.command,pause:{ _ in
            waiting = true; try await Task.sleep(nanoseconds:5_000_000_000)
        })
        let task = Task { try await canceled.read(controllers:[.engine]) }
        while !waiting { await Task.yield() }; task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must stop before channel setup") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(canceledFixture.commands.contains("01C000100003011"))
        XCTAssertEqual(Array(canceledFixture.commands.suffix(VWMeasuringBlocks.restoreCommands.count)),VWMeasuringBlocks.restoreCommands)
    }
    func testVWRecordingAndWirePreserveValuesAndNegotiatedCANIdentity() throws {
        let sample = OBDSample(timestamp:Date(timeIntervalSince1970:1700000000.25),signals:["dsgFluidC":80],command:"2113",reply:"SYNTHETIC VW CAN frames",requestHeader:"760",responseHeader:"300")
        var draft = RecordingDraft(source:.scanner,startedAt:sample.timestamp,updatedAt:sample.timestamp,scannerTransport:.obdLinkMXPlus)
        draft.accept(sample); let trip = draft.trip(endedAt:sample.timestamp.addingTimeInterval(1))
        XCTAssertEqual(try TripArchive.decode(TripArchive(trips:[trip]).encoded()).trips.first?.samples?.first,sample)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with:MacRecording.encode(trip)) as? [String:Any])
        let row = try XCTUnwrap((wire["samples"] as? [[String:Any]])?.first)
        XCTAssertEqual(row["obdResponseHeader"] as? String,"300")
        XCTAssertEqual(row["obdRequestHeader"] as? String,"760")
        XCTAssertEqual((row["signals"] as? [String:Double])?["dsgFluidC"],80)
    }
    @MainActor
    func testTwoControllersUnsupportedBlocksAndStandardAdapterRestoration() async throws {
        let fixture = VWProtocolFixture(); let reader = VWMeasuringBlocks(exchange:fixture.command,pause:{ _ in })
        let first = try await reader.read(controllers:[.engine,.dsg])
        XCTAssertEqual(first.count,3)
        XCTAssertEqual(first.first?.signals,["dpfAshML":13]);XCTAssertEqual(first.last?.signals,["dsgFluidC":80])
        XCTAssertEqual(Array(fixture.commands.suffix(VWMeasuringBlocks.restoreCommands.count)),VWMeasuringBlocks.restoreCommands)
        _ = try await reader.read(controllers:[.engine,.dsg])
        XCTAssertEqual(fixture.groupRequests.filter{$0==240}.count,0)
        XCTAssertEqual(fixture.groupRequests.filter{$0==241}.count,0)
        XCTAssertEqual(fixture.groupRequests.filter{$0==19}.count,2)
        XCTAssertFalse(fixture.commands.contains{$0.hasPrefix("27") || $0.hasPrefix("2E") || $0 == "04"})
    }
    @MainActor
    func testUnavailableEngineDoesNotBlockDSGAndCancellationRestoresCAN() async throws {
        let fixture = VWProtocolFixture();fixture.rejectEngine = true
        let reader = VWMeasuringBlocks(exchange:fixture.command,pause:{ _ in })
        let samples = try await reader.read(controllers:[.engine,.dsg])
        XCTAssertEqual(samples.count,1);XCTAssertEqual(samples.first?.signals,["dsgFluidC":80])
        let cancellation = VWProtocolFixture();cancellation.pauseSetup = true
        let canceled = VWMeasuringBlocks(exchange:cancellation.command,pause:{ _ in })
        let task = Task { try await canceled.read(controllers:[.engine]) }
        while !cancellation.paused { await Task.yield() }
        task.cancel()
        do { _ = try await task.value;XCTFail("Canceled VW session published readings") }
        catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
        XCTAssertEqual(Array(cancellation.commands.suffix(VWMeasuringBlocks.restoreCommands.count)),VWMeasuringBlocks.restoreCommands)
    }
}

@MainActor
private final class VWProtocolFixture {
    var commands: [String] = []
    var groupRequests: [Int] = []
    var rejectEngine = false
    var pauseSetup = false
    var paused = false
    private var controller = 1
    private var sequence: UInt8 = 0
    func command(_ text: String) async throws -> String {
        commands.append(text)
        if text.hasPrefix("AT") { return "OK" }
        if text.hasSuffix("C000100003011") {
            controller = text.hasPrefix("01") ? 1:2; sequence = 0
            if pauseSetup { paused = true;try await Task.sleep(nanoseconds:5_000_000_000) }
            return String(format:"%03X 00 %02X 00 03 %02X 07 01",0x200+controller,(rejectEngine && controller==1) ? 0xD7:0xD0,controller==1 ? 0x40:0x60)
        }
        if text == "A00F8AFF32FF1" { return "300 A1 0F 8A FF 4A FF" }
        if text == "A8" { return "300 A8" }
        if text.hasPrefix("B") { return "NO DATA" }
        let bytes = stride(from:0,to:text.count,by:2).compactMap { offset -> UInt8? in
            let start=text.index(text.startIndex,offsetBy:offset);let end=text.index(start,offsetBy:2)
            return UInt8(text[start..<end],radix:16)
        }
        guard bytes.count >= 5 else { return "NO DATA" }
        let payload: [UInt8]
        if bytes[3] == 0x10 { payload = [0x50,0x89] }
        else {
            let group=Int(bytes[4]);groupRequests.append(group)
            if group==108 {payload=[0x61,108,0x68,5,141,0x25,0,0,0x25,0,0,0x25,0,0]}
            else if group==114 {payload=[0x61,114]+Array(repeating:[UInt8(0x25),0,0],count:5).flatMap{$0}+[0x7E,2,43,0x25,0,0,0x25,0,0]}
            else if group==19 {payload=[0x61,19,0x1A,0,80,0x25,0,0,0x25,0,0,0x25,0,0]}
            else {payload=[0x7F,0x21,0x31]}
        }
        var remaining = [UInt8(0),UInt8(payload.count)]+payload
        var frames = [String(format:"300 %02X",0xB0|((bytes[0]+1)&15))]
        while !remaining.isEmpty {
            let chunk=Array(remaining.prefix(7));remaining.removeFirst(chunk.count)
            let op:UInt8 = (remaining.isEmpty ? 0x10:0x20)|sequence;sequence=(sequence+1)&15
            frames.append("300 "+([op]+chunk).map{String(format:"%02X",$0)}.joined(separator:" "))
        }
        return frames.joined(separator:"\r")
    }
}
