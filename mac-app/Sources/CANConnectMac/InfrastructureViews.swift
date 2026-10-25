import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

private extension DriveLineVehicleClass {
    var title:String { switch self { case .passengerCar:return "Passenger car";case .lightTruck:return "Light truck";case .motorcycle:return "Motorcycle";case .heavyTruck:return "Heavy truck";case .van:return "Van";case .other:return "Other" } }
}
private extension DriveLineUnitSystem {
    var title:String { switch self { case .metric:return "Metric";case .usCustomary:return "US customary";case .imperial:return "Imperial" } }
}
private extension DriveLineGPSPreference {
    var title:String { switch self { case .automatic:return "Automatic";case .phone:return "iPhone";case .imported:return "Imported";case .unavailable:return "Unavailable" } }
}
private extension DriveLineVehicleSource {
    var title:String { switch self { case .phoneGPS:return "iPhone GPS";case .obdScanner:return "OBD scanner";case .importedArchive:return "Imports";case .manual:return "Manual" } }
}

struct GarageView:View {
    @EnvironmentObject var store:AppStore
    @State private var editing:Vehicle?
    @State private var detail:Vehicle?
    @State private var adding = false
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Vehicle profiles are independent. Import recordings into the selected profile.").font(.system(size:12)).foregroundStyle(Theme.muted);Spacer();Button("Add vehicle",systemImage:"plus") { adding = true } }
            if store.state.vehicles.isEmpty { EmptyPanel(title:"Welcome to DriveLine",message:"Add your first vehicle, then import a recording. The garage supports cars, bikes, and trucks.") }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:270))],spacing:14) {
                ForEach(store.state.vehicles.filter{!$0.isArchived}) { vehicle in vehicleCard(vehicle) }
            }
            if store.state.vehicles.contains(where:\.isArchived) { Text("Archived vehicles").font(.headline);LazyVGrid(columns:[GridItem(.adaptive(minimum:270))],spacing:14) { ForEach(store.state.vehicles.filter(\.isArchived)) { vehicle in vehicleCard(vehicle) } } }
            HStack { Button("Load clearly labeled demo data") { store.loadDemo() };if store.state.trips.contains(where:{$0.isDemo}) { Button("Remove demo data") { store.removeDemo() } };Spacer() }.font(.system(size:11))
        }.sheet(isPresented:$adding) { VehicleEditor(vehicle:Vehicle(name:"")) }.sheet(item:$editing) { vehicle in VehicleEditor(vehicle:vehicle) }
            .sheet(item:$detail) { VehicleDetailView(vehicle:$0) }
    }
    @ViewBuilder private func vehicleCard(_ vehicle:Vehicle)->some View {
        let trips=store.state.trips.filter{$0.vehicleID==vehicle.id && !$0.isDemo}
        let fills=store.state.fuelEntries.filter{$0.vehicleID==vehicle.id && !$0.isDemo}
        let imports=store.state.receipts.filter{$0.vehicleID==vehicle.id}
        let pending=imports.filter{[.queued,.processing,.failed].contains($0.status)}
        Panel(title:vehicle.name,icon:store.state.selectedVehicleID==vehicle.id ? "checkmark.circle.fill":vehicle.isArchived ? "archivebox":"car") {
            VStack(alignment:.leading,spacing:10) {
                Text([vehicle.year,vehicle.make,vehicle.model].filter{!$0.isEmpty}.joined(separator:" ")).font(.system(size:12)).foregroundStyle(Theme.muted)
                KeyValue(label:"Class / fuel",value:"\(vehicle.vehicleClass.title) · \(vehicle.fuelType)")
                KeyValue(label:"VIN",value:vehicle.vin.isEmpty ? "Unavailable":"Stored locally · hidden")
                KeyValue(label:"Sources",value:vehicle.configuredSources.map(\.title).joined(separator:" · "))
                KeyValue(label:"Scanner",value:vehicle.scannerHost == nil ? (trips.contains(where:{$0.source.lowercased().contains("obd")}) ? "Historical scanner source":"Unavailable") : "Configured · live unavailable on Mac")
                KeyValue(label:"Last real drive",value:trips.max(by:{$0.end<$1.end})?.end.formatted(date:.abbreviated,time:.shortened) ?? "Unavailable")
                KeyValue(label:"Data",value:"\(trips.count) drives · \(fills.count) fills")
                KeyValue(label:"Storage",value:ByteCountFormatter.string(fromByteCount:Int64(imports.reduce(0){$0+$1.byteCount}),countStyle:.file))
                KeyValue(label:"Import queue",value:pending.isEmpty ? "Clear":"\(pending.count) queued / failed")
                HStack {
                    if vehicle.isArchived { Button("Restore") { store.perform { try store.setVehicleArchived(vehicle.id,archived:false) } } }
                    else { Button(store.state.selectedVehicleID==vehicle.id ? "Current vehicle":"Select vehicle") { store.selectVehicle(vehicle.id) }.disabled(store.state.selectedVehicleID==vehicle.id) }
                    Spacer();Button("Details") { detail=vehicle };Button("Edit") { editing=vehicle }
                }
            }.padding(14)
        }.accessibilityIdentifier("mac.garage.vehicle.\(vehicle.id.uuidString)")
    }
}
struct VehicleEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @State var vehicle:Vehicle
    @State private var stage=0
    @State private var scannerHost = ""
    @State private var scannerPort = "35000"
    @State private var usesGPS=true
    @State private var usesScanner=false
    @State private var usesImports=true
    @State private var detecting = false
    @State private var detectionMessage = ""
    @State private var detected:DriveLineVINResult?
    @State private var identity:ScannerVINReader.Identity?
    private let originalID:UUID
    init(vehicle:Vehicle) {
        _vehicle=State(initialValue:vehicle);originalID=vehicle.id
        _scannerHost=State(initialValue:vehicle.scannerHost ?? "")
        _scannerPort=State(initialValue:String(vehicle.scannerPort ?? 35000))
        _usesGPS=State(initialValue:vehicle.configuredSources.contains(.phoneGPS) || vehicle.name.isEmpty)
        _usesScanner=State(initialValue:vehicle.configuredSources.contains(.obdScanner))
        _usesImports=State(initialValue:vehicle.configuredSources.contains(.importedArchive) || vehicle.name.isEmpty)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(vehicle.name.isEmpty ? "Add a vehicle":"Edit vehicle").font(.title2)
            Picker("Stage",selection:$stage) { Text("1 · Vehicle").tag(0);Text("2 · Scanner").tag(1);Text("3 · Identify").tag(2);Text("4 · Finish").tag(3) }.pickerStyle(.segmented).accessibilityIdentifier("mac.onboarding.stage")
            Form { if stage==0 {
                TextField("Vehicle name",text:$vehicle.name).accessibilityLabel("Vehicle name")
                HStack { TextField("Year",text:$vehicle.year).accessibilityLabel("Year");TextField("Make",text:$vehicle.make).accessibilityLabel("Make") }
                TextField("Model",text:$vehicle.model).accessibilityLabel("Model")
                TextField("Notes",text:$vehicle.notes).accessibilityLabel("Notes")
                Picker("Vehicle class",selection:$vehicle.vehicleClass) { ForEach(DriveLineVehicleClass.allCases,id:\.self) { Text($0.title).tag($0) } }
                TextField("Fuel / power",text:$vehicle.fuelType)
                Picker("Preferred units",selection:$vehicle.preferredUnits) { ForEach(DriveLineUnitSystem.allCases,id:\.self) { Text($0.title).tag($0) } }
            } else if stage==1 {
                Toggle("iPhone GPS · supported now",isOn:$usesGPS)
                Toggle("Wi-Fi/TCP ELM scanner · supported now",isOn:$usesScanner)
                Toggle("Imported recordings · supported now",isOn:$usesImports)
                Text("OBDLink MX+ live recording is configured on iPhone. External CAN recorder, USB/BLE scanner, and external GPS are planned but unavailable on Mac.").font(.system(size:11)).foregroundStyle(Theme.muted)
                Picker("Preferred GPS",selection:$vehicle.preferredGPS) { ForEach(DriveLineGPSPreference.allCases,id:\.self) { Text($0.title).tag($0) } }
                if usesScanner { HStack { TextField("Private scanner address",text:$scannerHost);TextField("Port",text:$scannerPort).frame(width:90) } }
            } else if stage==2 {
                TextField("VIN (optional)",text:$vehicle.vin).accessibilityLabel("VIN (optional)")
                Text("Read-only Mode 09. All decoding is local; DriveLine does not send the VIN to an internet service.").font(.system(size:11)).foregroundStyle(Theme.muted)
                HStack { Button("Validate locally") { validateVIN() }.disabled(vehicle.vin.isEmpty);if usesScanner { Button(detecting ? "Reading…":"Read VIN from scanner") { detect() }.disabled(detecting) } }
                if let detected {
                    Text("VIN received and hidden from evidence captures.").font(.system(size:11)).foregroundStyle(Theme.green)
                    if let year=detected.suggestedModelYear { HStack { Text("Entered year: \(vehicle.year.isEmpty ? "Unavailable":vehicle.year) · Detected year: \(year)");Button("Accept \(year)") { vehicle.year=String(year) };Button("Keep entered") {} } }
                    else if detected.modelYearIsAmbiguous { Text("Ambiguous model-year cycle: \(detected.candidateModelYears.map(String.init).joined(separator:", ")). No suggestion applied.") }
                    if let make=detected.manufacturer { HStack { Text("Detected manufacturer: \(make)");Button("Use suggestion") { vehicle.make=make } } }
                    if let identity { KeyValue(label:"Source",value:"Scanner · Mode 09");KeyValue(label:"Responding ECU",value:identity.respondingAddress ?? "Unavailable");KeyValue(label:"Protocol",value:identity.protocolName);KeyValue(label:"Observed",value:identity.observedAt.formatted(date:.abbreviated,time:.standard)) }
                }
                if !detectionMessage.isEmpty { Text(detectionMessage).font(.system(size:11)).foregroundStyle(Theme.muted) }
            } else {
                KeyValue(label:"Stable vehicle UUID",value:String(originalID.uuidString.prefix(8))+"…")
                KeyValue(label:"Vehicle",value:[vehicle.year,vehicle.make,vehicle.model].filter{!$0.isEmpty}.joined(separator:" "))
                KeyValue(label:"Sources",value:configuredSources.map(\.title).joined(separator:" · "))
                KeyValue(label:"Scanner",value:usesScanner ? "Configured · disconnected":"Unavailable")
                KeyValue(label:"VIN",value:vehicle.vin.isEmpty ? "Unavailable":"Stored locally · hidden")
                Text("Saving is atomic. Existing drives, fills, receipts, imports, annotations, preferences, originals and transfer payloads stay attached to this UUID.").font(.system(size:11)).foregroundStyle(Theme.muted)
            } }.textFieldStyle(.roundedBorder)
            HStack { Button("Cancel") { dismiss() };Spacer();if stage>0 { Button("Back") { stage-=1 } };if stage<3 { Button("Continue") { prepare();stage+=1 }.buttonStyle(.borderedProminent).disabled(vehicle.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) } else { Button("Save vehicle") { save() }.buttonStyle(.borderedProminent) } }
        }.padding(24).frame(width:680).frame(minHeight:520)
    }
    var configuredSources:[DriveLineVehicleSource] { [.manual]+(usesGPS ? [.phoneGPS]:[])+(usesScanner ? [.obdScanner]:[])+(usesImports ? [.importedArchive]:[]) }
    func prepare() { vehicle.id=originalID;vehicle.configuredSources=configuredSources;if usesScanner,let port=UInt16(scannerPort) { vehicle.scannerHost=scannerHost.trimmingCharacters(in:.whitespacesAndNewlines);vehicle.scannerPort=port } else if !usesScanner { vehicle.scannerHost=nil;vehicle.scannerPort=nil } }
    func validateVIN() { do { detected=try DriveLineVINDecoder.decode(vehicle.vin,enteredModelYear:Int(vehicle.year));vehicle.vin=detected!.normalizedVIN;detectionMessage="VIN validated locally. Review suggestions before saving." } catch { detected=nil;detectionMessage=error.localizedDescription } }
    func detect() {
        guard let port = UInt16(scannerPort),port>0 else { detectionMessage = "Enter a valid scanner port.";return }
        detecting = true;detectionMessage = "Connecting to the scanner for a read-only Mode 09 VIN request…"
        Task {
            do { let value=try await ScannerVINReader.identify(host:scannerHost,port:port);identity=value;vehicle.vin=value.vin;vehicle.identification=DriveLineVehicleIdentityObservation(source:"Read-only Mode 09 VIN",respondingAddress:value.respondingAddress,protocolName:value.protocolName,observedAt:value.observedAt);validateVIN() }
            catch { detectionMessage = error.localizedDescription }
            detecting = false
        }
    }
    func save() { prepare();do { try store.saveVehicle(vehicle);dismiss() } catch { detectionMessage=error.localizedDescription } }
}
struct VehicleDetailView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    let vehicle:Vehicle
    var trips:[Trip] { store.state.trips.filter{$0.vehicleID==vehicle.id && !$0.isDemo} }
    var fills:[FuelEntry] { store.state.fuelEntries.filter{$0.vehicleID==vehicle.id && !$0.isDemo} }
    var body:some View { VStack(alignment:.leading,spacing:14) {
        HStack { Text(vehicle.name).font(.title2);Spacer();Button("Done") { dismiss() } }
        Form {
            Section("Identity") { KeyValue(label:"Stable UUID",value:vehicle.id.uuidString);KeyValue(label:"Vehicle",value:[vehicle.year,vehicle.make,vehicle.model].filter{!$0.isEmpty}.joined(separator:" "));KeyValue(label:"VIN",value:vehicle.vin.isEmpty ? "Unavailable":"Stored locally · hidden") }
            Section("Recording sources") { KeyValue(label:"Configured",value:vehicle.configuredSources.map(\.title).joined(separator:" · "));KeyValue(label:"Preferred GPS",value:vehicle.preferredGPS.title) }
            Section("Scanner") { KeyValue(label:"Configuration",value:vehicle.scannerHost == nil ? "Unavailable":"Configured · live unavailable on Mac");KeyValue(label:"Imported evidence",value:trips.contains(where:{$0.source.lowercased().contains("obd")}) ? "Historical scanner source":"Unavailable") }
            Section("Storage and transfer") { KeyValue(label:"Data",value:"\(trips.count) real drives · \(fills.count) fills");KeyValue(label:"Imports",value:"\(store.state.receipts.filter{$0.vehicleID==vehicle.id}.count)") }
            Section("Capabilities") { Text("Mac analysis and import are available. Live scanner state is unavailable on Mac. iPhone recording requires per-vehicle scanner configuration and validation.") }
        }
        HStack { Button("Drives") { store.selectVehicle(vehicle.id);store.page = .drives;dismiss() };Button("Fuel") { store.selectVehicle(vehicle.id);store.page = .fuel;dismiss() };Button("Signals") { store.selectVehicle(vehicle.id);store.page = .signals;dismiss() };Spacer();if vehicle.isArchived { Button("Unarchive") { store.perform { try store.setVehicleArchived(vehicle.id,archived:false) };dismiss() } } else { Button("Archive") { store.perform { try store.setVehicleArchived(vehicle.id,archived:true) };dismiss() } };Button("Delete empty profile",role:.destructive) { store.perform { try store.deleteEmptyVehicle(vehicle.id) };dismiss() }.disabled(!trips.isEmpty || !fills.isEmpty || store.state.receipts.contains(where:{$0.vehicleID==vehicle.id})) }
    }.padding(24).frame(width:720).frame(minHeight:580) }
}
struct ImportsView:View {
    @EnvironmentObject var store:AppStore
    @State private var targeted = false
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top,spacing:14) {
                Panel(title:"Bring your recordings home",icon:"square.and.arrow.down") {
                    VStack(spacing:12) {
                        Image(systemName:"folder.badge.plus").font(.system(size:32)).foregroundStyle(Theme.blue)
                        Text("Drop a recording here, or choose files")
                        Text("CSV · JSON · webCAN · candump · Pelican .scanlogs / ZIP").font(.system(size:11)).foregroundStyle(Theme.muted)
                        Button("Choose recordings…") { store.importFiles() }.buttonStyle(.borderedProminent)
                        Text("Import target: "+(store.selectedVehicle?.name ?? "Select a vehicle first")).font(.system(size:11))
                    }.padding(28).frame(maxWidth:.infinity).background(targeted ? Theme.blue.opacity(0.15):Color.clear)
                    .onDrop(of:[UTType.fileURL],isTargeted:$targeted) { providers in
                        guard let vehicleID = store.state.selectedVehicleID else { store.notice = "Select a vehicle first.";return false }
                        for provider in providers {
                            _ = provider.loadObject(ofClass:URL.self) { url,_ in guard let url = url else { return };Task { @MainActor in store.perform { _ = try store.enqueue(url,vehicleID:vehicleID) };await store.processPending() } }
                        };return true
                    }
                }
                Panel(title:"Transfer receipts",icon:"checkmark.shield") {
                    VStack(alignment:.leading,spacing:16) {
                        Text("Copied → queued → processing → processed").font(.system(size:12,weight:.medium))
                        Text("The original is preserved before a receipt is issued. Identical bytes imported into the same vehicle reuse the existing receipt.").font(.system(size:12)).foregroundStyle(Theme.muted)
                        Text("Companions can submit JSON recordings to the local API, then poll their receipt. ZIP and diagnostic imports currently use the Mac file picker.").font(.system(size:11)).foregroundStyle(Theme.muted)
                    }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
                }
            }
            Panel(title:"Import queue · \(store.receiptList.count) recordings") {
                HStack { Label(store.processing ? "Processing":"Idle",systemImage:store.processing ? "gearshape.2":"checkmark.circle");Spacer();Button(store.ingestionPaused ? "Resume processing":"Pause processing") { store.togglePause() } }.font(.system(size:12)).padding(12)
                if store.receiptList.isEmpty { EmptyPanel(title:"No recordings imported yet",message:"Choose a vehicle, then add your first log. Failed formats produce an error receipt and keep the original.") }
                ForEach(store.receiptList) { receipt in
                    Divider().overlay(Theme.line)
                    VStack(alignment:.leading,spacing:8) {
                        HStack { Text(receipt.originalName).font(.system(size:12,weight:.medium));Spacer();StatusPill(state:receipt.semanticState,text:receipt.statusTitle);if receipt.status == .failed { Button("Retry import") { store.retry(receipt.id) } } }
                        Text(receipt.message).font(.system(size:11)).foregroundStyle(receipt.status == .failed ? Color.orange:Theme.muted).textSelection(.enabled)
                        Text("Original preserved · \(receipt.archiveName)").font(.system(size:10)).foregroundStyle(Theme.secondaryText)
                        HStack { Text(store.state.vehicles.first(where:{$0.id==receipt.vehicleID})?.name ?? "Unknown vehicle");Text(ByteCountFormatter.string(fromByteCount:Int64(receipt.byteCount),countStyle:.file));Spacer();Text(receipt.createdAt.formatted(date:.abbreviated,time:.shortened)) }.font(.system(size:10)).foregroundStyle(Theme.muted)
                    }.padding(13)
                }
            }
        }
    }
}
struct ServerView:View {
    @EnvironmentObject var store:AppStore
    @State private var port = "8765"
    @State private var allowLAN = false
    @State private var loginStatus = ""
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { StatusPill(state:store.serverSemanticState,text:store.serverStatusTitle);Spacer();Button(store.serverStatus=="Listening" ? "Stop server":"Start server") { if store.serverStatus=="Listening" { store.stopServer() } else if apply() { store.startServer() } } }.font(.system(size:13))
            HStack(alignment:.top,spacing:14) {
                VStack(spacing:14) {
                    Panel(title:"Companion API") {
                        VStack(alignment:.leading,spacing:14) {
                            Text("Authenticated HTTP · schema v1").font(.system(size:13,weight:.medium))
                            HStack { TextField("Port",text:$port).frame(width:120);Toggle("Allow trusted local network",isOn:$allowLAN) }.font(.system(size:12))
                            Text(allowLAN ? "LAN endpoint: use this Mac's local IP with port \(port). Internet access and TLS are not configured.":"Loopback only: http://127.0.0.1:\(port)").font(.system(size:11)).foregroundStyle(Theme.muted).textSelection(.enabled)
                            HStack { Button("Apply settings") { _ = apply() };Button("Copy pairing token") { store.copyToken() } }
                            Text("Keep the pairing token private. The app stores it in Keychain; it is not part of library backups.").font(.system(size:11)).foregroundStyle(Theme.muted)
                        }.padding(16)
                    }
                    Panel(title:"Processing") {
                        VStack(spacing:14) { KeyValue(label:"Queue",value:"\(store.state.receipts.filter{$0.status == .queued}.count) waiting");KeyValue(label:"Worker",value:store.processing ? "Processing":store.ingestionPaused ? "Paused":"Ready");KeyValue(label:"Completed",value:String(store.state.receipts.filter{$0.status == .processed}.count));Button(store.ingestionPaused ? "Resume ingestion":"Pause ingestion") { store.togglePause() }.frame(maxWidth:.infinity,alignment:.leading) }.padding(16)
                    }
                }
                VStack(spacing:14) {
                    Panel(title:"Storage & backup") {
                        VStack(alignment:.leading,spacing:14) {
                            KeyValue(label:"Original recordings",value:ByteCountFormatter.string(fromByteCount:Int64(store.state.receipts.reduce(0){$0+$1.byteCount}),countStyle:.file))
                            KeyValue(label:"Library manifest",value:manifestSize)
                            KeyValue(label:"Recorded samples",value:String(store.state.trips.reduce(0){$0+$1.samples.count}))
                            Text("Originals are retained until you manage the library. Automatic 5,000 km raw-data expiry is not enabled in this release.").font(.system(size:11)).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
                            HStack { Button("Open data folder") { store.openLibrary() };Button("Back up library…") { store.backup() } }
                        }.padding(16)
                    }
                    Panel(title:"Mac lifecycle") {
                        VStack(alignment:.leading,spacing:14) {
                            HStack { StatusPill(state:.active,text:"App active");StatusPill(state:store.ingestionPaused ? .waiting:.active,text:store.ingestionPaused ? "Ingestion paused":"Ingestion active") }
                            Text("Closing the main window keeps the current server and ingestion worker running only while the DriveLine app remains open. Quitting stops the listener; no daemon is claimed.").font(.system(size:12)).foregroundStyle(Theme.muted)
                            Button("Enable start at login") { do { try SMAppService.mainApp.register();loginStatus = "Registration requested. Check System Settings → General → Login Items." } catch { loginStatus = error.localizedDescription } }
                            Button("Disable start at login") { do { try SMAppService.mainApp.unregister();loginStatus = "Start at login disabled." } catch { loginStatus = error.localizedDescription } }
                            if !loginStatus.isEmpty { Text(loginStatus).font(.system(size:11)).foregroundStyle(Theme.muted) }
                            Text("Launch-at-login requires a locally signed app in a stable location. This is separate from an always-on system daemon.").font(.system(size:11)).foregroundStyle(Theme.muted)
                        }.padding(16)
                    }
                }
            }
        }.onAppear { port = String(store.state.serverPort);allowLAN = store.state.allowLAN }
    }
    var manifestSize:String { let size = (try? store.repository?.manifest.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0;return ByteCountFormatter.string(fromByteCount:Int64(size),countStyle:.file) }
    func apply() -> Bool { guard let port = UInt16(port),port>0 else { store.error = "Use a port from 1 to 65535.";return false };store.configureServer(port:port,lan:allowLAN);return true }
}
