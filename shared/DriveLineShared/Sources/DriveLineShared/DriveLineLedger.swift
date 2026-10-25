import Foundation

public enum DriveLineJourneyPurpose: String, Codable, CaseIterable, Identifiable, Sendable {
    case personal
    case business
    case commute
    case service
    case test
    case other

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Mutable user-owned information stored beside a recording. It is deliberately
/// excluded from archives and transfer payloads so preserved bytes and hashes do
/// not change when a journey is reviewed.
public struct DriveLineJourneyAnnotation: Codable, Equatable, Sendable {
    public var recordingID: UUID
    public var purpose: DriveLineJourneyPurpose?
    public var reviewed: Bool
    public var note: String?
    public var startPlace: String?
    public var finishPlace: String?
    public var updatedAt: Date

    public init(recordingID: UUID, purpose: DriveLineJourneyPurpose? = nil,
                reviewed: Bool = false, note: String? = nil,
                startPlace: String? = nil, finishPlace: String? = nil,
                updatedAt: Date = Date()) {
        self.recordingID = recordingID
        self.purpose = purpose
        self.reviewed = reviewed
        self.note = note
        self.startPlace = startPlace
        self.finishPlace = finishPlace
        self.updatedAt = updatedAt
    }
}

public enum DriveLineJourneyQuality: String, Codable, CaseIterable, Sendable {
    case complete
    case degraded
    case limited
    case unavailable

    public var title: String {
        switch self {
        case .complete: return "Complete coverage"
        case .degraded: return "Degraded intervals"
        case .limited: return "Limited sources"
        case .unavailable: return "No observations"
        }
    }
}

public struct DriveLineEvidenceInterval: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(sourceID)-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
    public var start: Date
    public var end: Date
    public var sourceID: String
    public var reason: String

    public init(start: Date, end: Date, sourceID: String, reason: String) {
        self.start = start
        self.end = end
        self.sourceID = sourceID
        self.reason = reason
    }
}

public struct DriveLineJourneySummary: Equatable, Sendable {
    public var recordingID: UUID
    public var metrics: DriveLineMetrics
    public var sourceKinds: [DriveLineSourceKind]
    public var gpsCoverage: Double?
    public var obdCoverage: Double?
    public var quality: DriveLineJourneyQuality
    public var gaps: [DriveLineEvidenceInterval]
    public var fuelSource: String?
    public var statement: String

    public init(recordingID: UUID, metrics: DriveLineMetrics,
                sourceKinds: [DriveLineSourceKind], gpsCoverage: Double?,
                obdCoverage: Double?, quality: DriveLineJourneyQuality,
                gaps: [DriveLineEvidenceInterval], fuelSource: String?, statement: String) {
        self.recordingID = recordingID
        self.metrics = metrics
        self.sourceKinds = sourceKinds
        self.gpsCoverage = gpsCoverage
        self.obdCoverage = obdCoverage
        self.quality = quality
        self.gaps = gaps
        self.fuelSource = fuelSource
        self.statement = statement
    }
}

public enum DriveLineSignalProvenance: String, Codable, Sendable {
    case measured
    case derived
}

public struct DriveLineSignalPoint: Equatable, Identifiable, Sendable {
    public var id: String { "\(timestamp.timeIntervalSince1970)-\(sourceID)" }
    public var timestamp: Date
    public var value: Double
    public var sourceID: String

    public init(timestamp: Date, value: Double, sourceID: String) {
        self.timestamp = timestamp
        self.value = value
        self.sourceID = sourceID
    }
}

public struct DriveLineSignalSeries: Equatable, Sendable {
    public var key: String
    public var unit: String
    public var provenance: DriveLineSignalProvenance
    public var algorithmIdentifier: String?
    public var segments: [[DriveLineSignalPoint]]
    public var coverage: DriveLineCoverageSummary?

    public init(key: String, unit: String, provenance: DriveLineSignalProvenance,
                algorithmIdentifier: String? = nil, segments: [[DriveLineSignalPoint]],
                coverage: DriveLineCoverageSummary?) {
        self.key = key
        self.unit = unit
        self.provenance = provenance
        self.algorithmIdentifier = algorithmIdentifier
        self.segments = segments
        self.coverage = coverage
    }
}

public struct DriveLineCursorSelection: Equatable, Sendable {
    public var timestamp: Date
    public var gpsPoint: DriveLineGPSPoint?
    public var observations: [String: DriveLineObservation]

    public init(timestamp: Date, gpsPoint: DriveLineGPSPoint?, observations: [String: DriveLineObservation]) {
        self.timestamp = timestamp
        self.gpsPoint = gpsPoint
        self.observations = observations
    }
}

