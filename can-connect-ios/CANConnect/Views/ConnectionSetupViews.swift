import SwiftUI

struct ScannerConnectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var accessories = MXPlusAccessories()
    @State private var kind: ScannerConnectionKind = .wifi
    @State private var selectedAccessoryID: Int?
    @State private var host = ""
    @State private var port = ""
    @State private var failure: String?
    var body: some View { SheetShell(title:"OBD scanner") {
        Picker("Connection",selection:$kind) { ForEach(ScannerConnectionKind.allCases) { Text($0.title).tag($0) } }.accessibilityIdentifier("scanner.transport")
        if kind == .wifi {
            InfoNote(text:"Join your ELM327 adapter's Wi-Fi and turn on ignition. This connection records standard OBD readings for the selected vehicle.")
        } else {
            InfoNote(text:"Plug in your OBDLink MX+, turn on ignition, and pair it in iPhone Settings → Bluetooth. Press its Connect button to enable pairing. Close other OBD apps before connecting here.")
            if accessories.items.isEmpty {
                InfoNote(text:"No authenticated MX+ found. Pair the adapter, allow a few seconds, then refresh. Generic Bluetooth ELM327 and OBDLink CX are different transports.")
            } else {
                Picker("OBDLink MX+",selection:$selectedAccessoryID) {
                    Text("Choose adapter").tag(nil as Int?)
                    ForEach(accessories.items) { item in Text(item.name).tag(Optional(item.id)) }
                }.accessibilityIdentifier("scanner.accessory")
            }
            Button("Pair / reconnect MX+") { accessories.showPicker() }.disabled(accessories.showingPicker).accessibilityIdentifier("scanner.pair")
            Button("Refresh paired adapters") { refresh() }.accessibilityIdentifier("scanner.refresh")
            if let message = accessories.pickerMessage { InfoNote(text:message) }
        }
        DataRow(label:"Vehicle",value:store.activeVehicle?.title ?? "Choose a vehicle")
        InfoNote(text:"Confirm that this is the connected vehicle. If both profiles provide VINs, they must match. Without a VIN, verify the vehicle yourself before connecting.")
        if kind == .wifi {
            TextField("Scanner address",text:$host).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityIdentifier("connection.host")
            TextField("TCP port",text:$port).keyboardType(.numberPad).textFieldStyle(.roundedBorder).accessibilityIdentifier("connection.port")
        }
        if let failure { Text(failure).foregroundStyle(Palette.red).font(.system(size:13)) }
        InfoNote(text:store.scanner.status)
        AppButton(title:"Connect selected vehicle",icon:"antenna.radiowaves.left.and.right") {
            do {
                let settings: ScannerSettings
                if kind == .wifi {
                    guard let tcp = UInt16(port), tcp > 0 else { throw AppFailure("Enter a TCP port from 1 to 65535.") }
                    settings = ScannerSettings(host:host.trimmingCharacters(in:.whitespacesAndNewlines),port:tcp)
                } else {
                    guard let item = accessories.items.first(where:{$0.id == selectedAccessoryID}) else { throw AppFailure("Pair and choose your OBDLink MX+, then connect.") }
                    settings = ScannerSettings(transport:.obdLinkMXPlus,accessorySerial:item.serial)
                }
                try store.connectScanner(settings:settings); store.selectedTab = .live; dismiss()
            } catch { failure = error.localizedDescription }
        }.disabled(store.recording || store.pendingGPS)
        if store.scanner.connected || store.scanner.connecting {
            AppButton(title:"Disconnect scanner",secondary:true) { store.disconnectScanner() }.disabled(store.recording)
        }
        InfoNote(text:"Scanner recordings continue when you switch apps or lock the phone. Stay within adapter range. Location access adds the GPS route; Finish saves the recording.")
    }.onAppear {
        let settings = store.activeVehicle?.scannerConnection ?? store.state.scanner
        kind = settings.kind; host = settings.host; port = String(settings.port)
        refresh()
        selectedAccessoryID = accessories.items.first(where:{$0.serial == settings.accessorySerial})?.id ?? selectedAccessoryID
    }.onChange(of:accessories.items.map(\.id)) { _,_ in selectOnlyAccessory() } }
    private func refresh() { accessories.refresh(); selectOnlyAccessory() }
    private func selectOnlyAccessory() {
        if !accessories.items.contains(where:{$0.id == selectedAccessoryID}) { selectedAccessoryID = accessories.items.count == 1 ? accessories.items.first?.id : nil }
    }
}

struct ServerConnectionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var address = ""
    @State private var token = ""
    @State private var busy = false
    @State private var message: String?
    @State private var work: Task<Void,Never>?
    var body: some View { SheetShell(title:"Mac server") {
        InfoNote(text:"Start the native Mac app's Server and enable its local-network access. Use its private address and copy its pairing token. Your phone must be able to reach that network.")
        TextField("http://mac-mini.local:8765",text:$address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).textFieldStyle(.roundedBorder).accessibilityIdentifier("server.address")
        SecureField("Pairing token (blank keeps saved token)",text:$token).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityIdentifier("server.token")
        Text("The token is saved in this iPhone's Keychain. HTTP uses your trusted private LAN without encryption; use HTTPS if your server provides it.").captionStyle()
        if let message { InfoNote(text:message) }
        AppButton(title:busy ? "Checking…" : "Pair & test server",icon:"desktopcomputer") {
            busy = true; message = nil
            work = Task {
                defer { busy = false }
                do { try await store.configureServer(address:address,token:token); token = ""; message = store.serverStatus }
                catch is CancellationError {} catch { message = error.localizedDescription }
            }
        }.disabled(busy || store.transferring)
        InfoNote(text:"Recordings stay on this iPhone through queued, failed and completed transfers. The Mac verifies the source bytes and returns a processing receipt. Transfers can be retried from Connect → Transfers.")
    }.onAppear { address = store.state.server.address }.onDisappear { work?.cancel(); token = "" } }
}
struct TransferQueueView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View { SheetShell(title:"Transfer queue") {
        if store.state.transfers.isEmpty { InfoNote(text:"No recordings queued. Sample recordings are excluded. Pair your server, then send recordings from Transfers.") }
        ForEach(store.state.transfers.reversed()) { item in
            VStack(alignment:.leading,spacing:8) {
                Text(item.name).font(.system(size:16))
                Text(item.status.rawValue == "awaitingReceipt" ? "Awaiting Mac processing" : item.status.rawValue.capitalized).foregroundStyle(item.status == .complete ? Palette.green : Palette.blue)
                Text(item.message).captionStyle()
                Text(item.endpoint).captionStyle()
            }.card()
        }
        AppButton(title:store.transferring ? "Transferring…" : "Retry / check receipts",icon:"arrow.clockwise") { Task { await store.sendQueued() } }.disabled(store.transferring)
    } }
}
