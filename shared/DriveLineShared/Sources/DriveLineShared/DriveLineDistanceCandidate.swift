import Foundation

/// Derived evidence only; never serialized over an original recording.
public struct DriveLineDistanceCandidate: Equatable, Sendable {
    public var sourceID: String
    public var distanceKm: Double
    public var intervals: [DateInterval]
    public var recordingSeconds: Double
    public var coveredSeconds: Double { intervals.reduce(0) { $0 + $1.duration } }
    public var coverageFraction: Double { recordingSeconds > 0 ? min(1,coveredSeconds/recordingSeconds):0 }
}

extension DriveLineMetricPolicy {
    public static func selectDistance(_ candidates:[DriveLineDistanceCandidate])->DriveLineDistanceCandidate? {
        guard let best=candidates.max(by:{ $0.coverageFraction < $1.coverageFraction }) else { return nil }
        if let gps=candidates.first(where:{$0.sourceID == "gps"}),
           gps.coverageFraction >= best.coverageFraction - comparableDistanceCoverage { return gps }
        return best
    }

    public static func distanceCandidates(for recording:DriveLineRecording)->[DriveLineDistanceCandidate] {
        let duration=max(0,recording.endedAt.timeIntervalSince(recording.startedAt))
        var result:[DriveLineDistanceCandidate]=[]
        let points=recording.gpsPoints.filter { $0.timestamp >= recording.startedAt && $0.timestamp <= recording.endedAt }
        let segments=routeSegments(points)
        let gpsIntervals=segments.flatMap { segment in
            zip(segment,segment.dropFirst()).map { DateInterval(start:$0.timestamp,end:$1.timestamp) }
        }
        if let km=distanceFromGPS(points),!gpsIntervals.isEmpty {
            result.append(.init(sourceID:"gps",distanceKm:km,intervals:gpsIntervals,recordingSeconds:duration))
        }
        let groups=Dictionary(grouping:recording.signalSamples.filter {
            $0.timestamp >= recording.startedAt && $0.timestamp <= recording.endedAt &&
            $0.values["speedKph"].map { $0.isFinite && (0...maximumPlausibleSpeedKph).contains($0) } == true
        },by:\.sourceID)
        for source in groups.keys.sorted() {
            let samples=groups[source]!.sorted { $0.timestamp < $1.timestamp }
            let intervals=zip(samples,samples.dropFirst()).compactMap { a,b -> DateInterval? in
                let seconds=b.timestamp.timeIntervalSince(a.timestamp)
                return seconds > 0 && seconds <= maximumSignalGap ? DateInterval(start:a.timestamp,end:b.timestamp):nil
            }
            if let speed=integral("speedKph",samples:samples) {
                result.append(.init(sourceID:"speedKph",distanceKm:speed.value/3600,intervals:intervals,recordingSeconds:duration))
            }
        }
        return result
    }
}
