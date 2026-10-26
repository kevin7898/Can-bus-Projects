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
    public var distanceCandidates: [DriveLineDistanceCandidate] = []
    public var distanceIsPartial = false
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
    public static let version = "driveline.metrics.v2"
    public static let comparableDistanceCoverage = 0.05
    public static let adequateDistanceCoverage = 0.95
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
            let candidates = distanceCandidates(for:recording)
            let selected = selectDistance(candidates)
            let distance = selected?.distanceKm ?? recording.recordedDistanceKm
            let boundedSamples = recording.signalSamples.filter { $0.timestamp >= recording.startedAt && $0.timestamp <= recording.endedAt }
            let fuel = integral("fuelRateLph", samples: boundedSamples)
            let measuredFuel = fuel.flatMap { duration > 0 && $0.coverage / duration >= requiredFuelCoverage ? $0.value / 3600 : nil }
            let tripFuel = measuredFuel ?? recording.tripFuelLitres
            let economy: Double? = distance.flatMap { km -> Double? in
                // Whole-trip economy requires matching complete intervals, not
                // unrelated partial fuel and distance totals above a threshold.
                guard km > 0.1, let tripFuel, let selected,
                      let fuel, duration > 0, fuel.coverage >= duration - 0.001,
                      selected.coveredSeconds >= duration - 0.001 else { return nil }
                return tripFuel / km * 100
            }
            var metrics = DriveLineMetrics(distanceKm: distance, durationSeconds: duration,
                tripFuelLitres: tripFuel, economyL100Km: economy,
                coverage: coverageSummaries(recording),
                distanceSource:selected?.sourceID ?? (recording.recordedDistanceKm != nil ? "recorded" : nil))
            metrics.distanceCandidates = candidates
            metrics.distanceIsPartial = selected.map { $0.coverageFraction < adequateDistanceCoverage } ?? (distance != nil)
            return metrics
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
                    result[result.count - 1].append(point)
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
                let movement = haversineMetres(a, b)
                metres += movement >= minimumGPSMovementM ? movement : 0
                intervals += 1
            }
        }
        return intervals > 0 ? metres / 1000 : nil
    }

    public static func integral(_ key: String, samples: [DriveLineSignalSample]) -> (value: Double, coverage: Double)? {
        // Never integrate across different controllers. Choose one source's
        // evidence rather than alternating or adding overlapping ECU values.
        let groups = Dictionary(grouping:samples,by:\.sourceID)
        if groups.count > 1 {
            return groups.keys.sorted().compactMap { integral(key,samples:groups[$0]!) }
                .max { $0.coverage < $1.coverage }
        }
        let values = samples.compactMap { sample -> (Date, Double)? in
            guard let value=sample.values[key],value.isFinite else { return nil }
            return (sample.timestamp,value)
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
            let observations = recording.signalSamples.filter {
                $0.values[key]?.isFinite == true && $0.timestamp >= recording.startedAt && $0.timestamp <= recording.endedAt
            }.sorted { $0.timestamp < $1.timestamp }
            let observed = DriveLineAcquisitionPolicy.availabilitySeconds(timestamps:observations.map(\.timestamp),key:key,
                start:recording.startedAt,end:recording.endedAt)
            result.append(DriveLineCoverageSummary(key: key, observedSeconds: observed, recordingSeconds: duration,
                fraction: duration > 0 ? min(1, observed / duration) : 0,
                firstObservation: observations.first?.timestamp, lastObservation: observations.last?.timestamp,
                sourceIDs: Array(Set(observations.map(\.sourceID))).sorted()))
            let index=result.count-1
            result[index].observationCount=observations.count
            if observations.count > 1 {
                result[index].achievedCadenceSeconds=observations.last!.timestamp.timeIntervalSince(observations.first!.timestamp)/Double(observations.count-1)
            }
            result[index].expectedCadenceSeconds=DriveLineAcquisitionPolicy.signal(key).expectedCadence
            result[index].integrationSeconds=integral(key,samples:observations)?.coverage
            result[index].policyVersion=DriveLineAcquisitionPolicy.version
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
        guard let barometer = observations["barometricKpa"], barometer.value.isFinite else { return nil }
        for key in ["boostAbsoluteKpa", "mapKpa"] {
            guard let pressure = observations[key], pressure.value.isFinite,
                  pressure.recordingID == barometer.recordingID else { continue }
            // Importers may use separate labels for atmospheric sensors. Only
            // reject conflicting explicit ECU identity, not different labels.
            let ecuIDs = ["7E8", "7E9", "7EA", "7EB", "7EC", "7ED", "7EE", "7EF"]
            let pressureECU = ecuIDs.first { pressure.sourceID.uppercased().contains($0) }
            let barometerECU = ecuIDs.first { barometer.sourceID.uppercased().contains($0) }
            if let pressureECU, let barometerECU, pressureECU != barometerECU { continue }
            let reference = date ?? max(pressure.timestamp, barometer.timestamp)
            guard (0...maximumSignalGap).contains(reference.timeIntervalSince(pressure.timestamp)),
                  (0...boostBarometerFreshness).contains(reference.timeIntervalSince(barometer.timestamp)) else { continue }
            return DriveLineObservation(key: "boostKpa", value: pressure.value - barometer.value,
                timestamp: min(pressure.timestamp, barometer.timestamp), sourceID: pressure.sourceID,
                recordingID: pressure.recordingID)
        }
        return nil
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
