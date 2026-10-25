import XCTest
@testable import CANConnect

final class AppStoreTests: XCTestCase {
    @MainActor
    func testRecordingDeepLinkSelectsRecordDestination() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store=AppStore(disk:LocalStore(url:directory.appendingPathComponent("state.json")))
        store.selectedTab = .today
        store.openDeepLink(try XCTUnwrap(URL(string:"canconnect://recording")))
        XCTAssertEqual(store.selectedTab,.record)
    }

    @MainActor
    func testImportIsIdempotentAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let disk = LocalStore(url:directory.appendingPathComponent("state.json"))
        let store = AppStore(disk:disk)
        let originalCount = store.state.trips.count
        let fixture = SampleData.state()
        var trip = fixture.trips[0]; trip.id = UUID()
        let archive = try TripArchive(vehicles:fixture.vehicles,trips:[trip]).encoded()
        try store.importTrips(archive); try store.importTrips(archive)
        XCTAssertEqual(store.state.trips.count,originalCount+1)
        XCTAssertEqual(try disk.load()?.trips.count,originalCount+1)
    }
    @MainActor
    func testInterruptedRecordingRecoveredOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let disk = LocalStore(url:directory.appendingPathComponent("state.json"))
        let start = Date().addingTimeInterval(-30)
        let draft = RecordingDraft(source:.phoneGPS,startedAt:start,updatedAt:start.addingTimeInterval(20))
        var state = StoredState(); state.draft = draft; try disk.save(state)
        let first = AppStore(disk:disk)
        XCTAssertFalse(first.recording); XCTAssertEqual(first.state.trips.count,1)
        XCTAssertEqual(first.state.trips[0].duration,20,accuracy:0.001)
        XCTAssertEqual(AppStore(disk:disk).state.trips.count,1)
    }
}
