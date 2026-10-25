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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("can-connect-ui-tests/state.json")
            try? FileManager.default.removeItem(at:url.deletingLastPathComponent())
            let usesPhase3Fixture=arguments.contains("--phase3-active") || arguments.contains("--phase3-degraded")
            let testStore = AppStore(disk:LocalStore(url:url),gps:usesPhase3Fixture ? Phase3FixtureGPS():nil)
            if !arguments.contains("--show-onboarding") { testStore.state.onboardingCompleted = true; testStore.save() }
            if arguments.contains("--record-tab") { testStore.selectedTab = .record }
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
