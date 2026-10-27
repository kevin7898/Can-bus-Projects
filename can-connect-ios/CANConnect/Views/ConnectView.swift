import SwiftUI
import UniformTypeIdentifiers

struct ConnectView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(DriveLineAppearance.storageKey) private var appearanceRaw=DriveLineAppearance.system.rawValue
    @Binding var page: Int
    @State private var importing = false
    @State private var exporting = false
    @State private var document = JSONDocument(data:Data())
    @State private var recorderInfo = false
    @State private var serverSetup = false
    @State private var queue = false
    @State private var vehicleData = false
    @State private var signals = false
    @State private var fuelLogbook = false
    @State private var appearance = false
    @State private var units = false
    @State private var transfers = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    sectionLabel(connectionSectionTitle)
                    VStack(spacing:0) {
                        Button { recorderInfo=true } label: {
                            destinationRow("OBD scanner",detail:store.scanner.status,icon:"cpu",state:scannerState,status:scannerStatus)
                        }.buttonStyle(.plain).accessibilityIdentifier("more.scanner")
                        rowDivider
                        Button { serverSetup=true } label: {
                            destinationRow("Mac transfer",detail:macDetail,icon:"desktopcomputer",state:serverState,status:serverStatus)
                        }.buttonStyle(.plain).accessibilityIdentifier("more.server")
                        rowDivider
                        Button { store.gps.requestAutomaticAuthorization() } label: {
                            destinationRow("iPhone GPS",detail:store.gps.status,icon:"iphone",state:gpsState,status:gpsStatus)
                        }.buttonStyle(.plain).accessibilityIdentifier("more.gps")
                    }.card()

                    sectionLabel("Fuel & data")
                    VStack(spacing:0) {
                        Button { fuelLogbook=true } label: {
                            destinationRow("Fuel logbook",detail:fuelDetail,icon:"fuelpump.fill",state:.ready,status:"\(realFillCount) fills")
                        }.buttonStyle(.plain).accessibilityIdentifier("more.fuel-logbook")
                        rowDivider
                        Button { signals=true } label: {
                            destinationRow("Signals",detail:"Recorded traces, gaps, coverage, freshness, and provenance",icon:"waveform.path.ecg")
                        }.buttonStyle(.plain).accessibilityIdentifier("more.signals")
                        rowDivider
                        Button { vehicleData=true } label: {
                            destinationRow("Vehicle data & DPF",detail:"Latest recorded engine data, fuel level, and regeneration history",icon:"gauge.with.dots.needle.50percent")
                        }.buttonStyle(.plain).accessibilityIdentifier("more.vehicle-data")
                    }.card()

                    sectionLabel("Transfers")
                    VStack(spacing:0) {
                        Button { transfers=true } label: {
                            destinationRow("Transfers & backup",detail:"Send, import, export, and choose network preferences",icon:"externaldrive",state:transferState,status:transferStatus)
                        }.buttonStyle(.plain).accessibilityIdentifier("more.transfers")
                        rowDivider
                        Button { queue=true } label: {
                            destinationRow("Transfer queue",detail:queueDetail,icon:"arrow.up.arrow.down",state:queueState,status:"\(store.state.transfers.count) items")
                        }.buttonStyle(.plain).accessibilityIdentifier("more.transfer-queue")
                    }.card()

                    sectionLabel("Preferences")
                    VStack(spacing:0) {
                        Button { units=true } label: {
                            destinationRow("Units",detail:"Pressure, distance, temperature and fuel",icon:"ruler")
                        }.buttonStyle(.plain).accessibilityIdentifier("more.units")
                        rowDivider
                        Button { appearance=true } label: {
                            destinationRow("Appearance",detail:"Use the iPhone setting or keep DriveLine in Light or Dark",icon:"circle.lefthalf.filled",status:appearanceTitle)
                        }.buttonStyle(.plain).accessibilityIdentifier("more.appearance")
                    }.card()
                    InfoNote(text:"Recordings and receipts stay on this iPhone until a paired Mac confirms processing. Vehicle profiles remain in Garage.")
                }.padding(.horizontal,1).padding(.bottom,8)
                    .frame(maxWidth:.infinity,minHeight:geometry.size.height,alignment:.top)
            }.scrollBounceBehavior(.basedOnSize)
        }.onAppear { page=0 }
        .sheet(isPresented:$units) { SheetShell(title:"Units") { UnitPreferencesPicker() } }
        .sheet(isPresented:$recorderInfo) { ScannerConnectionView() }
        .sheet(isPresented:$serverSetup) { ServerConnectionView() }
        .sheet(isPresented:$queue) { TransferQueueView() }
        .sheet(isPresented:$vehicleData) { SheetShell(title:"Vehicle data & DPF") { VehicleView(page:$store.vehiclePage).frame(minHeight:620) } }
        .sheet(isPresented:$signals) { SignalsOverviewView() }
        .sheet(isPresented:$fuelLogbook) { FuelLedgerView() }
        .sheet(isPresented:$appearance) { appearanceSheet }
        .sheet(isPresented:$transfers) { transferSheet
            .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { importRecording($0,store:store) }
            .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"DriveLine-recordings") { result in if case .failure(let error) = result { store.error=error.localizedDescription } }
        }
    }
    private var appearanceSheet:some View {
        SheetShell(title:"Appearance") {
            AppearancePreferencePicker()
            InfoNote(text:"System follows this iPhone. Light and Dark remain fixed until changed here.")
        }
    }
    private var transferSheet:some View {
        SheetShell(title:"Transfers & backup") {
            VStack(alignment:.leading,spacing:13) { HStack { Image(systemName:"externaldrive").foregroundStyle(Palette.blue); Text("Kept on this iPhone").font(.system(size:16)) }; Text("\(store.state.trips.count) recordings · \(store.state.transfers.filter {$0.status == .complete}.count) processed by Mac").captionStyle(); InfoNote(text:"Originals remain on the phone. A transfer is complete when the Mac receipt confirms processing.") }.card()
            Toggle("Wi-Fi for large raw logs",isOn:Binding(get:{store.state.preferences.wifiLogs},set:{store.state.preferences.wifiLogs = $0; store.save()})).font(.system(size:13))
            Toggle("Allow cellular transfers",isOn:Binding(get:{store.state.preferences.cellularSummaries},set:{store.state.preferences.cellularSummaries = $0; store.save()})).font(.system(size:13))
            Text("Transfers run while the app is open. Wi-Fi-only takes priority. Separate summary uploads are unavailable.").captionStyle().fixedSize(horizontal:false,vertical:true)
            AppButton(title:store.transferring ? "Transferring…" : "Send / check recordings",icon:"arrow.up.circle",secondary:true) {
                do { _ = try store.queueRecordings(); Task { await store.sendQueued() } } catch { store.error = error.localizedDescription }
            }.disabled(store.transferring)
            AppButton(title:"Import recordings",icon:"square.and.arrow.down",secondary:true) { importing = true }
            AppButton(title:"Export all recordings",icon:"square.and.arrow.up") { do { document = JSONDocument(data:try store.archive(store.state.trips).encoded()); exporting = true } catch { store.error = error.localizedDescription } }
            InfoNote(text:"Mac pairing and the detailed transfer queue remain available from More.")
        }
    }
    private func sectionLabel(_ title:String)->some View {
        Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(Palette.secondaryText).padding(.top,2)
    }
    private func destinationRow(_ title:String,detail:String,icon:String,state:DriveLineSemanticState?=nil,status:String?=nil)->some View {
        HStack(spacing:13) {
            Image(systemName:icon).font(.system(size:21)).foregroundStyle(Palette.cobalt).frame(width:28)
            VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:15,weight:.semibold));Text(detail).captionStyle().multilineTextAlignment(.leading).lineLimit(3) }
            Spacer(minLength:8)
            if dynamicTypeSize.isAccessibilitySize {
                Image(systemName:"chevron.right").foregroundStyle(Palette.tertiaryText)
            } else {
                if let status { StatusPill(state:state ?? .ready,text:status) }
                Image(systemName:"chevron.right").foregroundStyle(Palette.tertiaryText)
            }
        }.foregroundStyle(Palette.primaryText).padding(.vertical,8).contentShape(Rectangle())
    }
    private var rowDivider:some View { Rectangle().fill(Palette.border).frame(height:0.5).padding(.leading,41) }
    private var connectionSectionTitle:String { scannerState == .ready && serverState == .ready && gpsState == .ready ? "Connections":"Needs attention" }
    private var scannerState:DriveLineSemanticState { store.scanner.connected ? .ready:(store.scanner.connecting ? .processing:.unavailable) }
    private var scannerStatus:String { store.scanner.connected ? "Connected":(store.scanner.connecting ? "Connecting":"Set up") }
    private var serverState:DriveLineSemanticState {
        if store.transferring { return .processing }
        if store.state.server.address.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return .unavailable }
        let value=store.serverStatus.lowercased()
        return value.contains("attention") || value.contains("failed") || value.contains("not connected") ? .stale:.ready
    }
    private var serverStatus:String { store.transferring ? "Sending":(serverState == .ready ? "Ready":(store.state.server.address.isEmpty ? "Set up":"Needs attention")) }
    private var macDetail:String { store.state.server.address.isEmpty ? "Pair a private Mac to transfer recordings and receipts":store.serverStatus }
    private var gpsState:DriveLineSemanticState {
        switch store.gps.permissionState {
        case .notDetermined:return .waiting
        case .denied,.restricted:return .unavailable
        case .available:
            let value=store.gps.status.lowercased()
            if value.contains("need") || value.contains("enable") || value.contains("disabled") || value.contains("unavailable") || value.contains("off") { return .unavailable }
            if value.contains("waiting") || value.contains("fix") || value.contains("weak") { return .waiting }
            return .ready
        }
    }
    private var gpsStatus:String { switch gpsState { case .ready:return "Ready";case .waiting:return "Waiting";default:return "Review" } }
    private var realFillCount:Int { store.vehicleFills.filter{!$0.isSample}.count }
    private var fuelDetail:String { realFillCount == 0 ? "No fill-ups recorded for this vehicle":"Review purchased fuel, receipts, cost, and full-tank economy" }
    private var queueState:DriveLineSemanticState { store.state.transfers.contains{ $0.status == .failed } ? .failed:(store.state.transfers.contains{ $0.status == .queued || $0.status == .awaitingReceipt } ? .queued:.complete) }
    private var queueDetail:String { store.state.transfers.isEmpty ? "No queued, failed, or completed transfers":"Review queued, failed, and completed transfer receipts" }
    private var transferState:DriveLineSemanticState { store.transferring ? .processing:serverState }
    private var transferStatus:String { store.transferring ? "Sending":(serverState == .ready ? "Ready":"Review") }
    private var appearanceTitle:String { (DriveLineAppearance(rawValue:appearanceRaw) ?? .system).title }
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
        UnitPreferencesPicker()
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
