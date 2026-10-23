import SwiftUI
import UniformTypeIdentifiers

struct ConnectView: View {
    @EnvironmentObject private var store: AppStore
    @State private var page = 0
    @State private var importing = false
    @State private var exporting = false
    @State private var document = JSONDocument(data:Data())
    @State private var recorderInfo = false
    var body: some View {
        VStack(spacing:12) { PageControl(labels:["Devices","Transfers"],selection:$page)
            TabView(selection:$page) { devices.tag(0); transfers.tag(1) }.tabViewStyle(.page(indexDisplayMode:.never))
        }
        .sheet(isPresented:$recorderInfo) { SheetShell(title:"CAN recorder") { Image(systemName:"cpu").font(.system(size:36)).foregroundStyle(Palette.blue); Text("Recorder transport is the next integration.").font(.title3); InfoNote(text:"The native app can record iPhone GPS and import CAN Connect JSON recordings. Bluetooth CAN streaming and the Mac mini server need an agreed transport and API before they can connect."); AppButton(title:"Try the sample CAN dashboard") { store.source = .demo; store.selectedTab = .live; recorderInfo = false } } }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { importRecording($0,store:store) }
        .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"CANConnect-recordings") { result in if case .failure(let error) = result { store.error = error.localizedDescription } }
    }
    private var devices: some View {
        VStack(alignment:.leading,spacing:16) {
            device("This iPhone",subtitle:store.recording && store.source == .phoneGPS ? store.gps.status : "GPS recorder · ready",icon:"iphone",status:"Local",color:Palette.green)
            Button { recorderInfo = true } label: { device("CAN recorder",subtitle:"Not configured",icon:"cpu",status:"Set up",color:Palette.muted) }.buttonStyle(.plain)
            device("Mac mini M4",subtitle:"Backup server · not configured",icon:"desktopcomputer",status:"Offline",color:Palette.muted)
            InfoNote(text:"Your iPhone keeps recordings locally. Add the recorder and server transport when their connection details are ready.")
            Spacer(minLength:0)
            AppButton(title:"Use iPhone GPS",icon:"location",secondary:true) { if !store.recording { store.source = .phoneGPS }; store.selectedTab = .live }
        }.padding(.horizontal,1).padding(.top,10)
    }
    private func device(_ title: String, subtitle: String, icon: String, status: String, color: Color) -> some View {
        HStack(spacing:13) { Image(systemName:icon).font(.system(size:23)).foregroundStyle(Palette.blue).frame(width:28); VStack(alignment:.leading,spacing:7) { Text(title).font(.system(size:15)); Text(subtitle).captionStyle().lineLimit(2) }; Spacer(); Text(status).font(.system(size:10)).foregroundStyle(color) }.frame(maxWidth:.infinity).card()
    }
    private var transfers: some View {
        VStack(alignment:.leading,spacing:17) {
            VStack(alignment:.leading,spacing:13) { HStack { Image(systemName:"externaldrive").foregroundStyle(Palette.blue); Text("Kept on this iPhone").font(.system(size:16)) }; Text("\(store.state.trips.count) recordings · no server uploads").captionStyle(); InfoNote(text:"Export a copy now, or connect your server in a future build. Originals remain on the phone.") }.card()
            Toggle("Wi-Fi for large raw logs",isOn:Binding(get:{store.state.preferences.wifiLogs},set:{store.state.preferences.wifiLogs = $0; store.save()})).font(.system(size:13))
            Toggle("Cellular for summaries",isOn:Binding(get:{store.state.preferences.cellularSummaries},set:{store.state.preferences.cellularSummaries = $0; store.save()})).font(.system(size:13))
            Text("Preferences are saved for the server integration. No uploads run in this build.").captionStyle().fixedSize(horizontal:false,vertical:true)
            Spacer(minLength:0)
            AppButton(title:"Import recordings",icon:"square.and.arrow.down",secondary:true) { importing = true }
            AppButton(title:"Export all recordings",icon:"square.and.arrow.up") { do { document = JSONDocument(data:try TripArchive(trips:store.sortedTrips).encoded()); exporting = true } catch { store.error = error.localizedDescription } }
        }.padding(.horizontal,1).padding(.top,10)
    }
}
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var removeSamples = false
    var body: some View { SheetShell(title:"CAN / CONNECT") {
        Eyebrow(text:"iOS companion · Native v1.0")
        Text("The design is locked.").font(.title2)
        InfoNote(text:"Five tabs. Pages within each tab. Independent signal cards. Local recordings and fill-ups.")
        DataRow(label:"GPS recording",value:"Available")
        DataRow(label:"Live vehicle data",value:"Sample feed")
        DataRow(label:"CAN / Mac mini",value:"Not configured")
        InfoNote(text:"Start a GPS recording to request location access. While recording, the blue location indicator lets GPS continue when the phone locks. Stop recording from Live.",icon:"location")
        AppButton(title:"Remove sample history",secondary:true) { removeSamples = true }
        Text("This removes only bundled sample trips and fill-ups. Your own recordings stay on the phone.").captionStyle()
        Text("Map data: City of Nanaimo open data. Expanded route maps: Apple Maps.").captionStyle()
        Link("View project on GitHub",destination:URL(string:"https://github.com/kevin7898/Can-bus-Projects")!).font(.system(size:13))
    }.confirmationDialog("Remove sample trips and fill-ups?",isPresented:$removeSamples,titleVisibility:.visible) { Button("Remove samples",role:.destructive) { store.removeSamples() } } }
}
