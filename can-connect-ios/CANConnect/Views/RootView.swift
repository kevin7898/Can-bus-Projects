import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var settings = false
    @State private var importFile = false
    var body: some View {
        VStack(spacing:12) {
            HStack { HStack(spacing:9) { Text("CAN"); Text("/").foregroundStyle(Palette.blue); Text("CONNECT") }.font(.system(size:12, weight:.medium)).tracking(2)
                Spacer(); Button { settings = true } label: { Image(systemName:"slider.horizontal.3").frame(width:36,height:30) }.foregroundStyle(Palette.muted).accessibilityLabel("App settings")
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
            case .overview: OverviewView()
            case .trips: TripsView()
            case .live: LiveView()
            case .vehicle: VehicleView()
            case .connect: ConnectView()
            } }.frame(maxWidth:.infinity, maxHeight:.infinity)
        }
        .padding(.horizontal,18).padding(.top,8).padding(.bottom,8)
        .background(Palette.background.ignoresSafeArea()).foregroundStyle(Palette.text)
        .safeAreaInset(edge:.bottom, spacing:0) { tabBar }
        .overlay(alignment:.bottom) { if let toast = store.toast { Text(toast).font(.system(size:12)).padding(12).background(Palette.raised, in:Capsule()).padding(.bottom,10).allowsHitTesting(false) } }
        .sheet(isPresented:$settings) { SettingsView() }
        .fileImporter(isPresented:$importFile, allowedContentTypes:[.json]) { result in importRecording(result, store:store) }
        .alert("CAN / CONNECT", isPresented:Binding(get:{ store.error != nil }, set:{ if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
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
