import Foundation

// Derived exclusively from retained raw responses. Rebuilding after relaunch,
// import or transfer does not invent samples or count an observation twice.
struct RegenReading: Codable, Equatable {
    let value: Double
    let timestamp: Date
}
struct RegenCycle: Identifiable, Codable, Equatable {
    enum Outcome: String, Codable { case completed, interrupted, partial, unconfirmed, recording }
    var id: String
    var tripID: UUID
    var vehicleID: UUID
    var startedAt: Date
    var previousInactiveAt: Date?
    var endedAt: Date
    var lastActiveAt: Date
    var outcome: Outcome
    var reason: String
    var startReadings: [String:RegenReading]
    var endReadings: [String:RegenReading]
    var peakExhaustC: Double?
    var observedDuration: TimeInterval { max(0,endedAt.timeIntervalSince(startedAt)) }
}

enum RegenAnalyzer {
    // Covers the measured ~10-second protocol-switch gap plus the three-second
    // status schedule. Longer gaps cannot establish continuous cycle evidence.
    static let maximumStatusGap: TimeInterval = 20
    private struct Candidate {
        var start: Date
        var priorInactive: Date?
        var lastActive: Date
        var activeCount: Int
        var firstInactive: Date?
    }
    static func cycles(in trip: Trip, since: Date, recording: Bool = false, now: Date = Date()) -> [RegenCycle] {
        guard !trip.isSample, trip.source == .scanner, let vehicle = trip.vehicleID else { return [] }
        let samples = (trip.samples ?? []).filter { $0.isValid && $0.timestamp >= since }.enumerated()
            .sorted { $0.element.timestamp == $1.element.timestamp ? $0.offset < $1.offset : $0.element.timestamp < $1.element.timestamp }.map(\.element)
        var result: [RegenCycle] = []
        var candidate: Candidate?
        var previousStatus: Date?
        var inactive: Date?
        var segmentStart = samples.first?.timestamp ?? trip.startedAt
        let keys = ["dpfSootG","dpfRegenTrigger","dpfDifferentialKpa","rpm","engineLoad","egt1C","egt2C","egt3C","egt4C"]
        func readings(near date: Date, segmentEnd: Date) -> [String:RegenReading] {
            var values: [String:RegenReading] = [:]
            for sample in samples where sample.timestamp >= segmentStart && sample.timestamp <= segmentEnd {
                for key in keys {
                    guard let value = sample.signals[key] else { continue }
                    let age = abs(sample.timestamp.timeIntervalSince(date))
                    guard age <= (key == "dpfSootG" ? 75 : 10) else { continue }
                    if let existing = values[key], abs(existing.timestamp.timeIntervalSince(date)) <= age { continue }
                    values[key] = RegenReading(value:value,timestamp:sample.timestamp)
                }
            }
            return values
        }
        func finish(_ c: Candidate, at end: Date, outcome: RegenCycle.Outcome, reason: String, segmentEnd: Date) {
            let peak = samples.filter { $0.timestamp >= c.start && $0.timestamp <= end }.flatMap {
                sample in ["egt1C","egt2C","egt3C","egt4C"].compactMap { sample.signals[$0] }
            }.max()
            result.append(RegenCycle(id:"\(trip.id.uuidString):\(c.start.timeIntervalSince1970)",tripID:trip.id,vehicleID:vehicle,
                startedAt:c.start,previousInactiveAt:c.priorInactive,endedAt:end,lastActiveAt:c.lastActive,
                outcome:outcome,reason:reason,startReadings:readings(near:c.start,segmentEnd:segmentEnd),
                endReadings:readings(near:end,segmentEnd:segmentEnd),peakExhaustC:peak))
        }
        for sample in samples {
            guard let active = sample.signals["dpfRegenActive"], active == 0 || active == 1 else { continue }
            if let previous = previousStatus {
                if sample.timestamp <= previous { continue } // duplicate status does not confirm a transition
                if sample.timestamp.timeIntervalSince(previous) > maximumStatusGap {
                    if let c = candidate { finish(c,at:c.lastActive,outcome:.interrupted,reason:"Regeneration-status data gap; end not confirmed",segmentEnd:previous) }
                    candidate = nil; inactive = nil; segmentStart = sample.timestamp
                }
            }
            previousStatus = sample.timestamp
            if active == 1 {
                if candidate == nil { candidate = Candidate(start:sample.timestamp,priorInactive:inactive,lastActive:sample.timestamp,activeCount:0) }
                candidate?.lastActive = sample.timestamp
                candidate?.activeCount += 1
                candidate?.firstInactive = nil
                inactive = nil
            } else {
                if var c = candidate {
                    if let end = c.firstInactive {
                        let outcome: RegenCycle.Outcome = c.activeCount < 2 ? .unconfirmed : c.priorInactive == nil ? .partial : .completed
                        let reason = outcome == .completed ? "Inactive → active → inactive observed; end confirmed twice" : outcome == .partial ? "Recording began during regeneration; start not observed" : "Only one active-status response; cycle not confirmed"
                        finish(c,at:end,outcome:outcome,reason:reason,segmentEnd:sample.timestamp)
                        candidate = nil
                    } else { c.firstInactive = sample.timestamp; candidate = c }
                }
                inactive = sample.timestamp
            }
        }
        if let c = candidate {
            let live = recording && previousStatus.map { now.timeIntervalSince($0) <= maximumStatusGap && now >= $0 } == true
            finish(c,at:c.lastActive,outcome:live ? .recording : .interrupted,
                reason:live ? "Recording in progress; end not yet confirmed" : "Recording ended before a confirmed inactive status",segmentEnd:samples.last?.timestamp ?? c.lastActive)
        }
        return result
    }
    static func history(trips: [Trip], vehicleID: UUID?, since: Date, draft: RecordingDraft? = nil, now: Date = Date()) -> [RegenCycle] {
        guard let vehicleID else { return [] }
        var seen = Set<UUID>()
        var output = trips.filter { $0.vehicleID == vehicleID && seen.insert($0.id).inserted }
            .flatMap { cycles(in:$0,since:since) }
        if let draft, draft.vehicleID == vehicleID, !seen.contains(draft.id) {
            output += cycles(in:draft.trip(endedAt:draft.updatedAt),since:since,recording:true,now:now)
        }
        return output.sorted { $0.startedAt > $1.startedAt }
    }
}
