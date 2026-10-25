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
    public var algorithmVersion: String?
    public var segments: [[DriveLineSignalPoint]]
    public var coverage: DriveLineCoverageSummary?

    public init(key: String, unit: String, provenance: DriveLineSignalProvenance,
                algorithmIdentifier: String? = nil, algorithmVersion: String? = nil,
                segments: [[DriveLineSignalPoint]],
                coverage: DriveLineCoverageSummary?) {
        self.key = key
        self.unit = unit
        self.provenance = provenance
        self.algorithmIdentifier = algorithmIdentifier
        self.algorithmVersion = algorithmVersion
        self.segments = segments
        self.coverage = coverage
    }
}

public enum DriveLineSignalGroup: String, CaseIterable, Codable, Identifiable, Sendable {
    case driving
    case engine
    case temperatures
    case fuelEconomy
    case pressureBoost
    case emissionsDPF
    case transmission
    case electrical
    case gpsMotion
    case rawDiagnostic
    case otherUnknown

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .driving: return "Driving"
        case .engine: return "Engine"
        case .temperatures: return "Temperatures"
        case .fuelEconomy: return "Fuel and economy"
        case .pressureBoost: return "Pressure and boost"
        case .emissionsDPF: return "Emissions and DPF"
        case .transmission: return "Transmission"
        case .electrical: return "Electrical"
        case .gpsMotion: return "GPS and motion"
        case .rawDiagnostic: return "Raw/diagnostic"
        case .otherUnknown: return "Other or unknown"
        }
    }
}

public struct DriveLineSignalDescriptor: Equatable, Identifiable, Sendable {
    public var id: String { key }
    public var key: String
    public var displayName: String
    public var unit: String?
    public var aliases: [String]
    public var group: DriveLineSignalGroup
    public var provenance: DriveLineSignalProvenance
    public var algorithmIdentifier: String?
    public var algorithmVersion: String?
    public var sourceIDs: [String]
    public var metadataAvailable: Bool

    public init(key: String, displayName: String, unit: String?, aliases: [String],
                group: DriveLineSignalGroup, provenance: DriveLineSignalProvenance = .measured,
                algorithmIdentifier: String? = nil, algorithmVersion: String? = nil,
                sourceIDs: [String] = [], metadataAvailable: Bool = true) {
        self.key = key
        self.displayName = displayName
        self.unit = unit
        self.aliases = aliases
        self.group = group
        self.provenance = provenance
        self.algorithmIdentifier = algorithmIdentifier
        self.algorithmVersion = algorithmVersion
        self.sourceIDs = sourceIDs
        self.metadataAvailable = metadataAvailable
    }
}

public enum DriveLineSignalFreshness: String, Codable, Sendable {
    case fresh
    case stale
    case unavailable

    public var title: String {
        switch self {
        case .fresh: return "Fresh at cursor"
        case .stale: return "Stale at cursor"
        case .unavailable: return "Unavailable at cursor"
        }
    }
}

public struct DriveLineSignalStatistics: Equatable, Sendable {
    public var current: DriveLineSignalPoint?
    public var freshness: DriveLineSignalFreshness
    public var minimum: Double?
    public var maximum: Double?
    public var recordedObservationAverage: Double?
    public var observationCount: Int
    public var latestObservation: Date?
    public var sourceIDs: [String]

    public init(current: DriveLineSignalPoint?, freshness: DriveLineSignalFreshness,
                minimum: Double?, maximum: Double?, recordedObservationAverage: Double?,
                observationCount: Int, latestObservation: Date?, sourceIDs: [String]) {
        self.current = current
        self.freshness = freshness
        self.minimum = minimum
        self.maximum = maximum
        self.recordedObservationAverage = recordedObservationAverage
        self.observationCount = observationCount
        self.latestObservation = latestObservation
        self.sourceIDs = sourceIDs
    }
}

public enum DriveLineSignalAlignment: String, CaseIterable, Codable, Identifiable, Sendable {
    case elapsedTime
    case travelledDistance

