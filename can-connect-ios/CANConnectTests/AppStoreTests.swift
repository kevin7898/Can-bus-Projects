import XCTest
@testable import CANConnect

final class AppStoreTests: XCTestCase {
    func testTodayPresentationExcludesSampleDataAndKeepsLatestRealEntitiesIndependent() throws {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=try XCTUnwrap(TimeZone(secondsFromGMT:0))
        let now=try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-25T18:00:00Z"))
        var vehicle=VehicleProfile();vehicle.nickname="Real Jetta"
        let real=Trip(vehicleID:vehicle.id,name:"Morning drive",startedAt:now.addingTimeInterval(-3600),duration:1800,distanceKM:22,
                      source:.scanner,isSample:false,economy:5,fuelLitres:1.1)
        let noFuel=Trip(vehicleID:vehicle.id,name:"Lunch drive",startedAt:now.addingTimeInterval(-900),duration:600,distanceKM:8,
                        source:.phoneGPS,isSample:false,economy:nil,fuelLitres:nil)
        let sample=Trip(vehicleID:vehicle.id,name:"Newer sample",startedAt:now.addingTimeInterval(-60),duration:999,distanceKM:999,
                        source:.demo,isSample:true,economy:1,fuelLitres:99)
        let realFill=FuelEntry(vehicleID:vehicle.id,date:now.addingTimeInterval(-7200),litres:42,costCAD:70,odometerKM:200_000,full:true)
        let sampleFill=FuelEntry(vehicleID:vehicle.id,date:now.addingTimeInterval(-30),litres:100,costCAD:0,odometerKM:1,full:true,isSample:true)
        var state=StoredState();state.vehicles=[vehicle];state.selectedVehicleID=vehicle.id
        state.trips=[sample,real,noFuel];state.fills=[sampleFill,realFill]

        let value=PhoneTodayPresentation.make(state:state,now:now,calendar:calendar,gpsStatus:"Ready",scannerStatus:"Not connected",scannerConnected:false,scannerConnecting:false)

        XCTAssertEqual(value.todayDriveCount,2)
        XCTAssertEqual(value.todayDistanceKM,30,accuracy:0.000_001)
        XCTAssertEqual(value.todayDuration,2400,accuracy:0.000_001)
        XCTAssertEqual(value.todayFuelLitres,1.1)
        XCTAssertEqual(value.todayFuelDriveCount,1)
        XCTAssertEqual(value.latestTrip?.id,noFuel.id)
        XCTAssertEqual(value.latestFill?.id,realFill.id)
    }

    func testTodayPresentationDoesNotRenderUnavailableFuelAsZero() {
        var vehicle=VehicleProfile();vehicle.nickname="GPS vehicle"
        let now=Date()
        let trip=Trip(vehicleID:vehicle.id,name:"GPS drive",startedAt:now,duration:60,distanceKM:1,
                      source:.phoneGPS,isSample:false,economy:nil,fuelLitres:nil)
        var state=StoredState();state.vehicles=[vehicle];state.selectedVehicleID=vehicle.id;state.trips=[trip]
        let value=PhoneTodayPresentation.make(state:state,now:now,gpsStatus:"Ready",scannerStatus:"Not connected",scannerConnected:false,scannerConnecting:false)
        XCTAssertNil(value.todayFuelLitres)
    }

    func testRecordingPresentationCoversLifecycleStates() {
        let now=Date(), idle=StoredState()
        func value(_ state:StoredState=idle,pending:Bool=false,connected:Bool=false,connecting:Bool=false,stopping:Bool=false,recovered:Bool=false)->PhoneRecordingPhase {
            PhoneRecordingPresentation.make(state:state,selectedSource:.phoneGPS,pendingGPS:pending,scannerConnected:connected,
                scannerConnecting:connecting,scannerStatus:"Synthetic",gpsStatus:"Synthetic",gpsSpeedKMH:nil,gpsLastFix:nil,now:now,
                isStopping:stopping,recovered:recovered).phase
        }
        XCTAssertEqual(value(),.idle)
        XCTAssertEqual(value(pending:true),.starting)
        var active=StoredState();active.draft=RecordingDraft(source:.phoneGPS,startedAt:now,updatedAt:now)
        XCTAssertEqual(value(active),.active)
        var degraded=StoredState();degraded.draft=RecordingDraft(source:.scanner,startedAt:now.addingTimeInterval(-20),updatedAt:now)
        XCTAssertEqual(value(degraded),.degraded)
        XCTAssertEqual(value(active,stopping:true),.stopping)
        XCTAssertEqual(value(recovered:true),.recovered)
    }

