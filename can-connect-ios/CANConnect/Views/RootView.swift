import SwiftUI
import UniformTypeIdentifiers
import Combine

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var settings = false
    @State private var importFile = false
    var body: some View {
        VStack(spacing:12) {
            HStack { Text("DriveLine").font(.system(size:12, weight:.medium)).tracking(2)
                Spacer()
                Menu {
                    ForEach(store.state.vehicles) { vehicle in Button(vehicle.title) { do { try store.chooseVehicle(vehicle.id) } catch { store.error = error.localizedDescription } }.accessibilityIdentifier(vehicle.isSample ? "garage.select.sample" : "garage.select.\(vehicle.id.uuidString)") }
                    Divider()
                    Button("Add a vehicle",systemImage:"plus") { store.vehicleSetupPresented = true }
                    Button("Manage vehicles",systemImage:"car.2") { store.garagePresented = true }
                } label: { HStack(spacing:5) { Image(systemName:store.activeVehicle?.kind.icon ?? "car.side"); Text(store.activeVehicle?.title ?? "Add vehicle").lineLimit(1).minimumScaleFactor(0.7) }.font(.system(size:10)).foregroundStyle(Palette.blue).frame(maxWidth:120,minHeight:30).contentShape(Rectangle()) }.disabled(store.recording || store.pendingGPS).accessibilityLabel("Choose vehicle")
                Button { settings = true } label: { Image(systemName:"slider.horizontal.3").frame(width:36,height:30) }.foregroundStyle(Palette.muted).accessibilityLabel("App settings")
            }
            HStack(alignment:.bottom) {
                VStack(alignment:.leading, spacing:5) { Eyebrow(text:store.selectedTab.eyebrow); Text(store.selectedTab.title).font(.system(size:28, weight:.regular)) }
                Spacer()
                if store.recording { Button { store.selectedTab = .live } label: { Label(store.timerText, systemImage:"record.circle.fill").font(.system(size:11)).foregroundStyle(Palette.red) }.accessibilityLabel("Recording. Open Live to finish") }
                else if store.selectedTab == .trips {
                    Menu { Button("Record with iPhone GPS", systemImage:"location") { store.source = .phoneGPS; store.selectedTab = .live }; Button("Import JSON recording", systemImage:"square.and.arrow.down") { importFile = true }; Button("Add sample recording", systemImage:"play.rectangle") { store.addSample() } } label: { Image(systemName:"plus").frame(width:40,height:40).background(Palette.surface, in:Circle()) }.accessibilityLabel("Add recording")
                } else { Text(store.selectedTab == .live && store.source == .demo ? "Demo" : "On iPhone").font(.system(size:10)).foregroundStyle(Palette.muted).padding(.horizontal,11).padding(.vertical,7).background(Palette.surface, in:Capsule()) }
            }
            Group { switch store.selectedTab {
            case .overview: OverviewView(page:$store.overviewPage)
            case .trips: TripsView(filter:$store.tripFilter, page:$store.tripPage)
            case .live: LiveView(page:$store.livePage)
            case .vehicle: VehicleView(page:$store.vehiclePage)
            case .connect: ConnectView(page:$store.connectPage)
            } }.frame(maxWidth:.infinity, maxHeight:.infinity)
        }
        .padding(.horizontal,18).padding(.top,8).padding(.bottom,8)
        .background(Palette.background.ignoresSafeArea()).foregroundStyle(Palette.text)
        .safeAreaInset(edge:.bottom, spacing:0) { tabBar }
        .overlay(alignment:.bottom) { if let toast = store.toast { Text(toast).font(.system(size:12)).padding(12).background(Palette.raised, in:Capsule()).padding(.bottom,10).allowsHitTesting(false) } }
        .sheet(isPresented:$settings) { SettingsView() }
        .sheet(isPresented:$store.garagePresented) { GarageView() }
        .fullScreenCover(isPresented:Binding(get:{!store.state.onboardingCompleted || store.vehicleSetupPresented},set:{store.vehicleSetupPresented = $0})) { VehicleSetupView() }
        .fileImporter(isPresented:$importFile, allowedContentTypes:[.json]) { result in importRecording(result, store:store) }
        .alert("DriveLine", isPresented:Binding(get:{ store.error != nil }, set:{ if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var tabBar: some View {
        HStack(spacing:0) { ForEach(AppTab.allCases) { tab in
            Button { store.selectedTab = tab } label: { VStack(spacing:6) { Image(systemName:tab.icon).font(.system(size:17)); Text(tab.title).font(.system(size:10)) }.frame(maxWidth:.infinity).frame(height:57).contentShape(Rectangle()) }
                .foregroundStyle(store.selectedTab == tab ? Palette.blue : Palette.muted)
                .accessibilityLabel(tab.title).accessibilityAddTraits(store.selectedTab == tab ? .isSelected : [])
        } }.padding(.horizontal,10).background(Color(hex:0x101722)).overlay(alignment:.top) { Rectangle().fill(Palette.border).frame(height:1) }
    }
}
@MainActor
func importRecording(_ result: Result<URL, Error>, store: AppStore) {
    do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size <= 20_000_000 else { throw AppFailure("Choose a recording under 20 MB.") }
        try store.importTrips(Data(contentsOf:url))
    } catch { store.error = error.localizedDescription }
}

#if DEBUG
/// Canvas-only sample data and services, isolated from recordings and hardware.
@MainActor
struct DriveLineCanvas: View {
    @StateObject private var store: AppStore

    init(tab: AppTab = .overview, recording: Bool = false) {
        _store = StateObject(wrappedValue:Self.makeStore(tab:tab, recording:recording))
    }

    static func makeStore(tab: AppTab = .overview, recording: Bool = false) -> AppStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriveLinePreviews/\(UUID().uuidString)/state.json")
        let store = AppStore(disk:LocalStore(url:url),
                             scanner:ScannerRecorder(makeSession:{ CanvasScanner() }),
                             activity:CanvasActivity(), gps:CanvasGPS(),
                             scannerAvailable:{ _ in false })
        store.state.onboardingCompleted = true
        store.selectedTab = tab
        if recording {
            let start = Date().addingTimeInterval(-140)
            let points = SampleData.routeCoordinates.enumerated().map { i, c in
                RoutePoint(latitude:c[0],longitude:c[1],timestamp:start.addingTimeInterval(Double(i)*20),accuracy:5,speed:18)
            }
            store.state.draft = RecordingDraft(vehicleID:store.state.selectedVehicleID,source:.demo,
                                               startedAt:start,updatedAt:Date(),distanceKM:4,route:points)
        }
        return store
    }

    var body: some View {
        RootView().environmentObject(store)
            .preferredColorScheme(.dark).tint(Palette.blue)
    }
}

@MainActor
private final class CanvasGPS: GPSRecording {
    let objectWillChange = ObservableObjectPublisher()
    var speedKMH: Double? { nil }
    var lastFix: Date? { nil }
    var status: String { "Canvas sample data · GPS disabled" }
    var onPoint: ((RoutePoint) -> Void)?
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    func requestAutomaticAuthorization() {}
    func start() { onFailure?("GPS recording is available in the app on iPhone.") }
    func stop() {}
}

@MainActor
private final class CanvasActivity: RecordingActivityManaging {
    func sync(_ snapshot: RecordingActivitySnapshot?, foreground: Bool) {}
}

@MainActor
private final class CanvasScanner: ScannerTransport {
    func open(host: String, port: UInt16) async throws -> ScannerIdentity {
        throw AppFailure("Scanner connections are disabled in Canvas previews.")
    }
    func command(_ text: String) async throws -> String {
        throw AppFailure("Scanner connections are disabled in Canvas previews.")
    }
    func disconnect() {}
}

#Preview("Overview · Sample data") { DriveLineCanvas() }
#Preview("Trips · Sample data") { DriveLineCanvas(tab:.trips) }
#Preview("Live · Sample data") { DriveLineCanvas(tab:.live) }
#Preview("Vehicle · Sample data") { DriveLineCanvas(tab:.vehicle) }
#Preview("Connect · Sample data") { DriveLineCanvas(tab:.connect) }
#endif