public struct DriveLineFuelLedgerItem: Equatable, Identifiable, Sendable {
    public var id: UUID { entry.id }
    public var entry: DriveLineFuelEntry
    public var costPerLitre: Double?
    public var tankEconomyL100Km: Double?
    public var boundaryStartID: UUID?

    public init(entry: DriveLineFuelEntry, costPerLitre: Double?,
                tankEconomyL100Km: Double?, boundaryStartID: UUID?) {
        self.entry = entry
        self.costPerLitre = costPerLitre
        self.tankEconomyL100Km = tankEconomyL100Km
        self.boundaryStartID = boundaryStartID
    }
}

public struct DriveLineTripFuelPoint: Equatable, Identifiable, Sendable {
    public var id: UUID { recordingID }
    public var recordingID: UUID
    public var date: Date
    public var litres: Double
    public var economyL100Km: Double?
    public var source: String

    public init(recordingID: UUID, date: Date, litres: Double,
                economyL100Km: Double?, source: String) {
        self.recordingID = recordingID
        self.date = date
        self.litres = litres
        self.economyL100Km = economyL100Km
        self.source = source
    }
}

public enum DriveLineJourneyPolicy {
    public static let algorithmIdentifier = "driveline.evidence"
    public static let algorithmVersion = "1"

    public static func summary(for recording: DriveLineRecording,
                               sources: [DriveLineSourceDescriptor] = []) -> DriveLineJourneySummary {
        let metrics = DriveLineMetricPolicy.metrics(for: recording)
        let gps = metrics.coverage.first(where: { $0.key == "gps" })?.fraction
        let obd = coverage(timestamps: recording.signalSamples.map(\.timestamp),
                           duration: metrics.durationSeconds,
                           maximumGap: DriveLineMetricPolicy.maximumSignalGap)
        let sourceKinds = resolvedSourceKinds(recording: recording, sources: sources)
        let gaps = gapIntervals(recording)
        let quality: DriveLineJourneyQuality
        if recording.gpsPoints.isEmpty && recording.signalSamples.isEmpty { quality = .unavailable }
        else if !gaps.isEmpty || [gps, obd].compactMap({ $0 }).contains(where: { $0 < 0.8 }) { quality = .degraded }
        else if recording.gpsPoints.isEmpty || recording.signalSamples.isEmpty { quality = .limited }
        else { quality = .complete }

        let fuelCoverage = metrics.coverage.first(where: { $0.key == "fuelRateLph" })?.fraction
        let fuelSource: String?
        if metrics.tripFuelLitres == nil { fuelSource = nil }
        else if fuelCoverage.map({ $0 >= DriveLineMetricPolicy.requiredFuelCoverage }) == true { fuelSource = "Measured fuel rate" }
        else { fuelSource = "Recorded trip summary" }

        return DriveLineJourneySummary(recordingID: recording.recordingID, metrics: metrics,
            sourceKinds: sourceKinds, gpsCoverage: gps, obdCoverage: obd, quality: quality,
            gaps: gaps, fuelSource: fuelSource,
            statement: statement(gps: gps, obd: obd, gaps: gaps, fuelAvailable: metrics.tripFuelLitres != nil,
                                 fuelCoverage: fuelCoverage))
    }

    public static func timeline(for recording: DriveLineRecording) -> [DriveLineTripEvent] {
        var events = recording.events
        events.append(event(recording, key: "recording-started", timestamp: recording.startedAt,
                            kind: "recordingStarted", note: "Recording started", sourceID: nil))
        events.append(event(recording, key: "recording-finished", timestamp: recording.endedAt,
                            kind: "recordingFinished", note: "Recording finished", sourceID: nil))
        events += sourceTimeline(recording: recording, sourceID: "gps",
                                 timestamps: recording.gpsPoints.map(\.timestamp),
                                 maximumGap: DriveLineMetricPolicy.maximumGPSGap)
        events += sourceTimeline(recording: recording, sourceID: "obd",
                                 timestamps: recording.signalSamples.map(\.timestamp),
                                 maximumGap: DriveLineMetricPolicy.maximumSignalGap)

        if let fuel = DriveLineMetricPolicy.coverageSummaries(recording).first(where: { $0.key == "fuelRateLph" }),
           fuel.fraction < DriveLineMetricPolicy.requiredFuelCoverage {
            events.append(event(recording, key: "fuel-coverage", timestamp: fuel.lastObservation ?? recording.endedAt,
                kind: "qualityThresholdNotMet",
                note: "Trip fuel unavailable: measured fuel-rate coverage was \(percent(fuel.fraction)), below the 80% threshold.",
                sourceID: fuel.sourceIDs.first, severity: .attention,
                evidence: ["coverage:fuelRateLph", "threshold:0.8"]))
        }
        for (index, sample) in recording.signalSamples.enumerated() {
            guard let raw = sample.values["dpfRegenTrigger"],
                  let value = DriveLineMetricPolicy.normalizedDPFRegenTrigger(raw) else { continue }
            events.append(event(recording, key: "regen-\(index)", timestamp: sample.timestamp,
                kind: "dpfRegenTriggerObserved",
                note: "DPF regeneration trigger observed at \(value.formatted(.number.precision(.fractionLength(0))))%. This is a normalized ECU trigger, not physical DPF fullness.",
                sourceID: sample.sourceID, evidence: ["signal:dpfRegenTrigger", "sample:\(index)"]))
        }
        return events.sorted { $0.timestamp == $1.timestamp ? $0.kind < $1.kind : $0.timestamp < $1.timestamp }
    }