    public var id: String { rawValue }
    public var title: String { self == .elapsedTime ? "Elapsed time" : "Travelled distance" }
}

public struct DriveLineAlignmentAvailability: Equatable, Sendable {
    public var isAvailable: Bool
    public var explanation: String

    public init(isAvailable: Bool, explanation: String) {
        self.isAvailable = isAvailable
        self.explanation = explanation
    }
}

public struct DriveLineAlignedSignalPoint: Equatable, Identifiable, Sendable {
    public var id: String { "\(point.id)-\(position)" }
    public var position: Double
    public var point: DriveLineSignalPoint

    public init(position: Double, point: DriveLineSignalPoint) {
        self.position = position
        self.point = point
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
    /// Identifies deterministic Phase 4 evidence derivations without changing preserved recordings.
    public static let algorithmIdentifier = "driveline.evidence"
    public static let algorithmVersion = "1"
    public static let boostAlgorithmIdentifier = "driveline.boost-gauge.v1"
    public static let boostAlgorithmVersion = "1"
    public static let requiredDistanceAlignmentCoverage = 0.5

    private static let knownSignals: [String: DriveLineSignalDescriptor] = {
        let values: [DriveLineSignalDescriptor] = [
            .init(key:"speedKph",displayName:"Vehicle speed",unit:"km/h",aliases:["speed","road speed"],group:.driving),
            .init(key:"rpm",displayName:"Engine speed",unit:"rpm",aliases:["revolutions","tachometer"],group:.engine),
            .init(key:"engineLoad",displayName:"Engine load",unit:"%",aliases:["load"],group:.engine),
            .init(key:"mafGps",displayName:"Mass airflow",unit:"g/s",aliases:["MAF","air flow"],group:.engine),
            .init(key:"coolantC",displayName:"Coolant temperature",unit:"°C",aliases:["coolant"],group:.temperatures),
            .init(key:"intakeC",displayName:"Intake temperature",unit:"°C",aliases:["IAT"],group:.temperatures),
            .init(key:"oilC",displayName:"Oil temperature",unit:"°C",aliases:["engine oil"],group:.temperatures),
            .init(key:"outsideC",displayName:"Outside temperature",unit:"°C",aliases:["ambient temperature"],group:.temperatures),
            .init(key:"egt1C",displayName:"Exhaust temperature 1",unit:"°C",aliases:["EGT 1"],group:.temperatures),
            .init(key:"egt2C",displayName:"Exhaust temperature 2",unit:"°C",aliases:["EGT 2"],group:.temperatures),
            .init(key:"egt3C",displayName:"Exhaust temperature 3",unit:"°C",aliases:["EGT 3"],group:.temperatures),
            .init(key:"egt4C",displayName:"Exhaust temperature 4",unit:"°C",aliases:["EGT 4"],group:.temperatures),
            .init(key:"fuelRateLph",displayName:"Fuel rate",unit:"L/h",aliases:["fuel flow"],group:.fuelEconomy),
            .init(key:"fuelPercent",displayName:"Fuel level",unit:"%",aliases:["tank level"],group:.fuelEconomy),
            .init(key:"boostKpa",displayName:"Gauge boost",unit:"kPa gauge",aliases:["boost","relative boost"],group:.pressureBoost,
                  provenance:.derived,algorithmIdentifier:boostAlgorithmIdentifier,algorithmVersion:boostAlgorithmVersion),
            .init(key:"mapKpa",displayName:"Manifold absolute pressure",unit:"kPa absolute",aliases:["MAP"],group:.pressureBoost),
            .init(key:"barometricKpa",displayName:"Barometric pressure",unit:"kPa absolute",aliases:["BARO","ambient pressure"],group:.pressureBoost),
            .init(key:"boostAbsoluteKpa",displayName:"Boost pressure A",unit:"kPa absolute",aliases:["absolute boost"],group:.pressureBoost),
            .init(key:"boostCommandedKpa",displayName:"Commanded boost A",unit:"kPa absolute",aliases:["requested boost"],group:.pressureBoost),
            .init(key:"boostBAbsoluteKpa",displayName:"Boost pressure B",unit:"kPa absolute",aliases:["absolute boost B"],group:.pressureBoost),
            .init(key:"boostBCommandedKpa",displayName:"Commanded boost B",unit:"kPa absolute",aliases:["requested boost B"],group:.pressureBoost),
            .init(key:"dpfDifferentialKpa",displayName:"DPF differential pressure",unit:"kPa",aliases:["DPF delta pressure"],group:.emissionsDPF),
            .init(key:"dpfInletKpa",displayName:"DPF inlet pressure",unit:"kPa",aliases:[],group:.emissionsDPF),
            .init(key:"dpfOutletKpa",displayName:"DPF outlet pressure",unit:"kPa",aliases:[],group:.emissionsDPF),
            .init(key:"dpfRegenActive",displayName:"DPF regeneration active",unit:"state",aliases:["regen active"],group:.emissionsDPF),
            .init(key:"dpfRegenType",displayName:"DPF regeneration type",unit:"state",aliases:["regen type"],group:.emissionsDPF),
            .init(key:"dpfRegenTrigger",displayName:"DPF regeneration trigger · normalized",unit:"%",aliases:["regen trigger","ECU trigger"],group:.emissionsDPF),
            .init(key:"dpfAverageRegenMinutes",displayName:"Average regeneration interval",unit:"min",aliases:[],group:.emissionsDPF),
            .init(key:"dpfAverageRegenKM",displayName:"Average regeneration distance",unit:"km",aliases:[],group:.emissionsDPF),
            .init(key:"dpfAshML",displayName:"DPF ash volume",unit:"mL",aliases:["ash volume"],group:.emissionsDPF),
            .init(key:"dpfSootG",displayName:"DPF soot mass",unit:"g",aliases:["soot mass"],group:.emissionsDPF),
            .init(key:"dsgFluidC",displayName:"DSG fluid temperature",unit:"°C",aliases:["transmission temperature"],group:.transmission),
            .init(key:"voltage",displayName:"Battery voltage",unit:"V",aliases:["system voltage"],group:.electrical),
            .init(key:"gps.speedKph",displayName:"GPS speed",unit:"km/h",aliases:["location speed"],group:.gpsMotion),
            .init(key:"gps.horizontalAccuracyM",displayName:"GPS horizontal accuracy",unit:"m",aliases:["location accuracy"],group:.gpsMotion)
        ]
        return Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0) })
    }()

    public static func signalDescriptor(_ key: String, recording: DriveLineRecording) -> DriveLineSignalDescriptor {
        let sourceIDs = sourceIDs(for:key,recording:recording)
        if var known = knownSignals[key] {
            known.sourceIDs = sourceIDs
            return known
        }
        return DriveLineSignalDescriptor(key:key,displayName:key,unit:nil,aliases:[],group:.otherUnknown,
                                         sourceIDs:sourceIDs,metadataAvailable:false)
    }

    public static func signalDescriptors(recording: DriveLineRecording, query: String = "",
                                         includeUnobservedKnown: Bool = false) -> [DriveLineSignalDescriptor] {
        var keys = Set(recording.signalSamples.flatMap { $0.values.keys })
        if recording.gpsPoints.contains(where:{ $0.speedMps?.isFinite == true }) { keys.insert("gps.speedKph") }
        if recording.gpsPoints.contains(where:{ $0.horizontalAccuracyM?.isFinite == true }) { keys.insert("gps.horizontalAccuracyM") }
        if includeUnobservedKnown { keys.formUnion(knownSignals.keys) }
        if !signalSeries("boostKpa",unit:knownSignals["boostKpa"]?.unit ?? "",recording:recording).segments.isEmpty {
            keys.insert("boostKpa")
        }
        let needle = query.trimmingCharacters(in:.whitespacesAndNewlines).folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current)
        return keys.map { signalDescriptor($0,recording:recording) }.filter { descriptor in
            guard !needle.isEmpty else { return true }
            let values = [descriptor.displayName,descriptor.key,descriptor.unit ?? ""] + descriptor.aliases + descriptor.sourceIDs
            return values.contains { $0.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current).contains(needle) }
        }.sorted {
            let left = DriveLineSignalGroup.allCases.firstIndex(of:$0.group) ?? .max
            let right = DriveLineSignalGroup.allCases.firstIndex(of:$1.group) ?? .max
            return left == right ? ($0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending) : left < right
        }
    }

    public static func groupedSignalDescriptors(recording: DriveLineRecording, query: String = "",
                                                includeUnobservedKnown: Bool = false) -> [(DriveLineSignalGroup,[DriveLineSignalDescriptor])] {
        let grouped = Dictionary(grouping:signalDescriptors(recording:recording,query:query,
                                                             includeUnobservedKnown:includeUnobservedKnown),by:\.group)
        return DriveLineSignalGroup.allCases.compactMap { group in
            guard let values=grouped[group],!values.isEmpty else { return nil }
            return (group,values)
        }
    }

    public static func signalStatistics(_ series: DriveLineSignalSeries, at cursor: Date,
                                        visibleRange: DateInterval? = nil) -> DriveLineSignalStatistics {
        let allPoints=series.segments.flatMap{$0}.filter{$0.value.isFinite}.sorted{$0.timestamp < $1.timestamp}
        let points = allPoints.filter { point in
            point.value.isFinite && (visibleRange.map { point.timestamp >= $0.start && point.timestamp <= $0.end } ?? true)
        }.sorted { $0.timestamp < $1.timestamp }
        var result=statistics(points:points,cursor:cursor,maximumAge:series.key.hasPrefix("gps.") ? DriveLineMetricPolicy.maximumGPSGap:DriveLineMetricPolicy.maximumSignalGap)
        result.latestObservation=allPoints.last?.timestamp
        result.sourceIDs=Array(Set(allPoints.map(\.sourceID))).sorted()
        return result
    }

    public static func signalStatistics(_ series: DriveLineSignalSeries, recording: DriveLineRecording,
                                        alignment: DriveLineSignalAlignment, visibleRange: ClosedRange<Double>,
                                        at cursor: Date) -> DriveLineSignalStatistics {
        let allPoints=series.segments.flatMap{$0}.filter{$0.value.isFinite}.sorted{$0.timestamp < $1.timestamp}
        let points = alignedSegments(series,recording:recording,alignment:alignment).flatMap { $0 }
            .filter { visibleRange.contains($0.position) }.map(\.point)
        var result=statistics(points:points,cursor:cursor,maximumAge:series.key.hasPrefix("gps.") ? DriveLineMetricPolicy.maximumGPSGap:DriveLineMetricPolicy.maximumSignalGap)
        result.latestObservation=allPoints.last?.timestamp
        result.sourceIDs=Array(Set(allPoints.map(\.sourceID))).sorted()
        return result
    }

    public static func distanceAlignmentAvailability(_ recording: DriveLineRecording) -> DriveLineAlignmentAvailability {
        guard !recording.gpsPoints.isEmpty else {
            return DriveLineAlignmentAvailability(isAvailable:false,
                explanation:"Travelled-distance alignment is unavailable because this recording has no GPS observations.")
        }
        let progress = routeProgress(recording)
        guard progress.count >= 2, (progress.last?.distanceKm ?? 0) > 0 else {
            return DriveLineAlignmentAvailability(isAvailable:false,
                explanation:"Travelled-distance alignment is unavailable because the recorded GPS points do not establish route progress.")
        }
        let coverage = DriveLineMetricPolicy.coverageSummaries(recording).first(where:{$0.key == "gps"})?.fraction ?? 0
        guard coverage >= requiredDistanceAlignmentCoverage else {
            return DriveLineAlignmentAvailability(isAvailable:false,
                explanation:"Travelled-distance alignment needs at least 50% recorded GPS coverage; this recording has \(Int((coverage*100).rounded()))%.")
        }
        return DriveLineAlignmentAvailability(isAvailable:true,
            explanation:"Aligned to cumulative progress from recorded GPS segments; gaps add no inferred distance.")
    }

    public static func alignmentExtent(_ recording: DriveLineRecording,
                                       alignment: DriveLineSignalAlignment) -> ClosedRange<Double>? {
        switch alignment {
        case .elapsedTime:
            return 0...max(0,recording.endedAt.timeIntervalSince(recording.startedAt))
        case .travelledDistance:
            guard distanceAlignmentAvailability(recording).isAvailable,
                  let end=routeProgress(recording).last?.distanceKm else { return nil }
            return 0...end
        }
    }

    public static func alignedSegments(_ series: DriveLineSignalSeries, recording: DriveLineRecording,
                                       alignment: DriveLineSignalAlignment) -> [[DriveLineAlignedSignalPoint]] {
        switch alignment {
        case .elapsedTime:
            return series.segments.map { segment in
                segment.map { DriveLineAlignedSignalPoint(position:max(0,$0.timestamp.timeIntervalSince(recording.startedAt)),point:$0) }
            }.filter { !$0.isEmpty }
        case .travelledDistance:
            guard distanceAlignmentAvailability(recording).isAvailable else { return [] }
            let progress=routeProgress(recording)
            var output:[[DriveLineAlignedSignalPoint]]=[]
            for signalSegment in series.segments {
                var current:[DriveLineAlignedSignalPoint]=[]
                for point in signalSegment {
                    guard let nearest=progress.min(by:{abs($0.timestamp.timeIntervalSince(point.timestamp)) < abs($1.timestamp.timeIntervalSince(point.timestamp))}),
                          abs(nearest.timestamp.timeIntervalSince(point.timestamp)) <= DriveLineMetricPolicy.maximumGPSGap else {
                        if !current.isEmpty { output.append(current);current=[] }
                        continue
                    }
                    current.append(DriveLineAlignedSignalPoint(position:nearest.distanceKm,point:point))
                }
                if !current.isEmpty { output.append(current) }
            }
            return output
        }
    }

    public static func timestamp(at position: Double, recording: DriveLineRecording,
                                 alignment: DriveLineSignalAlignment) -> Date? {
        switch alignment {
        case .elapsedTime:
            guard let extent=alignmentExtent(recording,alignment:alignment) else { return nil }
            return recording.startedAt.addingTimeInterval(min(max(position,extent.lowerBound),extent.upperBound))
        case .travelledDistance:
            guard distanceAlignmentAvailability(recording).isAvailable else { return nil }
            return routeProgress(recording).min(by:{abs($0.distanceKm-position)<abs($1.distanceKm-position)})?.timestamp
        }
    }

    public static func position(at timestamp: Date, recording: DriveLineRecording,
                                alignment: DriveLineSignalAlignment) -> Double? {
        switch alignment {
        case .elapsedTime:
            guard let extent=alignmentExtent(recording,alignment:alignment) else { return nil }
            return min(max(timestamp.timeIntervalSince(recording.startedAt),extent.lowerBound),extent.upperBound)
        case .travelledDistance:
            guard distanceAlignmentAvailability(recording).isAvailable else { return nil }
            return routeProgress(recording).min(by:{abs($0.timestamp.timeIntervalSince(timestamp)) < abs($1.timestamp.timeIntervalSince(timestamp))})?.distanceKm
        }
    }

    public static func comparisonIneligibility(primary: DriveLineRecording,
                                                candidate: DriveLineRecording) -> String? {
        if primary.recordingID == candidate.recordingID { return "Choose another recording." }
        if primary.vehicleID != candidate.vehicleID { return "Comparison is limited to recordings from the same vehicle." }
        return nil
    }

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
        if key == "gps.speedKph" {
            points = recording.gpsPoints.compactMap { point in
                guard let speed=point.speedMps,speed.isFinite else { return nil }
                return DriveLineSignalPoint(timestamp:point.timestamp,value:speed*3.6,sourceID:point.sourceID)
            }.sorted { $0.timestamp < $1.timestamp }
        } else if key == "gps.horizontalAccuracyM" {
            points = recording.gpsPoints.compactMap { point in
                guard let accuracy=point.horizontalAccuracyM,accuracy.isFinite else { return nil }
                return DriveLineSignalPoint(timestamp:point.timestamp,value:accuracy,sourceID:point.sourceID)
            }.sorted { $0.timestamp < $1.timestamp }
        } else if key == "boostKpa" {
            var observations: [String: DriveLineObservation] = [:]
            var result: [DriveLineSignalPoint] = []
            for sample in recording.signalSamples.sorted(by: { $0.timestamp < $1.timestamp }) {
                for (sampleKey, value) in sample.values where value.isFinite {
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
                    guard raw.isFinite else { return nil }
                    let value=key == "dpfRegenTrigger" ? DriveLineMetricPolicy.normalizedDPFRegenTrigger(raw):raw
                    return value.map { DriveLineSignalPoint(timestamp:sample.timestamp,value:$0,sourceID:sample.sourceID) }
                }
            }.sorted { $0.timestamp < $1.timestamp }
        }
        let maximumGap = key.hasPrefix("gps.") ? DriveLineMetricPolicy.maximumGPSGap : DriveLineMetricPolicy.maximumSignalGap
        let calculatedCoverage:DriveLineCoverageSummary? = (provenance == .derived || key.hasPrefix("gps.")) ? DriveLineCoverageSummary(
            key:key,observedSeconds:observedSeconds(points.map(\.timestamp),maximumGap:maximumGap),
            recordingSeconds:max(0,recording.endedAt.timeIntervalSince(recording.startedAt)),
            fraction:coverage(timestamps:points.map(\.timestamp),duration:max(0,recording.endedAt.timeIntervalSince(recording.startedAt)),maximumGap:maximumGap) ?? 0,
            firstObservation:points.first?.timestamp,lastObservation:points.last?.timestamp,
            sourceIDs:Array(Set(points.map(\.sourceID))).sorted()):nil
        return DriveLineSignalSeries(key: key, unit: unit, provenance: provenance,
            algorithmIdentifier: provenance == .derived ? boostAlgorithmIdentifier : nil,
            algorithmVersion: provenance == .derived ? boostAlgorithmVersion : nil,
            segments: segments(points,maximumGap:maximumGap),
            coverage: calculatedCoverage ?? DriveLineMetricPolicy.coverageSummaries(recording).first(where: { $0.key == key }))
    }

    public static func cursor(at timestamp: Date, recording: DriveLineRecording,
                              signalKeys: [String]) -> DriveLineCursorSelection {
        let gps = nearest(recording.gpsPoints, to: timestamp, maximumAge: DriveLineMetricPolicy.maximumGPSGap) { $0.timestamp }
        var observations: [String: DriveLineObservation] = [:]
        for key in signalKeys {
            let candidates=signalSeries(key,unit:knownSignals[key]?.unit ?? "",recording:recording).segments.flatMap{$0}
            if let point=nearest(candidates,to:timestamp,maximumAge:DriveLineMetricPolicy.maximumSignalGap,timestamp:{ $0.timestamp }) {
                observations[key]=DriveLineObservation(key:key,value:point.value,timestamp:point.timestamp,
                                                       sourceID:point.sourceID,recordingID:recording.recordingID)
            }
        }
        return DriveLineCursorSelection(timestamp: timestamp, gpsPoint: gps, observations: observations)
    }

    public static func fuelLedger(_ entries: [DriveLineFuelEntry], includeSamples: Bool = false) -> [DriveLineFuelLedgerItem] {
        let included=entries.filter { includeSamples || !$0.isSample }
        var result:[UUID:DriveLineFuelLedgerItem]=[:]
        for vehicleEntries in Dictionary(grouping:included,by:\.vehicleID).values {
            let sorted=vehicleEntries.sorted { lhs,rhs in lhs.odometerKm == rhs.odometerKm ? lhs.date < rhs.date:lhs.odometerKm < rhs.odometerKm }
            var lastFullIndex:Int?
            for (index,entry) in sorted.enumerated() {
                var economy:Double?
                var boundaryID:UUID?
                if entry.isFullFill,let start=lastFullIndex {
                    let distance=entry.odometerKm-sorted[start].odometerKm
                    if distance>0 {
                        economy=sorted[(start+1)...index].reduce(0) { $0+$1.litresPurchased }*100/distance
                        boundaryID=sorted[start].id
                    }
                }
                if entry.isFullFill { lastFullIndex=index }
                result[entry.id]=DriveLineFuelLedgerItem(entry:entry,
                    costPerLitre:entry.litresPurchased>0 ? entry.totalCost/entry.litresPurchased:nil,
                    tankEconomyL100Km:economy,boundaryStartID:boundaryID)
            }
        }
        return included.sorted { $0.date<$1.date }.compactMap { result[$0.id] }
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

    private static func segments(_ points: [DriveLineSignalPoint],maximumGap:TimeInterval) -> [[DriveLineSignalPoint]] {
        var result: [[DriveLineSignalPoint]] = []
        for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let previous = result.last?.last,
               point.timestamp.timeIntervalSince(previous.timestamp) <= maximumGap {
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

    private struct RouteProgressPoint {
        var timestamp:Date
        var distanceKm:Double
    }

    private static func routeProgress(_ recording:DriveLineRecording)->[RouteProgressPoint] {
        var distance=0.0
        var result:[RouteProgressPoint]=[]
        for segment in DriveLineMetricPolicy.routeSegments(recording.gpsPoints) {
            guard let first=segment.first else { continue }
            result.append(RouteProgressPoint(timestamp:first.timestamp,distanceKm:distance))
            for (a,b) in zip(segment,segment.dropFirst()) {
                distance += DriveLineMetricPolicy.distanceFromGPS([a,b]) ?? 0
                result.append(RouteProgressPoint(timestamp:b.timestamp,distanceKm:distance))
            }
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    private static func sourceIDs(for key:String,recording:DriveLineRecording)->[String] {
        if key == "gps.speedKph" {
            return Array(Set(recording.gpsPoints.filter{$0.speedMps?.isFinite == true}.map(\.sourceID))).sorted()
        }
        if key == "gps.horizontalAccuracyM" {
            return Array(Set(recording.gpsPoints.filter{$0.horizontalAccuracyM?.isFinite == true}.map(\.sourceID))).sorted()
        }
        if key == "boostKpa" {
            return Array(Set(signalSeries(key,unit:knownSignals[key]?.unit ?? "",recording:recording)
                .segments.flatMap{$0}.map(\.sourceID))).sorted()
        }
        return Array(Set(recording.signalSamples.filter{$0.values[key]?.isFinite == true}.map(\.sourceID))).sorted()
    }

    private static func statistics(points:[DriveLineSignalPoint],cursor:Date,maximumAge:TimeInterval)->DriveLineSignalStatistics {
        let finite=points.filter{$0.value.isFinite}.sorted{$0.timestamp < $1.timestamp}
        guard !finite.isEmpty else {
            return DriveLineSignalStatistics(current:nil,freshness:.unavailable,minimum:nil,maximum:nil,
                recordedObservationAverage:nil,observationCount:0,latestObservation:nil,sourceIDs:[])
        }
        let latestAtCursor=finite.last(where:{$0.timestamp <= cursor})
        let current=latestAtCursor.flatMap { cursor.timeIntervalSince($0.timestamp) <= maximumAge ? $0:nil }
        let average=finite.reduce(0) { $0+$1.value }/Double(finite.count)
        let freshness:DriveLineSignalFreshness = current != nil ? .fresh:(latestAtCursor == nil ? .unavailable:.stale)
        return DriveLineSignalStatistics(current:current,freshness:freshness,
            minimum:finite.map(\.value).min(),maximum:finite.map(\.value).max(),recordedObservationAverage:average,
            observationCount:finite.count,latestObservation:finite.last?.timestamp,
            sourceIDs:Array(Set(finite.map(\.sourceID))).sorted())
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
        guard let value = values.filter({ timestamp($0) <= date }).max(by:{timestamp($0) < timestamp($1)}),
              date.timeIntervalSince(timestamp(value)) <= maximumAge else { return nil }
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
