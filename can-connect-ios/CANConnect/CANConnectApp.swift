import SwiftUI

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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("can-connect-ui-tests/state.json")
            try? FileManager.default.removeItem(at:url.deletingLastPathComponent())
            let testStore = AppStore(disk:LocalStore(url:url))
            if !ProcessInfo.processInfo.arguments.contains("--show-onboarding") { testStore.state.onboardingCompleted = true; testStore.save() }
            if ProcessInfo.processInfo.arguments.contains("--record-tab") { testStore.selectedTab = .record }
            _store = StateObject(wrappedValue:testStore)
        } else { _store = StateObject(wrappedValue:AppStore()) }
    }
    var body: some Scene { WindowGroup { RootView().environmentObject(store)
        .preferredColorScheme((DriveLineAppearance(rawValue:appearanceRaw) ?? .system).colorScheme).tint(Palette.blue)
        .onOpenURL { store.openDeepLink($0) } } }
}
typealias AppTab=DriveLinePhoneDestination
extension DriveLinePhoneDestination {
    var icon:String { switch self { case .today:"house.fill";case .drives:"chart.bar.xaxis";case .record:"record.circle";case .garage:"car";case .more:"ellipsis" } }
    var eyebrow:String { switch self { case .today:"Your vehicle, connected";case .drives:"Every drive, kept";case .record:"Ready when you are";case .garage:"Vehicles in your DriveLine";case .more:"Connections, transfers, and settings" } }
}
