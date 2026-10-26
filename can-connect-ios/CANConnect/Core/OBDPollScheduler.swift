import Foundation

enum OBDPollTier:Int,CaseIterable,Sendable { case core,secondary,slowDiagnostic }
enum OBDPollOutcome:Sendable { case success,noData,malformed,ambiguous,timeout }

struct OBDPollRequest:Equatable,Sendable {
    var pid:Int
    var tier:OBDPollTier
    var deadline:ContinuousClock.Instant
}

struct OBDPIDDiagnostics:Equatable,Sendable {
    var pid:Int
    var tier:OBDPollTier
    var attempts=0
    var successes=0
    var timeouts=0
    var noData=0
    var malformed=0
    var ambiguous=0
    var missedDeadlines=0
    var averageRequestDelaySeconds=0.0
    var averageResponseLatencySeconds=0.0
    var effectiveCadenceSeconds:Double?
    var coverageFraction:Double?
    var backoffSeconds=0.0
}

struct OBDPollDiagnostics:Equatable,Sendable {
    var pids:[Int:OBDPIDDiagnostics]=[:]
    var enhancedWindowCount=0
    var enhancedWindowTotalSeconds=0.0
    var enhancedWindowMaximumSeconds=0.0
}

struct OBDPollScheduler {
    private struct State {
        var tier:OBDPollTier
        var interval:TimeInterval
        var deadline:ContinuousClock.Instant
        var backoffUntil:ContinuousClock.Instant?
        var consecutiveFailures=0
        var attempts=0
        var successes=0
        var timeouts=0
        var noData=0
        var malformed=0
        var ambiguous=0
        var missedDeadlines=0
        var requestDelayTotal=0.0
        var responseLatencyTotal=0.0
        var firstAttempt:ContinuousClock.Instant?
        var successTimes:[ContinuousClock.Instant]=[]
    }
    private var states:[Int:State]
    private var rotation:[OBDPollTier:Int]=[:]
    private var coreSelectionsSinceSecondary=0
    private var selectionsSinceSlow=0
    private(set) var enhancedWindowCount=0
    private(set) var enhancedWindowTotalSeconds=0.0
    private(set) var enhancedWindowMaximumSeconds=0.0

