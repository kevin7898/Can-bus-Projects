import Foundation

struct TripStorySnapshotKey: Hashable, Sendable {
    let recordingID: UUID
    let contentFingerprint: UInt64
}

struct TripStorySignalSnapshot: Sendable {
    let series: DriveLineSignalSeries
    let renderedSegments: [[DriveLineSignalPoint]]
}

struct TripStorySnapshot: Sendable {
    let key: TripStorySnapshotKey
    let summary: DriveLineJourneySummary
    let timeline: [DriveLineTripEvent]
    let signalMetadata: [DriveLineSignalDescriptor]
    let signals: [String: TripStorySignalSnapshot]
    let route: [RoutePoint]
    let cursorIndex: DriveLineCursorIndex
}

enum TripStorySnapshotBuilder {
    static let initialSignalUnits: [String: String] = [
        "speedKph": "km/h", "rpm": "rpm", "coolantC": "°C",
        "boostKpa": "kPa gauge", "fuelRateLph": "L/h",
        "dpfRegenTrigger": "%"
    ]

    static func key(for recording: DriveLineRecording) -> TripStorySnapshotKey {
        TripStorySnapshotKey(recordingID: recording.recordingID,
                             contentFingerprint: fingerprint(recording))
    }

    static func build(recording: DriveLineRecording,
                      signalUnits: [String: String] = initialSignalUnits) throws -> TripStorySnapshot {
        try Task.checkCancellation()
        return try DriveLinePerformance.measure("Trip Story snapshot preparation") {
            let key = key(for: recording)
            let summary = DriveLineJourneyPolicy.summary(for: recording)
            try Task.checkCancellation()
            let timeline = DriveLineJourneyPolicy.timeline(for: recording)
            let metadata = DriveLineJourneyPolicy.signalDescriptors(recording: recording)
            let cursorKeys = Array(Set(signalUnits.keys).union(metadata.map(\.key))).sorted()
            let cursorIndex = DriveLineCursorIndex(recording: recording, signalKeys: cursorKeys)
            try Task.checkCancellation()
            var signals: [String: TripStorySignalSnapshot] = [:]
            for key in signalUnits.keys.sorted() {
                try Task.checkCancellation()
                let series = DriveLineJourneyPolicy.signalSeries(key, unit: signalUnits[key] ?? "", recording: recording)
                signals[key] = TripStorySignalSnapshot(
                    series: series,
                    renderedSegments: DriveLineRenderingPolicy.signalSegments(series.segments)
                )
            }
            let route = recording.gpsPoints.map {
                RoutePoint(latitude: $0.latitude, longitude: $0.longitude, timestamp: $0.timestamp,
                           accuracy: $0.horizontalAccuracyM ?? 0, speed: $0.speedMps)
            }
            return TripStorySnapshot(key: key, summary: summary, timeline: timeline,
                signalMetadata: metadata, signals: signals, route: route, cursorIndex: cursorIndex)
        }
    }

    static func signal(_ key: String, unit: String,
                       recording: DriveLineRecording) throws -> TripStorySignalSnapshot {
        try Task.checkCancellation()
        let series = DriveLineJourneyPolicy.signalSeries(key, unit: unit, recording: recording)
        try Task.checkCancellation()
        return TripStorySignalSnapshot(series: series,
            renderedSegments: DriveLineRenderingPolicy.signalSegments(series.segments))
    }

    // Deterministic FNV-1a over evidence-bearing fields. Annotation and other
    // presentation metadata are intentionally excluded from this cache key.
    static func fingerprint(_ recording: DriveLineRecording) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        func mix(_ value: UInt64) { hash ^= value; hash &*= 1_099_511_628_211 }
        func mix(_ value: Double) { mix(value.bitPattern) }
        func mix(_ value: Date) { mix(value.timeIntervalSince1970) }
        func mix(_ value: String) { for byte in value.utf8 { mix(UInt64(byte)) } }
        mix(DriveLineMetricPolicy.version)
        mix(DriveLineAcquisitionPolicy.version)
        withUnsafeBytes(of: recording.recordingID.uuid) { for byte in $0 { mix(UInt64(byte)) } }
        mix(recording.startedAt); mix(recording.endedAt)
        for boundary in recording.acquisitionInterruptions ?? [] { mix(boundary) }
        for event in recording.events { mix(event.timestamp);mix(event.endTimestamp ?? event.timestamp);mix(event.kind);mix(event.note ?? "") }
        mix(UInt64(recording.gpsPoints.count)); mix(UInt64(recording.signalSamples.count))
        for point in recording.gpsPoints {
            mix(point.timestamp); mix(point.latitude); mix(point.longitude)
            mix(point.horizontalAccuracyM ?? -.infinity); mix(point.speedMps ?? -.infinity); mix(point.sourceID)
        }
        for sample in recording.signalSamples {
            mix(sample.timestamp); mix(sample.sourceID); mix(UInt64(sample.values.count))
            for key in sample.values.keys.sorted() { mix(key); mix(sample.values[key] ?? .nan) }
        }
        return hash
    }
}

