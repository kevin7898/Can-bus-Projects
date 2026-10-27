import Foundation

public struct DriveLineMatchedEconomy: Codable, Equatable, Sendable {
    public var fuelLitres:Double
    public var distanceKm:Double
    public var coveredSeconds:Double
    public var observedSeconds:Double
    public var distanceSource:String
    public var policyVersion = "matched-interval.v1"
    public var value:Double? { distanceKm > 0.000001 ? 100*fuelLitres/distanceKm:nil }
    public var isPartial:Bool { coveredSeconds < observedSeconds-0.001 }
    public var coverage:Double { observedSeconds > 0 ? min(1,coveredSeconds/observedSeconds):0 }
    public var missingReason:String? { value == nil ? "No matched moving distance":isPartial ? "Partial matched coverage":nil }
}

extension DriveLineMetricPolicy {
    private struct LinearSegment {
        var start:Date; var end:Date; var a:Double; var b:Double
        func integral(from:Date,to:Date)->Double {
            let duration=end.timeIntervalSince(start)
            let av=a+(b-a)*from.timeIntervalSince(start)/duration
            let bv=a+(b-a)*to.timeIntervalSince(start)/duration
            return (av+bv)/2*to.timeIntervalSince(from)
        }
    }
    /// Source-specific linear intervals, intersected before either integral.
    /// Idle fuel remains in covered time; duplicate/conflicting observations
    /// break continuity instead of double-counting overlapping intervals.
    public static func matchedEconomy(for recording:DriveLineRecording)->DriveLineMatchedEconomy? {
        guard let selected=selectDistance(distanceCandidates(for:recording)) else { return nil }
        let boundaries=recording.acquisitionInterruptions ?? []
        func segments(_ key:String, source:String)->[LinearSegment] {
            let samples=recording.signalSamples.filter { $0.sourceID == source && $0.values[key] != nil }
            let grouped=Dictionary(grouping:samples,by:\.timestamp)
            let dates=grouped.keys.sorted()
            var result:[LinearSegment]=[]
            for (a,b) in zip(dates,dates.dropFirst()) {
                let av=Set(grouped[a]!.compactMap { $0.values[key] }), bv=Set(grouped[b]!.compactMap { $0.values[key] })
                guard av.count == 1,bv.count == 1,let x=av.first,let y=bv.first,x.isFinite,y.isFinite,x >= 0,y >= 0,
                      key != "speedKph" || max(x,y) <= maximumPlausibleSpeedKph,
                      b.timeIntervalSince(a) <= maximumSignalGap,
                      !boundaries.contains(where:{$0 > a && $0 <= b}) else { continue }
                result.append(.init(start:a,end:b,a:x,b:y))
            }
            return result
        }
        var distance:[LinearSegment]=[]
        if selected.sourceID == "speedKph" {
            distance=segments("speedKph",source:selected.evidenceSourceID ?? "obd")
        } else if selected.sourceID == "gps" {
            let points=recording.gpsPoints.filter { $0.sourceID == selected.evidenceSourceID }
            for route in routeSegments(points) {
                for (a,b) in zip(route,route.dropFirst()) {
                    guard !boundaries.contains(where:{$0 > a.timestamp && $0 <= b.timestamp}) else { continue }
                    // Reuse the exact GPS filtering/distance policy. Constant
                    // segment rate is explicitly GPS-derived, not measured OBD.
                    let km=distanceFromGPS([a,b]) ?? 0
                    let speed=km*3600/b.timestamp.timeIntervalSince(a.timestamp)
                    distance.append(.init(start:a.timestamp,end:b.timestamp,a:speed,b:speed))
                }
            }
        }
        guard !distance.isEmpty else { return nil }
        let sources=Set(recording.signalSamples.filter { $0.values["fuelRateLph"] != nil }.map(\.sourceID)).sorted()
        var best:DriveLineMatchedEconomy?
        for source in sources {
            let fuel=segments("fuelRateLph",source:source)
            var i=0,j=0, litres=0.0,km=0.0,seconds=0.0
            while i < fuel.count && j < distance.count {
                let f=fuel[i],d=distance[j]
                let start=max(recording.startedAt,max(f.start,d.start)), end=min(recording.endedAt,min(f.end,d.end))
                if end > start {
                    litres += f.integral(from:start,to:end)/3600; km += d.integral(from:start,to:end)/3600
                    seconds += end.timeIntervalSince(start)
                }
                if f.end <= d.end { i += 1 } else { j += 1 }
            }
            let result=DriveLineMatchedEconomy(fuelLitres:litres,distanceKm:km,coveredSeconds:seconds,
                observedSeconds:max(0,recording.endedAt.timeIntervalSince(recording.startedAt)),distanceSource:selected.sourceID)
            if seconds > (best?.coveredSeconds ?? 0) { best=result }
        }
        return best
    }
    public static func weightedEconomy(_ results:[DriveLineMatchedEconomy])->Double? {
        let usable=results.filter { $0.value != nil && $0.policyVersion == "matched-interval.v1" }
        let km=usable.reduce(0) { $0+$1.distanceKm }
        return km > 0.000001 ? 100*usable.reduce(0) { $0+$1.fuelLitres }/km:nil
    }
}

/// Ordered live-only accumulator: constant memory. Late/duplicate samples and
/// clock/source changes interrupt continuity. Offline analysis can sort a log.
public struct TelemetryIntegral: Sendable {
    private var previous:(time:TelemetryTime,value:Double,source:String)?
    public private(set) var integral=0.0
    public private(set) var coveredSeconds=0.0
    public init() {}
    public mutating func interrupt() { previous=nil }
    public mutating func accept(time:TelemetryTime,value:Double,source:String) {
        defer { previous=value.isFinite && value >= 0 ? (time,value,source):nil }
        guard value.isFinite,value >= 0,let p=previous,p.time.epoch == time.epoch,p.source == source else { return }
        let seconds=time.monotonic-p.time.monotonic
        guard seconds > 0,seconds <= 10 else { return }
        integral += (p.value+value)/2*seconds; coveredSeconds += seconds
    }
}
