import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct GarageView:View {
    @EnvironmentObject var store:AppStore
    @State private var editing:Vehicle?
    @State private var adding = false
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Vehicle profiles are independent. Import recordings into the selected profile.").font(.system(size:12)).foregroundStyle(Theme.muted);Spacer();Button("Add vehicle",systemImage:"plus") { adding = true } }
            if store.state.vehicles.isEmpty { EmptyPanel(title:"Welcome to CAN / CONNECT",message:"Add your first vehicle, then import a recording. The garage supports cars, bikes, and trucks.") }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:270))],spacing:14) {
                ForEach(store.state.vehicles) { vehicle in
                    Panel(title:vehicle.name,icon:store.state.selectedVehicleID==vehicle.id ? "checkmark.circle.fill":"car") {
                        VStack(alignment:.leading,spacing:14) {
                            Image(systemName:"car.side").font(.system(size:52)).foregroundStyle(Theme.blue).frame(maxWidth:.infinity).padding(.vertical,16)
                            Text([vehicle.year,vehicle.make,vehicle.model].filter{!$0.isEmpty}.joined(separator:" ")).font(.system(size:12)).foregroundStyle(Theme.muted)
                            KeyValue(label:"Recordings",value:String(store.state.trips.filter{$0.vehicleID==vehicle.id}.count))
                            if !vehicle.vin.isEmpty { KeyValue(label:"VIN",value:vehicle.vin) }
                            HStack { Button(store.state.selectedVehicleID==vehicle.id ? "Active vehicle":"Select vehicle") { store.selectVehicle(vehicle.id) };Spacer();Button("Edit") { editing = vehicle } }
                        }.padding(14)
                    }
                }
            }
            HStack { Button("Load clearly labeled demo data") { store.loadDemo() };if store.state.trips.contains(where:{$0.isDemo}) { Button("Remove demo data") { store.removeDemo() } };Spacer() }.font(.system(size:11))
        }.sheet(isPresented:$adding) { VehicleEditor(vehicle:Vehicle(name:"")) }.sheet(item:$editing) { vehicle in VehicleEditor(vehicle:vehicle) }
    }
}
struct VehicleEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @State var vehicle:Vehicle
    @State private var scannerHost = "192.168.0.10"
    @State private var scannerPort = "35000"
    @State private var detecting = false
    @State private var detectionMessage = ""
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(vehicle.name.isEmpty ? "Add a vehicle":"Vehicle profile").font(.title2)
            Form {
                TextField("Vehicle name",text:$vehicle.name)
                HStack { TextField("Year",text:$vehicle.year);TextField("Make",text:$vehicle.make) }
                TextField("Model",text:$vehicle.model)
                TextField("VIN (optional)",text:$vehicle.vin)
                TextField("Notes",text:$vehicle.notes)
                Section("Scanner-assisted identity") {
                    Text("Read VIN from an ELM-compatible Wi-Fi/TCP scanner. Review the result before saving. BLE and USB scanner adapters are not integrated yet.").font(.system(size:11)).foregroundStyle(Theme.muted)
                    HStack { TextField("Scanner IP",text:$scannerHost);TextField("Port",text:$scannerPort).frame(width:85);Button(detecting ? "Reading…":"Read VIN") { detect() }.disabled(detecting) }
                    if !detectionMessage.isEmpty { Text(detectionMessage).font(.system(size:11)).foregroundStyle(Theme.muted) }
                }
            }.textFieldStyle(.roundedBorder)
            HStack { Spacer();Button("Cancel") { dismiss() };Button("Save vehicle") { do { vehicle.vin = vehicle.vin.uppercased().trimmingCharacters(in:.whitespacesAndNewlines);try store.saveVehicle(vehicle);dismiss() } catch { detectionMessage = error.localizedDescription } }.buttonStyle(.borderedProminent).disabled(vehicle.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width:580)
    }
    func detect() {
        guard let port = UInt16(scannerPort),port>0 else { detectionMessage = "Enter a valid scanner port.";return }
        detecting = true;detectionMessage = "Connecting to the scanner for a read-only Mode 09 VIN request…"
        Task {
            do { vehicle.vin = try await ScannerVINReader.read(host:scannerHost,port:port);detectionMessage = "VIN read successfully. Confirm year, make, and model manually before saving." }
            catch { detectionMessage = error.localizedDescription }
            detecting = false
        }
    }
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
                        HStack { Text(receipt.originalName).font(.system(size:12,weight:.medium));Spacer();Text(receipt.status.rawValue.uppercased()).foregroundStyle(receipt.status == .processed ? Theme.green:Theme.muted);if receipt.status == .failed { Button("Retry") { store.retry(receipt.id) } } }
                        Text(receipt.message).font(.system(size:11)).foregroundStyle(receipt.status == .failed ? Color.orange:Theme.muted).textSelection(.enabled)
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
            HStack { Label(store.serverStatus,systemImage:"server.rack").foregroundStyle(store.serverStatus=="Listening" ? Theme.green:Theme.muted);Spacer();Button(store.serverStatus=="Listening" ? "Stop server":"Start server") { if store.serverStatus=="Listening" { store.stopServer() } else { apply();store.startServer() } } }.font(.system(size:13))
            HStack(alignment:.top,spacing:14) {
                VStack(spacing:14) {
                    Panel(title:"Companion API") {
                        VStack(alignment:.leading,spacing:14) {
                            Text("Authenticated HTTP · schema v1").font(.system(size:13,weight:.medium))
                            HStack { TextField("Port",text:$port).frame(width:120);Toggle("Allow trusted local network",isOn:$allowLAN) }.font(.system(size:12))
                            Text(allowLAN ? "LAN endpoint: use this Mac's local IP with port \(port). Internet access and TLS are not configured.":"Loopback only: http://127.0.0.1:\(port)").font(.system(size:11)).foregroundStyle(Theme.muted).textSelection(.enabled)
                            HStack { Button("Apply settings") { apply() };Button("Copy pairing token") { store.copyToken() } }
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
                            Text("Originals are retained until you manage the library. Automatic 5,000 km raw-data expiry is not enabled in this release.").font(.system(size:11)).foregroundStyle(Theme.muted)
                            HStack { Button("Open data folder") { store.openLibrary() };Button("Back up library…") { store.backup() } }
                        }.padding(16)
                    }
                    Panel(title:"Mac lifecycle") {
                        VStack(alignment:.leading,spacing:14) {
                            Text("Closing the window keeps ingestion running while the app remains open. Use the menu-bar icon to reopen it or quit.").font(.system(size:12)).foregroundStyle(Theme.muted)
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
    func apply() { guard let port = UInt16(port),port>0 else { store.error = "Use a port from 1 to 65535.";return };store.configureServer(port:port,lan:allowLAN) }
}
