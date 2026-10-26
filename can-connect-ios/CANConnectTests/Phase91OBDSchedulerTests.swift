import XCTest
@testable import CANConnect

final class Phase91OBDSchedulerTests:XCTestCase {
    func testCorePIDDeadlineFairnessPrecedesSecondaryAndSlowWork() throws {
        let start=ContinuousClock.now
        var scheduler=OBDPollScheduler(pids:[0x33,0x05,0x0D,0x0C],now:start)
        let first=try XCTUnwrap(scheduler.next(at:start));XCTAssertEqual(first.tier,.core)
        scheduler.record(first,outcome:.success,responseLatency:0.02,at:start)
        let second=try XCTUnwrap(scheduler.next(at:start));XCTAssertEqual(second.tier,.core);XCTAssertNotEqual(first.pid,second.pid)
        scheduler.record(second,outcome:.success,responseLatency:0.02,at:start)
        XCTAssertEqual(scheduler.next(at:start)?.tier,.secondary)
    }
    func testContinuouslyOverdueCoreStillAllowsBoundedOtherTierOpportunities() throws {
        let start=ContinuousClock.now
        var scheduler=OBDPollScheduler(pids:[0x0C,0x0D,0x05,0x0B,0x33],now:start)
        var tiers:[OBDPollTier]=[]
        for offset in 0..<24 {
            let now=start.advanced(by:.seconds(offset))
            let request=try XCTUnwrap(scheduler.next(at:now));tiers.append(request.tier)
            scheduler.record(request,outcome:.success,responseLatency:0.8,at:now)
        }
        XCTAssertTrue(tiers.contains(.secondary));XCTAssertTrue(tiers.contains(.slowDiagnostic))
        XCTAssertGreaterThan(tiers.filter{$0 == .core}.count,tiers.filter{$0 == .slowDiagnostic}.count)
        var consecutiveCore=0
        for tier in tiers {
            consecutiveCore = tier == .core ? consecutiveCore+1:0
            XCTAssertLessThanOrEqual(consecutiveCore,2)
        }
    }
    func testOptionalTimeoutBackoffAndPeriodicRecovery() throws {
        let start=ContinuousClock.now
        var scheduler=OBDPollScheduler(pids:[0x33],now:start)
        let request=try XCTUnwrap(scheduler.next(at:start))
        scheduler.record(request,outcome:.timeout,responseLatency:2,at:start)
        XCTAssertNil(scheduler.next(at:start.advanced(by:.seconds(9))))
        let probe=try XCTUnwrap(scheduler.next(at:start.advanced(by:.seconds(10))))
        scheduler.record(probe,outcome:.success,responseLatency:0.03,at:start.advanced(by:.seconds(10)))
        let stats=try XCTUnwrap(scheduler.diagnostics(at:start.advanced(by:.seconds(11))).pids[0x33])
        XCTAssertEqual(stats.timeouts,1);XCTAssertEqual(stats.successes,1);XCTAssertEqual(stats.backoffSeconds,0)
    }
    func testSlowOptionalFailureCannotConsumeNextCoreDeadline() throws {
        let start=ContinuousClock.now
        var scheduler=OBDPollScheduler(pids:[0x0C,0x0D,0x33],now:start)
        for _ in 0..<2 {
            let request=try XCTUnwrap(scheduler.next(at:start));XCTAssertEqual(request.tier,.core)
            scheduler.record(request,outcome:.success,responseLatency:0.02,at:start)
        }
        let optional=try XCTUnwrap(scheduler.next(at:start));XCTAssertEqual(optional.pid,0x33)
        scheduler.record(optional,outcome:.noData,responseLatency:1,at:start.advanced(by:.seconds(1)))
        let next=try XCTUnwrap(scheduler.next(at:start.advanced(by:.seconds(1))))
        XCTAssertEqual(next.tier,.core,"Backed-off optional work must yield to overdue RPM/speed")
    }
    func testEnhancedWindowIsBoundedToOneWindowAndImmediatelyReprioritizesRPM() throws {
        let start=ContinuousClock.now
        var scheduler=OBDPollScheduler(pids:[0x0C],now:start)
        let rpm=try XCTUnwrap(scheduler.next(at:start));scheduler.record(rpm,outcome:.success,responseLatency:0.02,at:start)
        XCTAssertTrue(scheduler.enhancedWindowOpportunity(at:start.advanced(by:.milliseconds(100))))
        let end=start.advanced(by:.seconds(7));scheduler.recordEnhancedWindow(seconds:7);scheduler.prioritizeCore(at:end)
        XCTAssertEqual(scheduler.next(at:end)?.pid,0x0C)
        let diagnostics=scheduler.diagnostics(at:end)
        XCTAssertEqual(diagnostics.enhancedWindowCount,1);XCTAssertEqual(diagnostics.enhancedWindowMaximumSeconds,7)
    }
    func testMAPBoostAndBarometerRemainScheduledWhenVehicleReportsSupport() {
        let start=ContinuousClock.now
        var scheduler=OBDPollScheduler(pids:[0x0B,0x70,0x33],now:start)
        var observed=Set<Int>()
        for _ in 0..<3 {
            guard let request=scheduler.next(at:start) else { return XCTFail("Expected due pressure PID") }
            observed.insert(request.pid);scheduler.record(request,outcome:.success,responseLatency:0.01,at:start)
        }
        XCTAssertEqual(observed,Set([0x0B,0x70,0x33]))
    }
    func testECUHeaderSeparationRejectsAmbiguousAnonymousValues() throws {
        let reply="7E8 04 41 0C 1C 98 00 00 00\r7E9 04 41 0C 00 00 00 00 00"
        XCTAssertEqual(try XCTUnwrap(OBDDecoder.decode(reply,pid:0x0C,ecu:"7E8")).signals["rpm"],1830)
        XCTAssertNil(OBDDecoder.decode(reply,pid:0x0C),"Anonymous conflicting ECUs must never be combined")
    }
}