    public static func signalSeries(_ key: String, unit: String,
                                    recording: DriveLineRecording) -> DriveLineSignalSeries {
        let provenance: DriveLineSignalProvenance = key == "boostKpa" ? .derived : .measured
        let points: [DriveLineSignalPoint]
        if key == "boostKpa" {
            var observations: [String: DriveLineObservation] = [:]
            var result: [DriveLineSignalPoint] = []
            for sample in recording.signalSamples.sorted(by: { $0.timestamp < $1.timestamp }) {
                for (sampleKey, value) in sample.values {
                    observations[sampleKey] = DriveLineObservation(key: sampleKey, value: value,
                        timestamp: sample.timestamp, sourceID: sample.sourceID, recordingID: recording.recordingID)
                }
                if (sample.values["boostAbsoluteKpa"] ?? sample.values["mapKpa"]) != nil,
                   let boost = DriveLineMetricPolicy.boostGaugeKpa(observations: observations, at: sample.timestamp) {
                    result.append(DriveLineSignalPoint(timestamp: sample.timestamp, value: boost.value, sourceID: boost.sourceID))
                }
            }
            points = result
        } else {
            points = recording.signalSamples.compactMap { sample in
                sample.values[key].flatMap { raw in
                    let value=key == "dpfRegenTrigger" ? DriveLineMetricPolicy.normalizedDPFRegenTrigger(raw):raw
                    return value.map { DriveLineSignalPoint(timestamp:sample.timestamp,value:$0,sourceID:sample.sourceID) }
                }
            }.sorted { $0.timestamp < $1.timestamp }
        }
        let derivedCoverage:DriveLineCoverageSummary? = provenance == .derived ? DriveLineCoverageSummary(
            key:key,observedSeconds:observedSeconds(points.map(\.timestamp),maximumGap:DriveLineMetricPolicy.maximumSignalGap),
            recordingSeconds:max(0,recording.endedAt.timeIntervalSince(recording.startedAt)),
            fraction:coverage(timestamps:points.map(\.timestamp),duration:max(0,recording.endedAt.timeIntervalSince(recording.startedAt)),maximumGap:DriveLineMetricPolicy.maximumSignalGap) ?? 0,
            firstObservation:points.first?.timestamp,lastObservation:points.last?.timestamp,
            sourceIDs:Array(Set(points.map(\.sourceID))).sorted()):nil
        return DriveLineSignalSeries(key: key, unit: unit, provenance: provenance,
            algorithmIdentifier: provenance == .derived ? "driveline.boost-gauge.v1" : nil,
            segments: segments(points),
            coverage: derivedCoverage ?? DriveLineMetricPolicy.coverageSummaries(recording).first(where: { $0.key == key }))
    }

    public static func cursor(at timestamp: Date, recording: DriveLineRecording,
                              signalKeys: [String]) -> DriveLineCursorSelection {
        let gps = nearest(recording.gpsPoints, to: timestamp, maximumAge: DriveLineMetricPolicy.maximumGPSGap) { $0.timestamp }
        var observations: [String: DriveLineObservation] = [:]
        for key in signalKeys {
            let candidates = recording.signalSamples.compactMap { sample -> DriveLineObservation? in
                sample.values[key].map { DriveLineObservation(key: key, value: $0, timestamp: sample.timestamp,
                    sourceID: sample.sourceID, recordingID: recording.recordingID) }
            }
            if let value = nearest(candidates, to: timestamp, maximumAge: DriveLineMetricPolicy.maximumSignalGap, timestamp: { $0.timestamp }) {
                observations[key] = value
            }
        }
        return DriveLineCursorSelection(timestamp: timestamp, gpsPoint: gps, observations: observations)
    }

