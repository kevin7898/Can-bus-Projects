import Foundation
import OSLog

/// Signposts contain operation names only. Stable IDs, VINs, coordinates,
/// scanner details, addresses, credentials, and receipt content are never logged.
public enum DriveLinePerformance {
    private static let signposter = OSSignposter(subsystem: "app.driveline.performance", category: "EvidencePipeline")

    @discardableResult
    public static func measure<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try operation()
    }

    @discardableResult
    public static func measureAsync<T>(_ name: StaticString, _ operation: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await operation()
    }

    public static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}

/// Display-only reduction. Original observations are never mutated or removed.
/// Segments are reduced independently, isolated points stay isolated, and every
/// bucket keeps its recorded minimum and maximum in timestamp order.
public enum DriveLineRenderingPolicy {
    public static let defaultPointLimit = 2_400

    public static func signalSegments(_ segments: [[DriveLineSignalPoint]], limit: Int = defaultPointLimit) -> [[DriveLineSignalPoint]] {
        DriveLinePerformance.measure("Chart preparation") {
            reduce(segments, limit:limit, value: { $0.value }, timestamp: { $0.timestamp })
        }
    }

    public static func alignedSegments(_ segments: [[DriveLineAlignedSignalPoint]], limit: Int = defaultPointLimit) -> [[DriveLineAlignedSignalPoint]] {
        DriveLinePerformance.measure("Chart preparation aligned") {
            reduce(segments, limit:limit, value: { $0.point.value }, timestamp: { $0.point.timestamp })
        }
    }

    private static func reduce<Point>(_ segments: [[Point]], limit: Int,
                                      value: (Point) -> Double, timestamp: (Point) -> Date) -> [[Point]] {
        let finite = segments.map { $0.filter { value($0).isFinite }.sorted { timestamp($0) < timestamp($1) } }
        let total = finite.reduce(0) { $0 + $1.count }
        guard total > max(2,limit) else { return finite }
        let minimumRequired = finite.reduce(0) { $0 + min(2,$1.count) }
        let budget = max(max(2,limit),minimumRequired)
        return finite.map { segment in
            guard !segment.isEmpty else { return [] }
            let proportional = Int((Double(segment.count) / Double(total) * Double(budget)).rounded())
            return envelope(segment, limit:max(min(2,segment.count),proportional), value:value, timestamp:timestamp)
        }
    }

    private static func envelope<Point>(_ points: [Point], limit: Int,
                                        value: (Point) -> Double, timestamp: (Point) -> Date) -> [Point] {
        guard points.count > limit, limit >= 3 else {
            if points.count <= limit { return points }
            return [points.first!,points.last!]
        }
        let interior = Array(points.dropFirst().dropLast())
        let bucketCount = max(1,(limit-2)/2)
        let bucketSize = max(1,Int(ceil(Double(interior.count)/Double(bucketCount))))
        var selected = [points[0]]
        for start in stride(from:0,to:interior.count,by:bucketSize) {
            let bucket = Array(interior[start..<min(interior.count,start+bucketSize)])
            guard let low=bucket.min(by:{value($0)<value($1)}),let high=bucket.max(by:{value($0)<value($1)}) else { continue }
            if timestamp(low)==timestamp(high) { selected.append(low) }
            else { selected.append(contentsOf:[low,high].sorted{timestamp($0)<timestamp($1)}) }
        }
        selected.append(points[points.count-1])
        return selected.sorted { timestamp($0)<timestamp($1) }
    }
}

#if DEBUG
/// Sanitized, deterministic, debug-only Phase 9 corpus. It is generated in
/// bounded batches so one million observations can be exercised without an
/// unbounded in-memory cache.
public enum DriveLinePerformanceFixture {
    public static let journeyCount = 500
    public static let observationsPerJourney = 2_000
    public static let totalObservationCount = journeyCount * observationsPerJourney
    public static let transferStates = ["queued","failed","complete"]
    public static let baseDate = Date(timeIntervalSince1970:1_700_000_000)

    public static let vehicles: [DriveLineVehicle] = (0..<4).map { index in
        DriveLineVehicle(id:uuid(index), name:"Sanitized sample vehicle \(index+1)",
                         year:String(2013+index),make:index==0 ? "Volkswagen":"Fictional",
                         model:index==0 ? "Jetta TDI":"Test vehicle",vehicleClass:.passengerCar,
                         fuelType:index==0 ? "Diesel":"Test fuel",configuredSources:[.phoneGPS,.obdScanner,.importedArchive],
                         isArchived:index==3)
    }

