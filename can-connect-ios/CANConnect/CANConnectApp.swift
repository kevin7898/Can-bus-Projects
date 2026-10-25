import SwiftUI
import Combine

@main
struct CANConnectApp: App {
    @StateObject private var store: AppStore
    @AppStorage(DriveLineAppearance.storageKey) private var appearanceRaw=DriveLineAppearance.system.rawValue
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            _store = StateObject(wrappedValue:DriveLineCanvas.makeStore())
            return
        }
        #endif
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let arguments=ProcessInfo.processInfo.arguments
            if arguments.contains("--appearance-light") { UserDefaults.standard.set(DriveLineAppearance.light.rawValue,forKey:DriveLineAppearance.storageKey) }
            if arguments.contains("--appearance-dark") { UserDefaults.standard.set(DriveLineAppearance.dark.rawValue,forKey:DriveLineAppearance.storageKey) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("can-connect-ui-tests/state.json")
            try? FileManager.default.removeItem(at:url.deletingLastPathComponent())
            let usesPhase3Fixture=arguments.contains("--phase3-active") || arguments.contains("--phase3-degraded")
            let testStore = AppStore(disk:LocalStore(url:url),gps:usesPhase3Fixture ? Phase3FixtureGPS():nil)
            if !arguments.contains("--show-onboarding") { testStore.state.onboardingCompleted = true; testStore.save() }
            if arguments.contains("--record-tab") { testStore.selectedTab = .record }
            if arguments.contains("--phase4-fixture") {
                let vehicle=testStore.state.vehicles.first ?? VehicleProfile.sample
                let start=Date().addingTimeInterval(-3_600)
                let route=SampleData.routeCoordinates.enumerated().map { index,coordinate in
                    RoutePoint(latitude:coordinate[0],longitude:coordinate[1],timestamp:start.addingTimeInterval(Double(index)*20),accuracy:5,speed:18)
                }
                let samples=(0..<route.count).map { index in
                    let indexValue=Double(index)
                    let signals:[String:Double]=[
                        "speedKph":72+indexValue,
                        "rpm":1_600+Double(index*25),
                        "coolantC":86+indexValue/4,
                        "fuelRateLph":4.2,
                        "boostAbsoluteKpa":132+indexValue,
                        "barometricKpa":101,
                        "dpfRegenTrigger":indexValue*7,
                    ]
                    return OBDSample(
                        timestamp:route[index].timestamp,
                        signals:signals,
                        command:"FIXTURE",
                        reply:"Sanitized Phase 4 observation \(index)"
                    )
                }
                let trip=Trip(vehicleID:vehicle.id,name:"Sanitized sample journey",startedAt:start,duration:Double(max(1,route.count-1))*20,distanceKM:4.8,source:.demo,isSample:true,economy:8.75,fuelLitres:0.42,route:route,samples:samples)
                let first=FuelEntry(vehicleID:vehicle.id,date:start.addingTimeInterval(-20*86_400),litres:36,costCAD:61.20,odometerKM:216_000,full:true,isSample:true,stationName:"Sample station")
                let partial=FuelEntry(vehicleID:vehicle.id,date:start.addingTimeInterval(-10*86_400),litres:12,costCAD:21.48,odometerKM:216_260,full:false,isSample:true,stationName:"Sample station")
                let last=FuelEntry(vehicleID:vehicle.id,date:start.addingTimeInterval(-2*86_400),litres:24,costCAD:42.96,odometerKM:216_600,full:true,isSample:true,stationName:"Sample station")
                testStore.state.vehicles=[vehicle];testStore.state.selectedVehicleID=vehicle.id;testStore.state.trips=[trip];testStore.state.fills=[first,partial,last]
                testStore.state.journeyAnnotations[trip.id.uuidString]=DriveLineJourneyAnnotation(recordingID:trip.id,purpose:.service,reviewed:true,startPlace:"Sample start",finishPlace:"Sample finish")
                testStore.selectedTab = .drives;testStore.save()
            }
            if arguments.contains("--phase5-fixture") {
                var vehicle=VehicleProfile();vehicle.make="Volkswagen";vehicle.model="Jetta TDI";vehicle.year=2014;vehicle.fuel = .diesel;vehicle.nickname="Sanitized Jetta"
                let end=Date(),start=end.addingTimeInterval(-2_700)
                let samples=(0...18).map { index in
                    OBDSample(timestamp:start.addingTimeInterval(Double(index)*150),signals:["speedKph":76,"rpm":1_820,"fuelRateLph":4.4],command:"FIXTURE",reply:"Sanitized Phase 5 observation")
                }
                let trip=Trip(vehicleID:vehicle.id,name:"Sanitized measured journey",startedAt:start,duration:2_700,distanceKM:55.8,source:.scanner,isSample:false,economy:5.2,fuelLitres:2.9,samples:samples)
                let first=FuelEntry(vehicleID:vehicle.id,date:end.addingTimeInterval(-24*86_400),litres:38,costCAD:64.60,odometerKM:216_000,full:true,currencyCode:"CAD",stationName:"Harbour Fuel",notes:"Sanitized fixture")
                let partial=FuelEntry(vehicleID:vehicle.id,date:end.addingTimeInterval(-12*86_400),litres:12,costCAD:21.48,odometerKM:216_260,full:false,currencyCode:"CAD",stationName:"Island Fuel")
                let last=FuelEntry(vehicleID:vehicle.id,date:end.addingTimeInterval(-2*86_400),litres:24,costCAD:42.96,odometerKM:216_600,full:true,currencyCode:"CAD",stationName:"Harbour Fuel",notes:"Full tank after partial fill")
                testStore.state.vehicles=[vehicle];testStore.state.selectedVehicleID=vehicle.id;testStore.state.trips=[trip];testStore.state.fills=[first,partial,last]
                testStore.state.onboardingCompleted=true;testStore.selectedTab = .garage;testStore.save()
            }
            // Sanitized, debug-only state fixtures used for Phase 3 visual evidence.
            if usesPhase3Fixture {
                let start=Date().addingTimeInterval(-140)
                let route=SampleData.routeCoordinates.enumerated().map { index,coordinate in
                    RoutePoint(latitude:coordinate[0],longitude:coordinate[1],timestamp:start.addingTimeInterval(Double(index)*20),accuracy:5,speed:18)
                }
                let degraded=arguments.contains("--phase3-degraded")
                var draft=RecordingDraft(vehicleID:testStore.state.selectedVehicleID,source:degraded ? .scanner:.demo,
                                         startedAt:start,updatedAt:Date(),distanceKM:4,route:route)
                if degraded {
                    draft.samples=[OBDSample(timestamp:Date().addingTimeInterval(-90),signals:["rpm":1840,"coolantC":89,"dpfSootG":11.1,"dpfRegenTrigger":43],command:"FIXTURE",reply:"Sanitized Phase 3 fixture")]
                    draft.scannerReconnectDeadline=Date().addingTimeInterval(30);testStore.source = .scanner
                } else {
                    draft.samples=[OBDSample(timestamp:Date(),signals:["rpm":1840,"coolantC":89,"boostAbsoluteKpa":136,"barometricKpa":101,"dsgFluidC":78,"dpfSootG":11.1,"dpfRegenTrigger":43],command:"FIXTURE",reply:"Sanitized Phase 3 fixture")]
                }
                testStore.state.draft=draft;testStore.selectedTab = .record
            }
            _store = StateObject(wrappedValue:testStore)
        } else { _store = StateObject(wrappedValue:AppStore()) }
    }
    var body: some Scene { WindowGroup { RootView().environmentObject(store)
        .preferredColorScheme((DriveLineAppearance(rawValue:appearanceRaw) ?? .system).colorScheme).tint(Palette.blue)
        .onOpenURL { store.openDeepLink($0) } } }
}

#if DEBUG
@MainActor
private final class Phase3FixtureGPS:GPSRecording {
    let objectWillChange=ObservableObjectPublisher()
    let speedKMH:Double?=72
    let lastFix:Date?=Date()
    let status="Sanitized fixture GPS"
    var onPoint:((RoutePoint)->Void)?
    var onReady:(()->Void)?
    var onFailure:((String)->Void)?
    func requestAutomaticAuthorization() {}
    func start() { onReady?() }
    func stop() {}
}
#endif
typealias AppTab=DriveLinePhoneDestination
extension DriveLinePhoneDestination {
    var icon:String { switch self { case .today:"house.fill";case .drives:"chart.bar.xaxis";case .record:"record.circle";case .garage:"car";case .more:"ellipsis" } }
    var eyebrow:String { switch self { case .today:"Your vehicle, connected";case .drives:"Every drive, kept";case .record:"Ready when you are";case .garage:"Vehicles in your DriveLine";case .more:"Connections, transfers, and settings" } }
}
