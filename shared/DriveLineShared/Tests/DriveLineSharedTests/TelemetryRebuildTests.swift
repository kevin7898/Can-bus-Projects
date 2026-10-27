import XCTest
import Darwin
@testable import DriveLineShared

final class TelemetryRebuildTests:XCTestCase {
    func testInterruptedFinalizeCanRetryWithoutAppendingOrChangingOriginal() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let url=root.appendingPathComponent("finalize.dlt")
        let log=try TelemetryLog(url:url,header:.init(recordingID:UUID(),vehicleID:UUID(),epoch:UUID()))
        let bytes=try Data(contentsOf:url)
        try FileManager.default.createDirectory(at:url.appendingPathExtension("finalized"),withIntermediateDirectories:true)
        do { _ = try await log.finish();XCTFail("Marker failure should surface") } catch {}
        do { try await log.append(TelemetryEvent("late",at:.init(epoch:UUID(),monotonic:1,wall:Date())),type:2);XCTFail("Finalizing log must be immutable") } catch {}
        try FileManager.default.removeItem(at:url.appendingPathExtension("finalized"))
        let marker=try await log.finish()
        XCTAssertEqual(marker.byteLength,UInt64(bytes.count));XCTAssertEqual(try Data(contentsOf:url),bytes)
    }

    func testInterleavedIdentityFramesStayWithECUAndRejectConflicts() throws {
        // Synthetic 17-character identities, never vehicle/user data.
        let a=vinFrames("TEST0000000000001",ecu:"7E8")
        let b=vinFrames("TEST0000000000002",ecu:"7E9")
        let reply=zip(a,b).flatMap { [$0,$1] }.joined(separator:"\r")
        let parsed=TelemetryELM.parse(reply)
        XCTAssertEqual(parsed.payloads.count,2)
        XCTAssertThrowsError(try TelemetryELM.identities(parsed.payloads))
        XCTAssertEqual(try TelemetryELM.identities(TelemetryELM.parse(a.joined(separator:"\r")).payloads)["7E8"],"TEST0000000000001")
    }
    func testBrokenSequenceTruncationAnd29BitHeaders() {
        var frames=vinFrames("TEST0000000000001",ecu:"18DAF110")
        XCTAssertEqual(TelemetryELM.parse(frames.joined(separator:"\r")).payloads.first?.ecu,"18DAF110")
        frames[1]=frames[1].replacingOccurrences(of:"21 ",with:"23 ")
        XCTAssertTrue(TelemetryELM.parse(frames.joined(separator:"\r")).payloads.isEmpty)
        XCTAssertGreaterThan(TelemetryELM.parse(frames[0]).rejected,0)
    }
    func testGroupedLayoutDoesNotScanUnknownBytes() throws {
        let p=TelemetryPayload(ecu:"7E8",bytes:[0x41,0x0D,60,0x0C,0x1A,0xF8,0x5E,0,100])
        let result=try TelemetryPID.split(p,requested:[0x0D,0x0C,0x5E])
        XCTAssertEqual(result[0x0C],[0x1A,0xF8]);XCTAssertEqual(result.count,3)
        XCTAssertThrowsError(try TelemetryPID.split(.init(ecu:"7E8",bytes:[0x41,0xFF,0x41,0x0D,60]),requested:[0x0D]))
        XCTAssertThrowsError(try TelemetryPID.split(.init(ecu:"7E8",bytes:[0x41,0x0C,1]),requested:[0x0C]))
    }
    func testTypedReadOnlyRequestsAndInformationalValidation() throws {
        XCTAssertEqual(try TelemetryRequest.standard([13,12,94]).command,"010D0C5E")
        XCTAssertThrowsError(try TelemetryRequest.standard([255]))
        XCTAssertThrowsError(try TelemetryRequest.configuration("04"))
        XCTAssertThrowsError(try TelemetryRequest.configuration("ATSH123"))
        XCTAssertThrowsError(try TelemetryRequest.route(response:"18DAF110"))
        XCTAssertNoThrow(try TelemetryRequest.information("ATRV").validate("12.6V\r>"))
        XCTAssertThrowsError(try TelemetryRequest.configuration("ATE0").validate("NOT OK"))
    }
    func testRedactionOccursBeforeEncodingIncludingMalformedAndPartialIdentity() throws {
        for command in ["0902","0904","ATI","STI","ERROR"] {
            let request=command == "0902" ? TelemetryRequest.vin : try TelemetryRequest.information("ATI")
            let time=TelemetryTime(epoch:UUID(),monotonic:1,wall:Date())
            let exchange=TelemetryExchange(sessionID:UUID(),sequence:1,request:request,reply:"partial TEST0000000000001",start:time,end:time,generation:UUID(),outcome:"prompt")
            XCTAssertFalse(String(decoding:try JSONEncoder().encode(exchange),as:UTF8.self).contains("TEST0000"))
            XCTAssertEqual(TelemetryPrivacy.reply(command:command,reply:"49 02 malformed"),"[redacted]")
        }
        XCTAssertEqual(TelemetryPrivacy.reply(command:"010C",reply:"7E8 10 14 49 02 01 54 45 53"),"[redacted]")
    }
    func testCapabilityPagesAreNotMergedAcrossECUs() {
        let result=TelemetryELM.supported(TelemetryELM.parse("7E8 06 41 00 00 18 00 01\r7E9 06 41 00 00 10 00 00").payloads,base:0)
        XCTAssertEqual(result["7E8"],[12,13,32]);XCTAssertEqual(result["7E9"],[12])
    }
    func testOffsetStartAndEndUseExactlyMatchedIntervals() throws {
        let start=Date(timeIntervalSince1970:1000)
        let samples=(0...10).flatMap { i -> [DriveLineSignalSample] in
            [.init(timestamp:start.addingTimeInterval(Double(i)),values:["speedKph":60],sourceID:"7E8"),
             .init(timestamp:start.addingTimeInterval(Double(i)+0.3),values:["fuelRateLph":6],sourceID:"7E8")]
        }
        let recording=DriveLineRecording(recordingID:UUID(),vehicleID:UUID(),name:"Synthetic offset",startedAt:start,endedAt:start.addingTimeInterval(11),sourceIDs:["7E8"],signalSamples:samples,isSample:true)
        let result=try XCTUnwrap(DriveLineMetricPolicy.matchedEconomy(for:recording))
        XCTAssertEqual(result.coveredSeconds,9.7,accuracy:0.000001)
        XCTAssertEqual(try XCTUnwrap(result.value),10,accuracy:0.000001)
        XCTAssertEqual(result.fuelLitres,6*9.7/3600,accuracy:0.000001)
        XCTAssertTrue(result.isPartial)
    }
    func testIdleFuelAndInterruptionsAndZeroDistance() throws {
        let start=Date(timeIntervalSince1970:1000)
        var recording=DriveLineRecording(recordingID:UUID(),vehicleID:UUID(),name:"Synthetic idle",startedAt:start,endedAt:start.addingTimeInterval(10),sourceIDs:["obd"],signalSamples:[0.0,5,10].map {
            .init(timestamp:start.addingTimeInterval($0),values:["speedKph":0,"fuelRateLph":2],sourceID:"obd")
        },isSample:true)
        var result=try XCTUnwrap(DriveLineMetricPolicy.matchedEconomy(for:recording))
        XCTAssertNil(result.value);XCTAssertEqual(result.fuelLitres,20.0/3600,accuracy:0.000001)
        recording.acquisitionInterruptions=[start.addingTimeInterval(3)]
        result=try XCTUnwrap(DriveLineMetricPolicy.matchedEconomy(for:recording))
        XCTAssertEqual(result.coveredSeconds,5)
    }
    func testStreamingAccumulatorNeverBridgesEpochSourceOrClockReversal() {
        let epoch=UUID();var integral=TelemetryIntegral()
        func time(_ t:Double,_ e:UUID?=nil)->TelemetryTime { .init(epoch:e ?? epoch,monotonic:t,wall:Date(timeIntervalSince1970:1000-t)) }
        integral.accept(time:time(0),value:60,source:"7E8")
        integral.accept(time:time(1),value:60,source:"7E8")
        integral.accept(time:time(2,UUID()),value:60,source:"7E8")
        integral.accept(time:time(3),value:60,source:"7E9")
        integral.accept(time:time(2),value:60,source:"7E9")
        XCTAssertEqual(integral.integral,60);XCTAssertEqual(integral.coveredSeconds,1)
    }
    func testAmbientTemperatureIsSeparateAndWaitsFiveMinutes() throws {
        var scheduler=TelemetryScheduler(supported:[0x05,0x46],jetta:true,now:0)
        let coolant=try XCTUnwrap(scheduler.next(now:0))
        XCTAssertEqual(coolant.pids,[0x05])
        scheduler.record(coolant,valid:[0x05],latency:0,now:0)
        let ambient=try XCTUnwrap(scheduler.next(now:0))
        XCTAssertEqual(ambient.pids,[0x46])
        scheduler.record(ambient,valid:[0x46],latency:0,now:0)
        for second in 1..<300 {
            if let request=scheduler.next(now:Double(second)) {
                XCTAssertFalse(request.pids.contains(0x46))
                scheduler.record(request,valid:Set(request.pids),latency:0,now:Double(second))
            }
        }
        var due=[TelemetryScheduler.Work]()
        while let request=scheduler.next(now:300) { due.append(request) }
        XCTAssertTrue(due.contains { $0.pids == [0x46] })
        XCTAssertEqual(DriveLineAcquisitionPolicy.signal("outsideC").expectedCadence,300)
        XCTAssertGreaterThan(DriveLineAcquisitionPolicy.signal("outsideC").displayValidity,300)
    }
    func testSchedulerSplitsOptionalFailureAndDoesNotCatchUpAfterStall() {
        var scheduler=TelemetryScheduler(supported:[13,12,94,112],jetta:true,now:0)
        for t in [0.0,3.0] {
            let work=scheduler.next(now:t)!
            scheduler.record(work,valid:[13,12,94],latency:0.05,now:t+0.05)
        }
        XCTAssertEqual(scheduler.splitGroups,1)
        let request=scheduler.next(now:100)!
        XCTAssertEqual(request.pids.count,1)
        scheduler.record(request,valid:Set(request.pids),latency:0.05,now:100.05)
        var remaining:[Int]=[]
        while let next=scheduler.next(now:100.05) { remaining += next.pids }
        XCTAssertFalse(remaining.contains(request.pids[0]))
    }
    func testHintRequiresThreeUnhintedRepliesAndInvalidates() {
        var hint=TelemetryHint()
        for _ in 0..<2 { hint.observe(unhinted:true,complete:true,frames:3) }
        XCTAssertNil(hint.take(adapterVerified:true))
        hint.observe(unhinted:true,complete:true,frames:3)
        XCTAssertNil(hint.take(adapterVerified:false));XCTAssertEqual(hint.take(adapterVerified:true),3)
        hint.observe(unhinted:false,complete:false,frames:2)
        XCTAssertNil(hint.take(adapterVerified:true))
    }
    func testCRCRecoveryRetainsExactPrefixAndFinalizeIsIdempotent() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let url=root.appendingPathComponent("test.dlt"), id=UUID()
        let log=try TelemetryLog(url:url,header:.init(recordingID:id,vehicleID:UUID(),epoch:UUID()))
        try await log.append(TelemetryEvent("connected",at:.init(epoch:UUID(),monotonic:0,wall:Date())),type:2,important:true)
        let marker=try await log.finish(), again=try await log.finish()
        XCTAssertEqual(marker.sha256,again.sha256);XCTAssertEqual(marker.records,2)
        let original=try Data(contentsOf:url)
        for cut in 1...min(30,original.count-8) {
            let torn=root.appendingPathComponent("torn.dlt")
            try original.dropLast(cut).write(to:torn)
            let result=try TelemetryLog.recover(url:torn)
            XCTAssertTrue(result.damagedTail);XCTAssertEqual(result.records,1)
        }
        var damaged=original;damaged[damaged.count-6] ^= 1;try damaged.write(to:url)
        XCTAssertEqual(try TelemetryLog.recover(url:url).records,1)
        XCTAssertEqual(TelemetryLog.crc32(Data("123456789".utf8)),0xCBF43926)
    }
    func testTwoHourSchedulerAndStreamingAccumulatorHaveBoundedState() {
        var scheduler=TelemetryScheduler(supported:Set(TelemetryPID.lengths.keys),jetta:true,now:0)
        var integral=TelemetryIntegral(),now=0.0,count=0
        let epoch=UUID(),start=Date()
        while now <= 7200 {
            if let work=scheduler.next(now:now) {
                scheduler.record(work,valid:Set(work.pids),latency:0.024,now:now+0.024);count += 1
            }
            integral.accept(time:.init(epoch:epoch,monotonic:now,wall:start),value:60,source:"7E8")
            now += 0.1
        }
        XCTAssertGreaterThan(count,20_000);XCTAssertEqual(scheduler.driveHz,3)
        XCTAssertEqual(integral.coveredSeconds,7200,accuracy:0.11)
    }
    private func vinFrames(_ vin:String,ecu:String)->[String] {
        let bytes=[UInt8(0x49),0x02,0x01]+Array(vin.utf8)
        let frames=[[0x10,UInt8(bytes.count)]+Array(bytes.prefix(6)),[0x21]+Array(bytes.dropFirst(6).prefix(7)),[0x22]+Array(bytes.dropFirst(13))]
        return frames.map { ecu+" "+$0.map { String(format:"%02X",$0) }.joined(separator:" ") }
    }
}

