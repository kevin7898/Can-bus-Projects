import XCTest
@testable import DriveLineShared

final class DriveLineSharedTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }

    func testVersion2GoldenMetricsAndDeterministicRoundTrip() throws {
        let archive = try DriveLineArchive.decoded(fixture("golden-v2"))
        let recording = try XCTUnwrap(archive.recordings.first)
        let metrics = DriveLineMetricPolicy.metrics(for: recording)
        XCTAssertEqual(archive.schemaVersion, 2)
        XCTAssertEqual(recording.recordingID.uuidString, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(metrics.durationSeconds, 20, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.distanceKm), 0.200_15, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(metrics.tripFuelLitres), 0.02, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(metrics.economyL100Km), 9.9925, accuracy: 0.05)
        XCTAssertEqual(metrics.coverage.first(where: { $0.key == "fuelRateLph" })?.fraction, 1)
        XCTAssertEqual(metrics.distanceSource, "gps")
        XCTAssertEqual(try DriveLineArchive.decoded(archive.encoded()), archive)
        XCTAssertEqual(try archive.encoded(), try archive.encoded())
    }

    func testVersion1MigrationPreservesStableIdentityAndPrecision() throws {
        let archive = try DriveLineArchive.decoded(fixture("migration-v1"))
        let recording = try XCTUnwrap(archive.recordings.first)
        XCTAssertEqual(archive.schemaVersion, 2)
        XCTAssertEqual(recording.recordingID.uuidString, "33333333-3333-4333-8333-333333333333")
        XCTAssertEqual(recording.vehicleID.uuidString, "22222222-2222-4222-8222-222222222222")
        XCTAssertEqual(recording.startedAt.timeIntervalSince1970, 1_767_268_800.125, accuracy: 0.000_001)
    }

    func testLatestSignalsBoostAndSamplesStayIndependent() throws {
        let original = try XCTUnwrap(DriveLineArchive.decoded(fixture("golden-v2")).recordings.first)
        var gpsOnly = original
        gpsOnly.recordingID = UUID()
        gpsOnly.startedAt = original.endedAt.addingTimeInterval(100)
        gpsOnly.endedAt = gpsOnly.startedAt.addingTimeInterval(10)
        gpsOnly.signalSamples = []
        let latest = DriveLineMetricPolicy.latestObservations([original, gpsOnly])
        XCTAssertEqual(latest["rpm"]?.value, 1700)
        XCTAssertEqual(DriveLineMetricPolicy.boostGaugeKpa(observations: latest, at: original.endedAt)?.value, 35)
        XCTAssertNil(DriveLineMetricPolicy.boostGaugeKpa(observations: latest, at: original.endedAt.addingTimeInterval(100)))
        var sample = original
        sample.recordingID = UUID()
        sample.isSample = true
        sample.signalSamples = [DriveLineSignalSample(timestamp: original.endedAt.addingTimeInterval(1), values: ["rpm": 9999])]
        XCTAssertEqual(DriveLineMetricPolicy.latestObservations([original, sample])["rpm"]?.value, 1700)
    }

    func testFillQuantityIsSeparateFromTripFuelAndSamplesExcluded() throws {
        let archive = try DriveLineArchive.decoded(fixture("golden-v2"))
        XCTAssertEqual(archive.recordings.first?.tripFuelLitres, 0.02)
        XCTAssertEqual(archive.fuelEntries.first?.litresPurchased, 42.5)
        let vehicleID = try XCTUnwrap(archive.vehicles.first?.id)
        let first = DriveLineFuelEntry(vehicleID: vehicleID, date: .distantPast, litresPurchased: 40,
                                       totalCost: 60, odometerKm: 10_000, isFullFill: true)
        let partial = DriveLineFuelEntry(vehicleID: vehicleID, date: .distantPast, litresPurchased: 10,
                                         totalCost: 15, odometerKm: 10_200, isFullFill: false)
        let last = DriveLineFuelEntry(vehicleID: vehicleID, date: .distantPast, litresPurchased: 20,
                                      totalCost: 30, odometerKm: 10_600, isFullFill: true)
        let sample = DriveLineFuelEntry(vehicleID: vehicleID, date: .distantPast, litresPurchased: 100,
                                        totalCost: 0, odometerKm: 10_700, isFullFill: true, isSample: true)
        XCTAssertEqual(try XCTUnwrap(DriveLineMetricPolicy.tankToTankEconomy([first, partial, last, sample])), 5, accuracy: 0.000_001)
        XCTAssertEqual(DriveLineMetricPolicy.normalizedDPFRegenTrigger(43), 43)
        XCTAssertNil(DriveLineMetricPolicy.normalizedDPFRegenTrigger(101))
    }
}