    init(pids:[Int],now:ContinuousClock.Instant) {
        states=Dictionary(uniqueKeysWithValues:pids.map { pid in
            (pid,State(tier:Self.tier(pid),interval:OBDDecoder.pollInterval(pid:pid),deadline:now))
        })
    }
    static func tier(_ pid:Int)->OBDPollTier {
        switch pid {
        case 0x0C,0x0D:return .core
        case 0x05,0x0B,0x5E,0x04,0x42,0x10,0x70:return .secondary
        default:return .slowDiagnostic
        }
    }
    mutating func next(at now:ContinuousClock.Instant)->OBDPollRequest? {
        var dueByTier:[OBDPollTier:[Int]]=[:]
        for tier in OBDPollTier.allCases {
            dueByTier[tier]=states.filter { _,state in
                state.tier == tier && now >= state.deadline && (state.backoffUntil.map { now >= $0 } ?? true)
            }.map(\.key).sorted()
        }
        let selectedTier:OBDPollTier?
        if dueByTier[.core]?.isEmpty == false {
            if selectionsSinceSlow >= 8,dueByTier[.slowDiagnostic]?.isEmpty == false { selectedTier = .slowDiagnostic }
            else if coreSelectionsSinceSecondary >= 2,dueByTier[.secondary]?.isEmpty == false { selectedTier = .secondary }
            else { selectedTier = .core }
        } else if dueByTier[.secondary]?.isEmpty == false { selectedTier = .secondary }
        else if dueByTier[.slowDiagnostic]?.isEmpty == false { selectedTier = .slowDiagnostic }
        else { selectedTier = nil }
        guard let tier=selectedTier,let due=dueByTier[tier],!due.isEmpty else { return nil }
        let index=(rotation[tier] ?? 0)%due.count
        rotation[tier]=(index+1)%due.count
        let pid=due[index]
        switch tier {
        case .core:coreSelectionsSinceSecondary += 1;selectionsSinceSlow += 1
        case .secondary:coreSelectionsSinceSecondary=0;selectionsSinceSlow += 1
        case .slowDiagnostic:coreSelectionsSinceSecondary=0;selectionsSinceSlow=0
        }
        return OBDPollRequest(pid:pid,tier:tier,deadline:states[pid]!.deadline)
    }
    mutating func record(_ request:OBDPollRequest,outcome:OBDPollOutcome,
                         responseLatency:TimeInterval,at now:ContinuousClock.Instant) {
        guard var state=states[request.pid] else { return }
        state.attempts += 1
        if state.firstAttempt == nil { state.firstAttempt=now }
        let delay=max(0,Self.seconds(request.deadline.duration(to:now)))
        state.requestDelayTotal += delay
        state.responseLatencyTotal += max(0,responseLatency)
        if delay > max(0.1,state.interval*0.5) { state.missedDeadlines += 1 }
        switch outcome {
        case .success:
            state.successes += 1;state.consecutiveFailures=0;state.backoffUntil=nil
            state.successTimes.append(now)
            if state.successTimes.count > 256 { state.successTimes.removeFirst(state.successTimes.count-256) }
            state.deadline=now.advanced(by:.seconds(state.interval))
        case .timeout,.noData,.malformed,.ambiguous:
            state.consecutiveFailures=min(state.consecutiveFailures+1,7)
            switch outcome {
            case .timeout:state.timeouts += 1
            case .noData:state.noData += 1
            case .malformed:state.malformed += 1
            case .ambiguous:state.ambiguous += 1
            case .success:break
            }
            let base:TimeInterval = state.tier == .core ? 1:(state.tier == .secondary ? 3:10)
            let delay=min(300,base*pow(2,Double(state.consecutiveFailures-1)))
            state.backoffUntil=now.advanced(by:.seconds(delay));state.deadline=state.backoffUntil!
        }
        states[request.pid]=state
    }
    mutating func prioritizeCore(at now:ContinuousClock.Instant) {
        for pid in states.keys where states[pid]?.tier == .core { states[pid]?.deadline=now;states[pid]?.backoffUntil=nil }
    }
    func enhancedWindowOpportunity(at now:ContinuousClock.Instant)->Bool {
        let core=states.values.filter{$0.tier == .core}
        return !core.isEmpty && core.allSatisfy { state in
            guard let last=state.successTimes.last else { return false }
            return Self.seconds(last.duration(to:now)) <= max(0.75,state.interval*1.5)
        }
    }
    mutating func recordEnhancedWindow(seconds:TimeInterval) {
        let value=max(0,seconds);enhancedWindowCount += 1;enhancedWindowTotalSeconds += value
        enhancedWindowMaximumSeconds=max(enhancedWindowMaximumSeconds,value)
    }
    func diagnostics(at now:ContinuousClock.Instant)->OBDPollDiagnostics {
        var result=OBDPollDiagnostics(enhancedWindowCount:enhancedWindowCount,
            enhancedWindowTotalSeconds:enhancedWindowTotalSeconds,enhancedWindowMaximumSeconds:enhancedWindowMaximumSeconds)
        for (pid,state) in states {
            let cadence:Double? = state.successTimes.count > 1 ?
                Self.seconds(state.successTimes.first!.duration(to:state.successTimes.last!))/Double(state.successTimes.count-1):nil
            let duration=state.firstAttempt.map { max(0,Self.seconds($0.duration(to:now))) } ?? 0
            var observed=0.0
            for pair in zip(state.successTimes,state.successTimes.dropFirst()) {
                observed += min(Self.seconds(pair.0.duration(to:pair.1)),max(DriveLineMetricPolicy.maximumSignalGap,state.interval*2))
            }
            let backoff=state.backoffUntil.map { max(0,Self.seconds(now.duration(to:$0))) } ?? 0
            result.pids[pid]=OBDPIDDiagnostics(pid:pid,tier:state.tier,attempts:state.attempts,successes:state.successes,
                timeouts:state.timeouts,noData:state.noData,malformed:state.malformed,ambiguous:state.ambiguous,
                missedDeadlines:state.missedDeadlines,averageRequestDelaySeconds:state.attempts>0 ? state.requestDelayTotal/Double(state.attempts):0,
                averageResponseLatencySeconds:state.attempts>0 ? state.responseLatencyTotal/Double(state.attempts):0,
                effectiveCadenceSeconds:cadence,coverageFraction:duration>0 ? min(1,observed/duration):nil,backoffSeconds:backoff)
        }
        return result
    }
    static func classify(reply:String,pid:Int,decoded:OBDSample?,ecu:String?)->OBDPollOutcome {
        if decoded != nil { return .success }
        let upper=reply.uppercased()
        if upper.contains("NO DATA") || upper.contains("UNABLE TO CONNECT") || upper.contains("STOPPED") { return .noData }
        let payloads=ELMResponses.payloads(reply,ecu:ecu).filter { $0.count >= 2 && $0[0] == 0x41 && Int($0[1]) == pid }
        if payloads.count > 1 { return .ambiguous }
        return .malformed
    }
    static func seconds(_ duration:Duration)->Double {
        let parts=duration.components
        return Double(parts.seconds)+Double(parts.attoseconds)/1_000_000_000_000_000_000
    }
}