    public static func fuelLedger(_ entries: [DriveLineFuelEntry], includeSamples: Bool = false) -> [DriveLineFuelLedgerItem] {
        let sorted = entries.filter { includeSamples || !$0.isSample }.sorted { lhs, rhs in
            lhs.odometerKm == rhs.odometerKm ? lhs.date < rhs.date : lhs.odometerKm < rhs.odometerKm
        }
        var lastFullIndex: Int?
        return sorted.enumerated().map { index, entry in
            var economy: Double?
            var boundaryID: UUID?
            if entry.isFullFill, let start = lastFullIndex {
                let distance = entry.odometerKm - sorted[start].odometerKm
                if distance > 0 {
                    economy = sorted[(start + 1)...index].reduce(0) { $0 + $1.litresPurchased } * 100 / distance
                    boundaryID = sorted[start].id
                }
            }
            if entry.isFullFill { lastFullIndex = index }
            return DriveLineFuelLedgerItem(entry: entry,
                costPerLitre: entry.litresPurchased > 0 ? entry.totalCost / entry.litresPurchased : nil,
                tankEconomyL100Km: economy, boundaryStartID: boundaryID)
        }
    }

    public static func tripFuelSeries(_ recordings: [DriveLineRecording], includeSamples: Bool = false) -> [DriveLineTripFuelPoint] {
        recordings.filter { includeSamples || !$0.isSample }.compactMap { recording -> DriveLineTripFuelPoint? in
            let metrics = DriveLineMetricPolicy.metrics(for: recording)
            guard let litres = metrics.tripFuelLitres else { return nil }
            let hasMeasuredCoverage = (metrics.coverage.first(where: { $0.key == "fuelRateLph" })?.fraction ?? 0)
                >= DriveLineMetricPolicy.requiredFuelCoverage
            let source = hasMeasuredCoverage ? "Measured fuel rate" : "Recorded trip summary"
            return DriveLineTripFuelPoint(recordingID: recording.recordingID, date: recording.endedAt,
                                          litres: litres, economyL100Km: metrics.economyL100Km, source: source)
        }.sorted { $0.date < $1.date }
    }

    public static func gapIntervals(_ recording: DriveLineRecording) -> [DriveLineEvidenceInterval] {
        gaps(timestamps: recording.gpsPoints.map(\.timestamp), maximumGap: DriveLineMetricPolicy.maximumGPSGap,
             sourceID: "gps", reason: "GPS observation gap") +
        gaps(timestamps: recording.signalSamples.map(\.timestamp), maximumGap: DriveLineMetricPolicy.maximumSignalGap,
             sourceID: "obd", reason: "Scanner observation gap")
    }