    func testRecordingPresentationSelectsFreshnessIndependentlyAndUsesNoSyntheticZero() throws {
        let now=Date(), old=now.addingTimeInterval(-30), recent=now.addingTimeInterval(-1)
        var draft=RecordingDraft(source:.scanner,startedAt:old,updatedAt:recent)
        draft.samples=[
            OBDSample(timestamp:old,signals:["rpm":1800,"dpfSootG":11.1],command:"VW",reply:"fixture"),
            OBDSample(timestamp:recent,signals:["coolantC":89,"dpfRegenTrigger":43],command:"VW",reply:"fixture")
        ]
        var state=StoredState();state.draft=draft
        let value=PhoneRecordingPresentation.make(state:state,selectedSource:.scanner,pendingGPS:false,scannerConnected:true,
            scannerConnecting:false,scannerStatus:"Connected",gpsStatus:"Active",gpsSpeedKMH:84,gpsLastFix:recent,now:now)
        let rpm=try XCTUnwrap(value.metrics.first{$0.key=="rpm"})
        let coolant=try XCTUnwrap(value.metrics.first{$0.key=="coolantC"})
        let boost=try XCTUnwrap(value.metrics.first{$0.key=="boostGaugeKpa"})
        let trigger=try XCTUnwrap(value.metrics.first{$0.key=="dpfRegenTrigger"})
        XCTAssertEqual(rpm.value,1800);XCTAssertEqual(rpm.state,.stale)
        XCTAssertEqual(coolant.value,89);XCTAssertEqual(coolant.state,.healthy)
        XCTAssertNil(boost.value);XCTAssertEqual(boost.state,.unavailable)
        XCTAssertEqual(trigger.value,43,"Trigger remains a normalized indicator rather than physical fullness")
    }

    func testRecordingPresentationKeepsRemainingSourceActiveAndNamesQueuedUploads() throws {
        let now=Date(), start=now.addingTimeInterval(-30)
        var state=StoredState();state.draft=RecordingDraft(source:.scanner,startedAt:start,updatedAt:now)
        state.transfers=[TransferItem(tripID:UUID(),name:"Fixture upload",endpoint:"local",
                                      vehicle:VehicleProfile(),payload:Data())]

        let gpsLoss=PhoneRecordingPresentation.make(state:state,selectedSource:.scanner,pendingGPS:false,
            scannerConnected:true,scannerConnecting:false,scannerStatus:"Connected",gpsStatus:"Waiting",
            gpsSpeedKMH:nil,gpsLastFix:nil,now:now)
        XCTAssertEqual(gpsLoss.phase,.degraded)
        XCTAssertEqual(gpsLoss.scannerState,.healthy)
        XCTAssertEqual(gpsLoss.recoveryTitle,"GPS unavailable")
        XCTAssertEqual(gpsLoss.queuedStatusTitle,"Upload queued · 1")

        let scannerLoss=PhoneRecordingPresentation.make(state:state,selectedSource:.scanner,pendingGPS:false,
            scannerConnected:false,scannerConnecting:false,scannerStatus:"Disconnected",gpsStatus:"Active",
            gpsSpeedKMH:72,gpsLastFix:now,now:now)
        XCTAssertEqual(scannerLoss.phase,.degraded)
        XCTAssertEqual(scannerLoss.gpsState,.healthy)
        XCTAssertEqual(scannerLoss.recoveryTitle,"Scanner disconnected")
    }

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
    func testFinishSavesDraftExactlyOnce() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let disk=LocalStore(url:directory.appendingPathComponent("state.json"))
        let store=AppStore(disk:disk)
        store.state.draft=RecordingDraft(vehicleID:store.state.selectedVehicleID,source:.demo,startedAt:Date(),updatedAt:Date())
        let id=try XCTUnwrap(store.state.draft?.id)
        store.finishRecording();store.finishRecording()
        XCTAssertEqual(store.state.trips.filter{$0.id==id}.count,1)
        XCTAssertEqual(try disk.load()?.trips.filter{$0.id==id}.count,1)
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
