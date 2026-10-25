import SwiftUI
import UniformTypeIdentifiers

struct ConnectView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var page: Int
    @State private var importing = false
    @State private var exporting = false
    @State private var document = JSONDocument(data:Data())
    @State private var recorderInfo = false
    @State private var serverSetup = false
    @State private var queue = false
    @State private var vehicleData = false
    @State private var signals = false
    var body: some View {
        VStack(spacing:12) { PageControl(labels:["Connections","Transfers","Settings"],selection:$page)
            TabView(selection:$page) { devices.tag(0); transfers.tag(1); settings.tag(2) }.tabViewStyle(.page(indexDisplayMode:.never))
        }
        .sheet(isPresented:$recorderInfo) { ScannerConnectionView() }
        .sheet(isPresented:$serverSetup) { ServerConnectionView() }
        .sheet(isPresented:$queue) { TransferQueueView() }
        .sheet(isPresented:$vehicleData) { SheetShell(title:"Vehicle data and fuel") { VehicleView(page:$store.vehiclePage).frame(minHeight:620) } }
        .sheet(isPresented:$signals) { SignalsOverviewView() }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { importRecording($0,store:store) }
        .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"DriveLine-recordings") { result in if case .failure(let error) = result { store.error = error.localizedDescription } }
    }
    private var devices: some View {
        VStack(alignment:.leading,spacing:16) {
            Button { store.gps.requestAutomaticAuthorization() } label: { device("This iPhone",subtitle:store.gps.status,icon:"iphone",status:"Local",color:Palette.green) }.buttonStyle(.plain).accessibilityIdentifier("gps.authorization")
            Button { recorderInfo = true } label: { device("CAN recorder",subtitle:store.scanner.status,icon:"cpu",status:store.scanner.connected ? "Online" : "Set up",color:store.scanner.connected ? Palette.green : Palette.muted) }.buttonStyle(.plain)
            Button { serverSetup = true } label: { device("Mac mini M4",subtitle:store.serverStatus,icon:"desktopcomputer",status:"Set up",color:Palette.muted) }.buttonStyle(.plain)
            InfoNote(text:"Record GPS or connect an OBDLink MX+ or Wi-Fi ELM327 scanner. Pair your private Mac server to transfer saved recordings.")
            Spacer(minLength:0)
            AppButton(title:"Use iPhone GPS",icon:"location",secondary:true) { if !store.recording { store.source = .phoneGPS }; store.selectedTab = .record }
        }.padding(.horizontal,1).padding(.top,10)
    }
    private func device(_ title: String, subtitle: String, icon: String, status: String, color: Color) -> some View {
        HStack(spacing:13) { Image(systemName:icon).font(.system(size:23)).foregroundStyle(Palette.blue).frame(width:28); VStack(alignment:.leading,spacing:7) { Text(title).font(.system(size:15)); Text(subtitle).captionStyle().lineLimit(2) }; Spacer(); Text(status).font(.system(size:10)).foregroundStyle(color) }.frame(maxWidth:.infinity).card()
    }
    private var transfers: some View {
        VStack(alignment:.leading,spacing:12) {
            VStack(alignment:.leading,spacing:13) { HStack { Image(systemName:"externaldrive").foregroundStyle(Palette.blue); Text("Kept on this iPhone").font(.system(size:16)) }; Text("\(store.state.trips.count) recordings · \(store.state.transfers.filter {$0.status == .complete}.count) processed by Mac").captionStyle(); InfoNote(text:"Originals remain on the phone. A transfer is complete when the Mac receipt confirms processing.") }.card()
            Toggle("Wi-Fi for large raw logs",isOn:Binding(get:{store.state.preferences.wifiLogs},set:{store.state.preferences.wifiLogs = $0; store.save()})).font(.system(size:13))
            Toggle("Allow cellular transfers",isOn:Binding(get:{store.state.preferences.cellularSummaries},set:{store.state.preferences.cellularSummaries = $0; store.save()})).font(.system(size:13))
            Text("Transfers run while the app is open. Wi-Fi-only takes priority. Separate summary uploads are unavailable.").captionStyle().fixedSize(horizontal:false,vertical:true)
            HStack { Button("Server setup") { serverSetup = true }; Spacer(); Button("Transfer queue (\(store.state.transfers.count))") { queue = true } }.font(.system(size:12))
            AppButton(title:store.transferring ? "Transferring…" : "Send / check recordings",icon:"arrow.up.circle",secondary:true) {
                do { _ = try store.queueRecordings(); Task { await store.sendQueued() } } catch { store.error = error.localizedDescription }
            }.disabled(store.transferring)
            Spacer(minLength:0)
            AppButton(title:"Import recordings",icon:"square.and.arrow.down",secondary:true) { importing = true }
            AppButton(title:"Export all recordings",icon:"square.and.arrow.up") { do { document = JSONDocument(data:try store.archive(store.state.trips).encoded()); exporting = true } catch { store.error = error.localizedDescription } }
        }.padding(.horizontal,1).padding(.top,10)
    }
    private var settings:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                VStack(alignment:.leading,spacing:10) { Text("Appearance").font(.system(size:16,weight:.semibold));AppearancePreferencePicker();Text("System follows this iPhone. Light and Dark remain fixed until changed here.").captionStyle() }.card()
                Button { store.selectedTab = .garage } label:{ settingRow("Manage vehicles",detail:"Select, add, and review vehicle profiles",icon:"car.2") }.buttonStyle(.plain).accessibilityIdentifier("more.garage")
                Button { vehicleData=true } label:{ settingRow("Vehicle data and fuel",detail:"Fuel logbook, recorded signals, and DPF history",icon:"gauge.with.dots.needle.50percent") }.buttonStyle(.plain).accessibilityIdentifier("more.vehicle-data")
                Button { signals=true } label:{ settingRow("Signals",detail:"Grouped recorded traces, gaps, coverage, freshness, and provenance",icon:"waveform.path.ecg") }.buttonStyle(.plain).accessibilityIdentifier("more.signals")
                Button { serverSetup=true } label:{ settingRow("Mac server pairing",detail:store.serverStatus,icon:"desktopcomputer") }.buttonStyle(.plain).accessibilityIdentifier("more.server")
                Button { queue=true } label:{ settingRow("Transfer queue",detail:"\(store.state.transfers.count) queued or completed items",icon:"arrow.up.arrow.down") }.buttonStyle(.plain).accessibilityIdentifier("more.transfer-queue")
                InfoNote(text:"Connections and Transfers remain available above. Originals stay on this iPhone until a Mac processing receipt is confirmed.")
            }.padding(.horizontal,1).padding(.top,4)
        }
    }
    private func settingRow(_ title:String,detail:String,icon:String)->some View {
        HStack(spacing:13) { Image(systemName:icon).font(.system(size:21)).foregroundStyle(Palette.cobalt).frame(width:28);VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:15,weight:.semibold));Text(detail).captionStyle().multilineTextAlignment(.leading) };Spacer();Image(systemName:"chevron.right").foregroundStyle(Palette.tertiaryText) }.foregroundStyle(Palette.primaryText).card()
    }
}
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var garage = false
    @State private var removeSamples = false
    var body: some View { SheetShell(title:"DriveLine") {
        Eyebrow(text:"iOS companion · Native v1.0")
        Text("The design is locked.").font(.title2)
        InfoNote(text:"Five tabs. Pages within each tab. Independent signal cards. Local recordings and fill-ups.")
        AppearancePreferencePicker()
        AppButton(title:"Manage vehicles",icon:"car.2",secondary:true) { garage = true }
        DataRow(label:"GPS recording",value:"Available")
        DataRow(label:"Live vehicle data",value:store.scanner.connected ? store.scannerTitle : "GPS / sample / OBD")
        DataRow(label:"Mac server",value:store.serverStatus)
        InfoNote(text:"For trips that start while locked, tap This iPhone in Connect and allow Always location access with Precise Location on. While Using supports trips started with DriveLine open. GPS stops when recording finishes.",icon:"location")
        AppButton(title:"Remove sample history",secondary:true) { removeSamples = true }
        Text("This removes only bundled sample trips and fill-ups. Your own recordings stay on the phone.").captionStyle()
        Text("Map data: City of Nanaimo open data. Expanded route maps: Apple Maps.").captionStyle()
        Link("View project on GitHub",destination:URL(string:"https://github.com/kevin7898/Can-bus-Projects")!).font(.system(size:13))
    }.sheet(isPresented:$garage) { GarageView() }.confirmationDialog("Remove sample trips and fill-ups?",isPresented:$removeSamples,titleVisibility:.visible) { Button("Remove samples",role:.destructive) { store.removeSamples() } } }
}

#if DEBUG
#Preview("More · Sample data") { DriveLineCanvas(tab:.more) }
#endif