    private static func resolvedSourceKinds(recording: DriveLineRecording,
                                            sources: [DriveLineSourceDescriptor]) -> [DriveLineSourceKind] {
        let descriptors = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.kind) })
        let result = recording.sourceIDs.map { id -> DriveLineSourceKind in
            if let kind = descriptors[id] { return kind }
            if id.lowercased().contains("gps") { return .gps }
            if id.lowercased().contains("obd") || id.lowercased().contains("scanner") { return .obd }
            return recording.isSample ? .synthetic : .imported
        }
        return Array(Set(result)).sorted { $0.rawValue < $1.rawValue }
    }

    private static func sourceTimeline(recording: DriveLineRecording, sourceID: String,
                                       timestamps: [Date], maximumGap: TimeInterval) -> [DriveLineTripEvent] {
        let sorted = Array(Set(timestamps)).sorted()
        guard let first = sorted.first else { return [] }
        var events = [event(recording, key: "\(sourceID)-began", timestamp: first,
                            kind: "\(sourceID)Began", note: "\(sourceID.uppercased()) observations began",
                            sourceID: sourceID)]
        for (index, pair) in zip(sorted, sorted.dropFirst()).enumerated() {
            guard pair.1.timeIntervalSince(pair.0) > maximumGap else { continue }
            events.append(event(recording, key: "\(sourceID)-lost-\(index)", timestamp: pair.0,
                endTimestamp: pair.1, kind: "\(sourceID)Lost",
                note: "\(sourceID.uppercased()) observations were unavailable for \(Int(pair.1.timeIntervalSince(pair.0))) seconds",
                sourceID: sourceID, severity: .attention,
                evidence: ["gap-start:\(pair.0.timeIntervalSince1970)", "gap-end:\(pair.1.timeIntervalSince1970)"]))
            events.append(event(recording, key: "\(sourceID)-recovered-\(index)", timestamp: pair.1,
                kind: "\(sourceID)Recovered", note: "\(sourceID.uppercased()) observations recovered",
                sourceID: sourceID))
        }
        return events
    }

    private static func event(_ recording: DriveLineRecording, key: String, timestamp: Date,
                              endTimestamp: Date? = nil, kind: String, note: String,
                              sourceID: String?, severity: DriveLineEventSeverity = .information,
                              evidence: [String] = []) -> DriveLineTripEvent {
        DriveLineTripEvent(id: stableUUID("\(recording.recordingID.uuidString)|\(key)"),
            timestamp: timestamp, endTimestamp: endTimestamp, kind: kind, note: note,
            sourceID: sourceID, severity: severity, confidence: 1,
            algorithmIdentifier: algorithmIdentifier, algorithmVersion: algorithmVersion,
            evidenceReferences: evidence)
    }

    private static func gaps(timestamps: [Date], maximumGap: TimeInterval,
                             sourceID: String, reason: String) -> [DriveLineEvidenceInterval] {
        let sorted = Array(Set(timestamps)).sorted()
        return zip(sorted, sorted.dropFirst()).compactMap { a, b in
            b.timeIntervalSince(a) > maximumGap ? DriveLineEvidenceInterval(start: a, end: b, sourceID: sourceID, reason: reason) : nil
        }
    }

    private static func segments(_ points: [DriveLineSignalPoint]) -> [[DriveLineSignalPoint]] {
        var result: [[DriveLineSignalPoint]] = []
        for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let previous = result.last?.last,
               point.timestamp.timeIntervalSince(previous.timestamp) <= DriveLineMetricPolicy.maximumSignalGap {
                result[result.count - 1].append(point)
            } else { result.append([point]) }
        }
        return result
    }

    private static func coverage(timestamps: [Date], duration: TimeInterval,
                                 maximumGap: TimeInterval) -> Double? {
        guard !timestamps.isEmpty, duration > 0 else { return nil }
        let sorted = Array(Set(timestamps)).sorted()
        let seconds = zip(sorted, sorted.dropFirst()).reduce(0.0) { total, pair in
            let gap = pair.1.timeIntervalSince(pair.0)
            return total + (gap > 0 && gap <= maximumGap ? gap : 0)
        }
        return min(1, seconds / duration)
    }

    private static func observedSeconds(_ timestamps:[Date],maximumGap:TimeInterval)->Double {
        let sorted=Array(Set(timestamps)).sorted()
        return zip(sorted,sorted.dropFirst()).reduce(0) { total,pair in
            let interval=pair.1.timeIntervalSince(pair.0)
            return total+(interval > 0 && interval <= maximumGap ? interval:0)
        }
    }

    private static func statement(gps: Double?, obd: Double?, gaps: [DriveLineEvidenceInterval],
                                  fuelAvailable: Bool, fuelCoverage: Double?) -> String {
        var parts: [String] = []
        if let obd { parts.append("Scanner telemetry covered \(percent(obd)) of this journey.") }
        else { parts.append("Scanner telemetry was unavailable for this journey.") }
        if let gps { parts.append("GPS covered \(percent(gps)) of this journey.") }
        else { parts.append("GPS route data was unavailable.") }
        if let longest = gaps.max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }) {
            parts.append("A \(Int(longest.end.timeIntervalSince(longest.start)))-second \(longest.sourceID.uppercased()) interruption is shown explicitly.")
        }
        if !fuelAvailable {
            if let fuelCoverage { parts.append("Trip fuel is unavailable because measured fuel-rate coverage was \(percent(fuelCoverage)), below the required 80% threshold.") }
            else { parts.append("Trip fuel is unavailable because no qualifying measured fuel-rate interval was recorded.") }
        }
        return parts.joined(separator: " ")
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func nearest<T>(_ values: [T], to date: Date, maximumAge: TimeInterval,
                                   timestamp: (T) -> Date) -> T? {
        guard let value = values.min(by: { abs(timestamp($0).timeIntervalSince(date)) < abs(timestamp($1).timeIntervalSince(date)) }),
              abs(timestamp(value).timeIntervalSince(date)) <= maximumAge else { return nil }
        return value
    }

    private static func stableUUID(_ value: String) -> UUID {
        func hash(seed: UInt64) -> UInt64 {
            value.utf8.reduce(seed) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }
        let a = hash(seed: 14_695_981_039_346_656_037)
        let b = hash(seed: 10_995_116_282_11)
        let hex = String(format: "%016llx%016llx", a, b)
        let uuid = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(13).prefix(3))-8\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: uuid)!
    }
}
