import Foundation

public struct DriveLineObservation: Equatable, Sendable {
    public var key: String
    public var value: Double
    public var timestamp: Date
    public var sourceID: String
    public var recordingID: UUID

    public init(key: String, value: Double, timestamp: Date, sourceID: String, recordingID: UUID) {
        self.key = key
        self.value = value
        self.timestamp = timestamp
        self.sourceID = sourceID
        self.recordingID = recordingID
    }
}

public struct DriveLineMetrics: Equatable, Sendable {
    public var distanceKm: Double?
    public var durationSeconds: Double
    public var tripFuelLitres: Double?
    public var economyL100Km: Double?
    public var coverage: [DriveLineCoverageSummary]
    public var distanceSource: String?

    public init(distanceKm: Double?, durationSeconds: Double, tripFuelLitres: Double?,
                economyL100Km: Double?, coverage: [DriveLineCoverageSummary], distanceSource: String?) {
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.tripFuelLitres = tripFuelLitres
        self.economyL100Km = economyL100Km
        self.coverage = coverage
        self.distanceSource = distanceSource
    }
}

public enum DriveLineMetricPolicy {
    public static let maximumGPSGap: TimeInterval = 30
    public static let maximumSignalGap: TimeInterval = 10
    public static let maximumHorizontalAccuracyM = 50.0
    public static let maximumPlausibleSpeedKph = 300.0
    public static let minimumGPSMovementM = 5.0
    public static let requiredFuelCoverage = 0.8
    public static let boostBarometerFreshness: TimeInterval = 75

    public static func metrics(for recording: DriveLineRecording) -> DriveLineMetrics {
        DriveLinePerformance.measure("Trip metric calculation") {
            let duration = max(0, recording.endedAt.timeIntervalSince(recording.startedAt))
            let gpsDistance = distanceFromGPS(recording.gpsPoints)
            let speed = integral("speedKph", samples: recording.signalSamples)
            let speedDistance = speed.map { $0.value / 3600 }
            let distance = gpsDistance ?? speedDistance ?? recording.recordedDistanceKm
            let fuel = integral("fuelRateLph", samples: recording.signalSamples)
            let measuredFuel = fuel.flatMap { duration > 0 && $0.coverage / duration >= requiredFuelCoverage ? $0.value / 3600 : nil }
            let tripFuel = measuredFuel ?? recording.tripFuelLitres
            let economy: Double? = distance.flatMap { km -> Double? in
                guard km > 0.1, let tripFuel else { return nil }
                return tripFuel / km * 100
            }
            return DriveLineMetrics(distanceKm: distance, durationSeconds: duration,
                tripFuelLitres: tripFuel, economyL100Km: economy,
                coverage: coverageSummaries(recording),
                distanceSource:gpsDistance != nil ? "gps" : speedDistance != nil ? "speedKph" : recording.recordedDistanceKm != nil ? "recorded" : nil)
        }
    }

    public static func routeSegments(_ points: [DriveLineGPSPoint]) -> [[DriveLineGPSPoint]] {
        DriveLinePerformance.measure("Route processing") {
            var result: [[DriveLineGPSPoint]] = []
            for point in points.sorted(by: { $0.timestamp < $1.timestamp }) where accepts(point) {
                guard let previous = result.last?.last else { result.append([point]); continue }
                let elapsed = point.timestamp.timeIntervalSince(previous.timestamp)
                let metres = haversineMetres(previous, point)
                if elapsed > 0, elapsed <= maximumGPSGap,
                   metres / elapsed * 3.6 <= maximumPlausibleSpeedKph {
                    if metres >= minimumGPSMovementM { result[result.count - 1].append(point) }
                } else { result.append([point]) }
            }
            return result
        }
    }

    public static func distanceFromGPS(_ points: [DriveLineGPSPoint]) -> Double? {
        var metres = 0.0
        var intervals = 0
        for segment in routeSegments(points) {
            for (a, b) in zip(segment, segment.dropFirst()) {
                metres += haversineMetres(a, b)
                intervals += 1
            }
        }
        return intervals > 0 ? metres / 1000 : nil
    }

    public static func integral(_ key: String, samples: [DriveLineSignalSample]) -> (value: Double, coverage: Double)? {
        let values = samples.compactMap { sample -> (Date, Double)? in
            sample.values[key].map { (sample.timestamp, $0) }
        }.sorted { $0.0 < $1.0 }
        var value = 0.0
        var coverage = 0.0
        for (a, b) in zip(values, values.dropFirst()) {
            let seconds = b.0.timeIntervalSince(a.0)
            guard seconds > 0, seconds <= maximumSignalGap, a.1 >= 0, b.1 >= 0 else { continue }
            value += (a.1 + b.1) / 2 * seconds
            coverage += seconds
        }
        return coverage > 0 ? (value, coverage) : nil
    }

