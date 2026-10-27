import Foundation

/// Caller supplies elapsed seconds from one clock epoch. No wall-clock schedule.
public struct TelemetryScheduler: Sendable {
    public struct Work: Equatable, Sendable { public var pids:[Int]; public var due:Double }
    private var work:[Work]
    private var failures:[String:Int]=[:]
    private var windowStart:Double
    private var occupied=0.0
    private var complete=0
    private var failed=0
    private var lastAdjustment:Double
    public private(set) var driveHz=1.0
    public private(set) var exchanges=0
    public private(set) var splitGroups=0
    public init(supported:Set<Int>, jetta:Bool, now:Double) {
        let groups=jetta ? [[0x0D,0x0C,0x5E,0x70],[0x78,0x7A],[0x04,0x10],[0x05,0x33,0x42],[0x8B]] : []
        var used=Set<Int>(), work:[Work]=[]
        for group in groups {
            let pids=group.filter { supported.contains($0) }; used.formUnion(pids)
            if !pids.isEmpty { work.append(.init(pids:pids,due:now)) }
        }
        for pid in supported.sorted() where TelemetryPID.lengths[pid] != nil && !used.contains(pid) { work.append(.init(pids:[pid],due:now)) }
        self.work=work; windowStart=now; lastAdjustment=now
    }
    public mutating func next(now:Double)->Work? {
        let due=work.indices.filter { work[$0].due <= now }
        guard let index=due.min(by:{ a,b in
            let ap=Self.core(work[a].pids), bp=Self.core(work[b].pids)
            return ap != bp ? ap : work[a].due < work[b].due
        }) else { return nil }
        let next=work[index]
        // Reserve now; completion reschedules from completion, never catches up.
        work[index].due = .infinity
        return next
    }
    private static func core(_ pids:[Int])->Bool { pids.contains { [0x0D,0x0C,0x5E].contains($0) } }
    public mutating func record(_ request:Work, valid:Set<Int>, latency:Double, now:Double) {
        exchanges += 1; occupied += max(0,latency)
        let good=Set(request.pids).isSubset(of:valid), key=request.pids.description
        if good { complete += 1; failures[key]=0 } else { failed += 1; failures[key,default:0] += 1 }
        guard let index=work.firstIndex(where:{$0.pids == request.pids}) else { return }
        if !good,request.pids.count > 1,failures[key,default:0] >= 2 {
            work.remove(at:index)
            work += request.pids.map { .init(pids:[$0],due:now+0.02) }; splitGroups += 1
        } else {
            let normal=request.pids == [0x46] ? 300.0 : (Self.core(request.pids) ? 1/driveHz : (request.pids.contains(0x78) || request.pids.contains(0x04) ? 1:5))
            let delay=good ? normal : min(max(30,normal),normal*pow(2,Double(min(5,failures[key,default:0]))))
            work[index].due=now+max(0.02,delay-max(0,latency))
        }
        if now-windowStart >= 10 {
            let occupancy=occupied/max(0.001,now-windowStart)
            if failed > 0 || occupancy > 0.6 || latency > 0.25 {
                driveHz=max(1,driveHz-1); lastAdjustment=now
            } else if complete >= 10, occupancy < 0.4, now-lastAdjustment >= 30 {
                driveHz=min(3,driveHz+1); lastAdjustment=now
            }
            windowStart=now; occupied=0; complete=0; failed=0
        }
    }
}

public struct TelemetryHint: Sendable {
    private var count:Int?
    private var consistent=0
    private var uses=0
    public init() {}
    public mutating func observe(unhinted:Bool, complete:Bool, frames:Int) {
        guard complete,frames > 0,frames <= 15 else { self=Self(); return }
        if !unhinted { if frames != count { self=Self() }; return }
        if count == frames { consistent += 1 } else { count=frames; consistent=1 }
    }
    public mutating func take(adapterVerified:Bool)->Int? {
        guard adapterVerified,consistent >= 3 else { return nil }
        uses += 1
        return uses % 10 == 0 ? nil:count
    }
    public mutating func invalidate() { self=Self() }
}

public struct TelemetryRates: Sendable {
    public struct Summary: Codable, Sendable {
        public var windowSeconds:Double
        public var validCount:Int
        public var attempts:Int
        public var hertz:Double
        public var p50Latency:Double
        public var p95Latency:Double
        public var p95Gap:Double
        public var maximumGap:Double
    }
    private struct Receipt:Sendable { var time:Double;var latency:Double;var valid:Bool }
    private var receipts:[Int:[Receipt]]=[:]
    public init() {}
    public mutating func record(pids:[Int],valid:Set<Int>,latency:Double,at now:Double) {
        for pid in pids {
            receipts[pid,default:[]].append(.init(time:now,latency:latency,valid:valid.contains(pid)))
            receipts[pid]=Array(receipts[pid]!.filter { now-$0.time <= 60 }.suffix(512))
        }
    }
    public func summaries(now:Double,window:Double)->[Int:Summary] {
        receipts.mapValues { all in
            let values=all.filter { now-$0.time <= window && now >= $0.time }, good=values.filter(\.valid)
            let gaps=zip(good,good.dropFirst()).map { $1.time-$0.time }
            func percentile(_ a:[Double],_ fraction:Double)->Double { a.isEmpty ? 0:a.sorted()[Int(Double(a.count-1)*fraction)] }
            return .init(windowSeconds:window,validCount:good.count,attempts:values.count,hertz:Double(good.count)/window,
                p50Latency:percentile(values.map(\.latency),0.5),p95Latency:percentile(values.map(\.latency),0.95),
                p95Gap:percentile(gaps,0.95),maximumGap:max(gaps.max() ?? 0,good.last.map { now-$0.time } ?? window))
        }
    }
}
