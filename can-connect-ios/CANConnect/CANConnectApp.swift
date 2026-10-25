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
            _store = StateObject(wrappedValue:testStore)
        } else { _store = StateObject(wrappedValue:AppStore()) }
    }
    var body: some Scene { WindowGroup { RootView().environmentObject(store)
        .preferredColorScheme((DriveLineAppearance(rawValue:appearanceRaw) ?? .system).colorScheme).tint(Palette.blue)
        .onOpenURL { url in
            if url.scheme == "canconnect", url.host == "recording" { store.selectedTab = .live }
        } } }
}
enum AppTab: String, CaseIterable, Identifiable {
    case overview, trips, live, vehicle, connect
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String { switch self { case .overview: return "square.grid.2x2"; case .trips: return "point.topleft.down.to.point.bottomright.curvepath"; case .live: return "waveform.path.ecg"; case .vehicle: return "car"; case .connect: return "antenna.radiowaves.left.and.right" } }
    var eyebrow: String { switch self { case .overview: return "Your vehicle, connected"; case .trips: return "Every drive, kept"; case .live: return "In the car"; case .vehicle: return "The full picture"; case .connect: return "Your recording network" } }
}