    public static func coverageSummaries(_ recording: DriveLineRecording) -> [DriveLineCoverageSummary] {
        let duration = max(0, recording.endedAt.timeIntervalSince(recording.startedAt))
        var result: [DriveLineCoverageSummary] = []
        let keys = Set(recording.signalSamples.flatMap { $0.values.keys })
        for key in keys.sorted() {
            let observations = recording.signalSamples.filter { $0.values[key] != nil }.sorted { $0.timestamp < $1.timestamp }
            let observed = observationCoverage(observations.map(\.timestamp),maximumGap:maximumSignalGap)
            result.append(DriveLineCoverageSummary(key: key, observedSeconds: observed, recordingSeconds: duration,
                fraction: duration > 0 ? min(1, observed / duration) : 0,
                firstObservation: observations.first?.timestamp, lastObservation: observations.last?.timestamp,
                sourceIDs: Array(Set(observations.map(\.sourceID))).sorted()))
        }
        let acceptedGPS=recording.gpsPoints.filter(accepts).sorted { $0.timestamp < $1.timestamp }
        var gpsSeconds=0.0
        for (a,b) in zip(acceptedGPS,acceptedGPS.dropFirst()) {
            let elapsed=b.timestamp.timeIntervalSince(a.timestamp)
            let speed=elapsed > 0 ? haversineMetres(a,b)/elapsed*3.6 : .infinity
            if elapsed <= maximumGPSGap,speed <= maximumPlausibleSpeedKph { gpsSeconds += elapsed }
        }
        if !recording.gpsPoints.isEmpty {
            result.append(DriveLineCoverageSummary(key: "gps", observedSeconds: gpsSeconds, recordingSeconds: duration,
                fraction: duration > 0 ? min(1, gpsSeconds / duration) : 0,
                firstObservation: recording.gpsPoints.map(\.timestamp).min(), lastObservation: recording.gpsPoints.map(\.timestamp).max(),
                sourceIDs: Array(Set(recording.gpsPoints.map(\.sourceID))).sorted()))
        }
        return result.sorted { $0.key < $1.key }
    }

    public static func latestObservations(_ recordings: [DriveLineRecording], includeSamples: Bool = false) -> [String: DriveLineObservation] {
        var result: [String: DriveLineObservation] = [:]
        for recording in recordings where includeSamples || !recording.isSample {
            for sample in recording.signalSamples {
                for (key, value) in sample.values where result[key].map({ $0.timestamp < sample.timestamp }) ?? true {
                    result[key] = DriveLineObservation(key: key, value: value, timestamp: sample.timestamp,
                        sourceID: sample.sourceID, recordingID: recording.recordingID)
                }
            }
        }
        return result
    }

    public static func boostGaugeKpa(observations: [String: DriveLineObservation], at date: Date? = nil) -> DriveLineObservation? {
        guard let pressure = observations["boostAbsoluteKpa"] ?? observations["mapKpa"],
              let barometer = observations["barometricKpa"] else { return nil }
        let reference = date ?? max(pressure.timestamp, barometer.timestamp)
        guard abs(pressure.timestamp.timeIntervalSince(barometer.timestamp)) <= boostBarometerFreshness,
              reference.timeIntervalSince(pressure.timestamp) <= maximumSignalGap,
              reference.timeIntervalSince(barometer.timestamp) <= boostBarometerFreshness else { return nil }
        return DriveLineObservation(key: "boostKpa", value: pressure.value - barometer.value,
            timestamp: max(pressure.timestamp, barometer.timestamp), sourceID: pressure.sourceID,
            recordingID: pressure.recordingID)
    }

    public static func tankToTankEconomy(_ entries: [DriveLineFuelEntry], includeSamples: Bool = false) -> Double? {
        let sorted = entries.filter { includeSamples || !$0.isSample }.sorted { $0.odometerKm < $1.odometerKm }
        guard let end = sorted.lastIndex(where: \.isFullFill), end > 0,
              let start = sorted[..<end].lastIndex(where: \.isFullFill) else { return nil }
        let distance = sorted[end].odometerKm - sorted[start].odometerKm
        guard distance > 0 else { return nil }
        return sorted[(start + 1)...end].reduce(0) { $0 + $1.litresPurchased } * 100 / distance
    }

    public static func normalizedDPFRegenTrigger(_ value: Double) -> Double? {
        value.isFinite && (0...100).contains(value) ? value : nil
    }

    public static let dpfRegenTriggerLabel = "DPF regeneration trigger"
    public static let dpfRegenTriggerExplanation = "Normalized ECU trigger indicator; not physical DPF fullness."

    private static func observationCoverage(_ timestamps:[Date],maximumGap:TimeInterval) -> TimeInterval {
        zip(timestamps,timestamps.dropFirst()).reduce(0) { total,pair in
            let elapsed=pair.1.timeIntervalSince(pair.0)
            return total+(elapsed > 0 && elapsed <= maximumGap ? elapsed : 0)
        }
    }

    private static func accepts(_ point: DriveLineGPSPoint) -> Bool {
        point.isValid && (point.horizontalAccuracyM.map { $0 <= maximumHorizontalAccuracyM } ?? true)
    }

    private static func haversineMetres(_ a: DriveLineGPSPoint, _ b: DriveLineGPSPoint) -> Double {
        let radians = Double.pi / 180
        let lat1 = a.latitude * radians
        let lat2 = b.latitude * radians
        let deltaLatitude = (b.latitude - a.latitude) * radians
        let deltaLongitude = (b.longitude - a.longitude) * radians
        let h = pow(sin(deltaLatitude / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(deltaLongitude / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }
}