    public static let fuelEntries: [DriveLineFuelEntry] = (0..<40).map { index in
        let digest=String(repeating:String(format:"%x",index%16),count:64)
        return DriveLineFuelEntry(id:uuid(10_000+index),vehicleID:vehicles[index%vehicles.count].id,
            date:baseDate.addingTimeInterval(Double(index)*86_400),litresPurchased:42+Double(index%5),
            totalCost:70+Double(index),currencyCode:index%2==0 ? "CAD":"USD",
            odometerKm:150_000+Double(index)*650,isFullFill:index%3 != 1,
            stationName:"Sanitized sample station",notes:"Synthetic performance metadata",
            receipt:DriveLineReceiptMetadata(fileName:"sample-receipt-\(index).pdf",mediaType:"application/pdf",
                byteCount:128+index,sha256:digest,capturedAt:baseDate.addingTimeInterval(Double(index)*86_400)),isSample:true)
    }

    public static func recording(at index: Int, observationCount: Int = observationsPerJourney) -> DriveLineRecording {
        precondition((0..<journeyCount).contains(index))
        let mode=index%3
        let gpsCount = mode==0 ? observationCount : mode==1 ? 0 : observationCount/2
        let signalCount = observationCount-gpsCount
        let start=baseDate.addingTimeInterval(Double(index)*7_200)
        func timestamp(_ position:Int,_ count:Int)->Date {
            let fraction=count>1 ? Double(position)/Double(count-1):0
            let irregular=Double(position)*0.82+Double(position%7)*0.07
            return start.addingTimeInterval(irregular+(fraction>0.5 ? 75:0))
        }
        let gps=(0..<gpsCount).map { position in
            DriveLineGPSPoint(timestamp:timestamp(position,gpsCount),latitude:0.01+Double(position)*0.000_001,
                longitude:0.01+Double(position)*0.000_0015,horizontalAccuracyM:6+Double(position%4),
                speedMps:14+Double(position%6),sourceID:"synthetic-gps")
        }
        let signals:[DriveLineSignalSample]=(0..<signalCount).map { position in
            let observedAt=timestamp(position,signalCount)
            let values:[String:Double]=[
                "rpm":1_700+Double(position%900),
                "speedKph":50+Double(position%35),
                "fuelRateLph":4+Double(position%6)/10,
                "boostAbsoluteKpa":125+Double(position%30),
                "barometricKpa":100,
                "dpfRegenTrigger":Double(position%101)
            ]
            return DriveLineSignalSample(timestamp:observedAt,values:values,sourceID:"synthetic-obd")
        }
        let end=max(gps.last?.timestamp ?? start,signals.last?.timestamp ?? start)
        return DriveLineRecording(recordingID:uuid(20_000+index),vehicleID:vehicles[index%vehicles.count].id,
            name:"Sanitized sample journey \(index+1)",startedAt:start,endedAt:end,
            sourceIDs:[gps.isEmpty ? nil:"synthetic-gps",signals.isEmpty ? nil:"synthetic-obd","synthetic"].compactMap{$0},
            gpsPoints:gps,signalSamples:signals,notes:"Debug-only Phase 9 performance fixture",isSample:true)
    }

    public static func thirtyMinuteRecording() -> DriveLineRecording {
        let count=1_801
        let start=baseDate
        let gps=(0..<count).map { index in DriveLineGPSPoint(timestamp:start.addingTimeInterval(Double(index)),
            latitude:0.02+Double(index)*0.000_001,longitude:0.02+Double(index)*0.000_001,
            horizontalAccuracyM:8,speedMps:12,sourceID:"synthetic-gps") }
        let signals=(0..<count).map { index in DriveLineSignalSample(timestamp:start.addingTimeInterval(Double(index)),
            values:["rpm":1_800+Double(index%500),"speedKph":54,"fuelRateLph":4.8],sourceID:"synthetic-obd") }
        return DriveLineRecording(recordingID:uuid(99_999),vehicleID:vehicles[0].id,
            name:"Sanitized 30-minute sample",startedAt:start,endedAt:start.addingTimeInterval(1_800),
            sourceIDs:["synthetic-gps","synthetic-obd","synthetic"],gpsPoints:gps,signalSamples:signals,
            notes:"Accelerated simulation of a 30-minute recording and playback session",isSample:true)
    }

    private static func uuid(_ value:Int)->UUID {
        UUID(uuidString:String(format:"00000000-0000-4000-8000-%012x",value))!
    }
}
#endif
