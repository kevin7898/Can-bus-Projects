import XCTest
@testable import CANConnect

final class Phase91TripStoryPerformanceTests:XCTestCase {
    func testContentFingerprintInvalidatesButAnnotationDoesNotParticipate() {
        let original=recording(index:1,observations:5_000)
        let first=TripStorySnapshotBuilder.key(for:original)
        var changed=original
        changed.signalSamples[0].values["rpm"] = 9_999
        XCTAssertNotEqual(first,TripStorySnapshotBuilder.key(for:changed))

        // Journey annotations live outside the recording and therefore cannot
        // invalidate immutable telemetry preparation.
        let annotation=DriveLineJourneyAnnotation(recordingID:original.recordingID,note:"Reviewed")
        XCTAssertEqual(annotation.recordingID,first.recordingID)
        XCTAssertEqual(first,TripStorySnapshotBuilder.key(for:original))
    }

    func testCacheIsBoundedToThreeMostRecentSnapshots() async throws {
        let cache=TripStorySnapshotCache(capacity:3)
        for index in 0..<4 { _ = try await cache.snapshot(recording:recording(index:index,observations:200)) }
        let cachedCount=await cache.cachedCount()
        XCTAssertEqual(cachedCount,3)
        let ids=await cache.cachedKeys().map(\.recordingID)
        XCTAssertFalse(ids.contains(recording(index:0,observations:200).recordingID))
        XCTAssertTrue(ids.contains(recording(index:3,observations:200).recordingID))
    }

    func testCancelledSelectionDoesNotPopulateCache() async throws {
        let cache=TripStorySnapshotCache(capacity:3)
        let large=recording(index:2,observations:120_000)
        let task=Task { try await cache.snapshot(recording:large) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled work must not be accepted") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        let cachedCount=await cache.cachedCount()
        XCTAssertEqual(cachedCount,0)
    }

    func testDisplayPointBoundsAndBinaryCursorLookup() throws {
        let recording=recording(index:3,observations:10_000)
        let snapshot=try TripStorySnapshotBuilder.build(recording:recording)
        for value in snapshot.signals.values {
            XCTAssertLessThanOrEqual(value.renderedSegments.flatMap{$0}.count,
                                     DriveLineRenderingPolicy.defaultPointLimit + value.renderedSegments.count * 2)
        }
        let cursor=recording.startedAt.addingTimeInterval(300)
        let indexed=snapshot.cursorIndex.selection(at:cursor,signalKeys:["rpm","speedKph"])
        let linear=DriveLineJourneyPolicy.cursor(at:cursor,recording:recording,signalKeys:["rpm","speedKph"])
        XCTAssertEqual(indexed,linear)
    }

    func testSanitizedMillionObservationCorpusCanBePreparedInBoundedBatches() throws {
        var total=0
        for index in 0..<DriveLinePerformanceFixture.journeyCount {
            let recording=DriveLinePerformanceFixture.recording(at:index)
            total += recording.gpsPoints.count + recording.signalSamples.count
            if index % 100 == 0 {
                let snapshot=try TripStorySnapshotBuilder.build(recording:recording)
                XCTAssertEqual(snapshot.key.recordingID,recording.recordingID)
                XCTAssertTrue(recording.isSample)
            }
        }
        XCTAssertEqual(total,DriveLinePerformanceFixture.totalObservationCount)
    }

    private func recording(index:Int,observations:Int)->DriveLineRecording {
        let start=Date(timeIntervalSince1970:1_700_000_000+Double(index)*10_000)
        let id=UUID(uuidString:String(format:"00000000-0000-4000-8000-%012x",80_000+index))!
        let samples=(0..<observations).map { value in
            DriveLineSignalSample(timestamp:start.addingTimeInterval(Double(value)),
                values:["rpm":1_500+Double(value%1_000),"speedKph":40+Double(value%40)],sourceID:"synthetic-obd")
        }
        return DriveLineRecording(recordingID:id,vehicleID:UUID(),name:"Sanitized performance fixture",
            startedAt:start,endedAt:start.addingTimeInterval(Double(max(1,observations-1))),
            sourceIDs:["synthetic-obd","synthetic"],signalSamples:samples,isSample:true)
    }
}

extension Phase91TripStoryPerformanceTests {
    private func historyTrip(samples:Int=5_000)->Trip {
        let start=Date(timeIntervalSince1970:1_700_000_000)
        return Trip(name:"Synthetic history performance",startedAt:start,duration:Double(samples-1),distanceKM:10,source:.scanner,isSample:false,
                    samples:(0..<samples).map { i in OBDSample(timestamp:start.addingTimeInterval(Double(i)),signals:["rpm":1500,"speedKph":60,"fuelRateLph":6],command:"010C",reply:"fixture") })
    }
    func testHistoryCacheMatchesPoliciesAndInvalidatesSameIDEdits() async throws {
        let cache=HistoryPresentationCache(capacity:2)
        var trip=historyTrip(samples:100)
        let first=try await cache.presentation(for:trip)
        XCTAssertEqual(first.quality,DriveLineJourneyPolicy.summary(for:trip.sharedRecording).quality)
        XCTAssertEqual(first.fuel,DriveLineJourneyPolicy.tripFuelSeries([trip.sharedRecording]).first)
        _ = try await cache.presentation(for:trip)
        let builds=await cache.buildCount;XCTAssertEqual(builds,1)
        trip.samples?[0].signals["fuelRateLph"]=100
        let changed=try await cache.presentation(for:trip)
        XCTAssertEqual(changed.fuel,DriveLineJourneyPolicy.tripFuelSeries([trip.sharedRecording]).first)
        let nextBuilds=await cache.buildCount;XCTAssertEqual(nextBuilds,2)
        XCTAssertNotEqual(first.fuel?.litres,changed.fuel?.litres)
        for _ in 0..<3 { _ = try await cache.presentation(for:historyTrip(samples:10)) }
        let count=await cache.count;XCTAssertEqual(count,2)
    }
    @MainActor func testLargeHistoryPreparationDoesNotBlockMainActorAndWarmCacheIsReused() async throws {
        let cache=HistoryPresentationCache(),trip=historyTrip(samples:30_000)
        let work=Task { try await cache.presentation(for:trip) }
        let start=ContinuousClock.now
        try await Task.sleep(for:.milliseconds(20))
        let delay=ContinuousClock.now-start
        XCTAssertLessThan(delay,.seconds(1),"History analysis must not freeze the main actor")
        _ = try await work.value
        for _ in 0..<10 { _ = try await cache.presentation(for:trip) }
        let count=await cache.buildCount;XCTAssertEqual(count,1)
        XCTAssertEqual(trip.historySourceIDs,trip.sharedRecording.sourceIDs)
    }
    func testCancelledHistoryDoesNotEnterCache() async throws {
        let cache=HistoryPresentationCache(),trip=historyTrip()
        let work=Task { () throws ->HistoryTripPresentation in
            try await Task.sleep(for:.seconds(1))
            return try await cache.presentation(for:trip)
        }
        work.cancel()
        do { _ = try await work.value;XCTFail("Expected cancellation") } catch is CancellationError { }
        let count=await cache.count;XCTAssertEqual(count,0)
    }
}