extension TelemetryRebuildTests {
    func testSixtyThousandDurableExchangesAndDeterministicReplay() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let url=root.appendingPathComponent("long-run.dlt"),epoch=UUID(),session=UUID(),generation=UUID()
        let request=try TelemetryRequest.standard([12]),wall=Date(timeIntervalSince1970:1000)
        let log=try TelemetryLog(url:url,header:.init(recordingID:session,vehicleID:UUID(),epoch:epoch))
        var first:[Double]=[],last:[Double]=[],firstRSS:UInt64=0,lastRSS:UInt64=0
        func residentBytes()->UInt64 {
            var info=mach_task_basic_info_data_t()
            var size=mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status=withUnsafeMutablePointer(to:&info) { pointer in
                pointer.withMemoryRebound(to:integer_t.self,capacity:Int(size)) { task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&size) }
            }
            return status == KERN_SUCCESS ? UInt64(info.resident_size):0
        }
        let started=ProcessInfo.processInfo.systemUptime
        for i in 0..<60_000 {
            let t=Double(i)*0.12
            let start=TelemetryTime(epoch:epoch,monotonic:t,wall:wall.addingTimeInterval(t))
            let end=TelemetryTime(epoch:epoch,monotonic:t+0.024,wall:wall.addingTimeInterval(t+0.024))
            let timer=ProcessInfo.processInfo.systemUptime
            try await log.append(TelemetryExchange(sessionID:session,sequence:UInt64(i),request:request,reply:"7E8 04 41 0C 1A F8",start:start,end:end,generation:generation,outcome:"prompt"),type:1,important:i % 9 == 0)
            let elapsed=ProcessInfo.processInfo.systemUptime-timer
            if (2500..<5000).contains(i) { first.append(elapsed) }
            if i >= 57_500 { last.append(elapsed) }
            if i == 5000 { firstRSS=residentBytes() }
            if i == 59999 { lastRSS=residentBytes() }
        }
        let marker=try await log.finish()
        XCTAssertEqual(marker.records,60_001)
        let replayStart=ProcessInfo.processInfo.systemUptime
        var sequence:UInt64=0
        let recovered=try TelemetryLog.recover(url:url) { type,data in
            if type == 1 {
                let value=try JSONDecoder().decode(TelemetryExchange.self,from:data)
                XCTAssertEqual(value.sequence,sequence);sequence += 1
                XCTAssertEqual(TelemetryELM.parse(value.reply).payloads.first?.bytes,[0x41,0x0C,0x1A,0xF8])
            }
        }
        XCTAssertEqual(sequence,60_000);XCTAssertFalse(recovered.damagedTail)
        func percentile(_ values:[Double],_ fraction:Double)->Double { values.sorted()[Int(Double(values.count-1)*fraction)] }
        let syncs=await log.syncCount
        print("REBUILD_BENCHMARK exchanges=60000 simulated_seconds=7200 first_rss=\(firstRSS) last_rss=\(lastRSS) bytes=\(marker.byteLength) syncs=\(syncs) first_p50=\(percentile(first,0.5)) first_p95=\(percentile(first,0.95)) last_p50=\(percentile(last,0.5)) last_p95=\(percentile(last,0.95)) replay_seconds=\(ProcessInfo.processInfo.systemUptime-replayStart) total_wall_seconds=\(ProcessInfo.processInfo.systemUptime-started)")
    }
}

extension TelemetryRebuildTests {
    func testRatesSeparateValidSamplesFromPromptsAndIncludeCurrentOutage() {
        var rates=TelemetryRates()
        for i in 0..<10 { rates.record(pids:[12,13],valid:i < 9 ? [12,13]:[13],latency:0.05,at:Double(i)) }
        let rpm=rates.summaries(now:15,window:10)[12]!
        XCTAssertEqual(rpm.attempts,5);XCTAssertEqual(rpm.validCount,4)
        XCTAssertEqual(rpm.hertz,0.4);XCTAssertEqual(rpm.maximumGap,7)
    }
}