actor TripStorySnapshotCache {
    static let shared = TripStorySnapshotCache(capacity: 3)

    private let capacity: Int
    private var values: [TripStorySnapshotKey: TripStorySnapshot] = [:]
    private var recency: [TripStorySnapshotKey] = []

    init(capacity: Int = 3) { self.capacity = max(1, capacity) }

    func snapshot(recording: DriveLineRecording) async throws -> TripStorySnapshot {
        let key = TripStorySnapshotBuilder.key(for: recording)
        if let cached = values[key] {
            touch(key)
            return cached
        }
        let work = Task.detached(priority: .userInitiated) {
            try TripStorySnapshotBuilder.build(recording: recording)
        }
        let prepared = try await withTaskCancellationHandler(operation: {
            try await work.value
        }, onCancel: {
            work.cancel()
        })
        try Task.checkCancellation()
        values[key] = prepared
        touch(key)
        while recency.count > capacity, let oldest = recency.first {
            recency.removeFirst(); values.removeValue(forKey: oldest)
        }
        return prepared
    }

    func removeAll() { values.removeAll(); recency.removeAll() }
    func cachedKeys() -> [TripStorySnapshotKey] { recency }
    func cachedCount() -> Int { values.count }

    private func touch(_ key: TripStorySnapshotKey) {
        recency.removeAll { $0 == key }; recency.append(key)
    }
}

/// Small history-row results shared by Drives and Fuel. All raw observation
/// conversion and metric work happens on this actor, never in a SwiftUI body.
/// Immutable Trip snapshots share their copy-on-write arrays with the library.
struct HistoryTripPresentation: Sendable {
    let quality: DriveLineJourneyQuality
    let fuel: DriveLineTripFuelPoint?
}
actor HistoryPresentationCache {
    static let shared=HistoryPresentationCache()
    private let capacity:Int
    private var entries:[UUID:(trip:Trip,value:HistoryTripPresentation)]=[:]
    private var order:[UUID]=[]
    private(set) var buildCount=0
    init(capacity:Int=128) { self.capacity=max(1,capacity) }
    func presentation(for trip:Trip) throws -> HistoryTripPresentation {
        try Task.checkCancellation()
        if let entry=entries[trip.id],entry.trip == trip {
            touch(trip.id);return entry.value
        }
        let recording=trip.sharedRecording
        let summary=DriveLineJourneyPolicy.summary(for:recording)
        try Task.checkCancellation()
        let metrics=summary.metrics
        let fuel:DriveLineTripFuelPoint?
        if !trip.isSample,let litres=metrics.tripFuelLitres {
            let measured=(metrics.coverage.first { $0.key == "fuelRateLph" }?.fraction ?? 0) >= DriveLineMetricPolicy.requiredFuelCoverage
            fuel=DriveLineTripFuelPoint(recordingID:trip.id,date:recording.endedAt,litres:litres,
                economyL100Km:metrics.economyL100Km,source:measured ? "Measured fuel rate":"Recorded trip summary")
        } else { fuel=nil }
        let value=HistoryTripPresentation(quality:summary.quality,fuel:fuel)
        entries[trip.id]=(trip,value);touch(trip.id);buildCount += 1
        while order.count > capacity { entries.removeValue(forKey:order.removeFirst()) }
        return value
    }
    private func touch(_ id:UUID) { order.removeAll { $0 == id };order.append(id) }
    var count:Int { entries.count }
}
